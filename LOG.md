# Experiment Log

## 04/18/2025
Simon:
* TRT-LLM's new flag that's suggested by NVIDIA. This is still running on the same container built from main as of 04/15/2025. I tried latest release `v0.18.2` (04/16/2025)
    * For all the workloads except the 30000/100 dataset please use this command:
    ```
    trtllm-serve deepseek-ai/DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --max_num_tokens 11000 --kv_cache_free_gpu_memory_fraction 0.80 --trust_remote_code --extra_llm_api_options ./extra_llm_api_options.yaml
    ```
    and this for the extra_llm_api_options.yaml:
    ```
    pytorch_backend_config:
      enable_overlap_scheduler: true
      use_cuda_graph: true
      cuda_graph_max_batch_size: 256
      cuda_graph_padding_enabled: true
    ```
    * For the 30000/100 dataset please use this command:
    ```
    trtllm-serve deepseek-ai/DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --kv_cache_free_gpu_memory_fraction .60 --max_batch_size 50 --max_seq_len 31000 --max_num_tokens 31000 --trust_remote_code
    ```
    Note no extra_llm_api_options are needed in this case.
    * I also found the prefix cache is turned on by default and I cannot disable it without OOM. So I restarted the server between each scenario.
    * Detailed commands are in `trt-guide.md`.
* SGLang: @zhyncs has [this repro command](https://github.com/sgl-project/sglang/issues/5514) on 0.4.5.post1 (04/15/2025) turning on data parallelism in vLLM. Some notable changes:
    * Bugfix in DP.
    * The new version also uses FA3 MLA by default, supported mixed chunk using similar strategy as vLLM.
    ```
    SGL_ENABLE_JIT_DEEPGEMM=1 python3 -m sglang.launch_server --model deepseek-ai/DeepSeek-V3 --tp 8 --trust-remote-code --enable-dp-attention --dp-size 8
    ```
    * ^ This means we have removed flash mla and expert parallel flag.
    * Given this I should probably turn off EP in vLLM for direct comparison.
    * I still ended up setting `--disable-radix-cache` as a general way to prevent prefix caching. So the benchmark script doesn't need to include flush cache. This is the only difference from what I am running as compared to @zhyncs's command.
    * I'm seeing `[2025-04-18 13:24:29 TP0] DeepGEMM JIT code generation <gemm_fp8_fp8_bf16_nt>: M=7138, N=576, K=7168. Please wait.` not just in the startup, but also as requests arrive in different workloads! So I think I need to run the full sweep once, discard the result, and run the sweep again to get the final result. Otherwise the output throughput is halved: 639.78 for 1000/2000 case instead of 1k+ toks/s.... Ah! It's cached on disk. So subsequent runs don't need double sweep.
* SGLang harness: I also implemented a way to use SGLang's bench_serving harness. Use it as the last argument in `just run-sweeps` or `just run-scenario`. I mostly used to diagnose the reproducibility issue. But turns out it is the CPU issue below.
* I spent some times trying to figure out why SGLang's number is not reproducible. Turns out Berkeley's DGX H200 has Intel Xeon 8480C while Nebius's H200 has 8468, which clocks differently (8468 is faster). I will run a subset of tests in Nebius's H200 (it's $$$ to run them and I don't want to build TRT container again).
* Ok planning a final set of results for today:
  * Nebius's H200: [vLLM, vLLM-EP, SGL]
  * Berkeley's H200: [vLLM, vLLM-EP, SGL, TRT-LLM]

## 04/16/2025
Simon:
* Refactored the code again and getting it ready for public usage.
* Identified that vLLM was outperforming a lot due to usage of dummy weights, which effect MoE's token routing.
  We should not use dummy weights for any MoE models. Dense models should be okay with dummy weights.
* Battled TRT-LLM set up for a few days, got a version working when built from source `2e669133c2767733c89375953bc4a94363e37985`.
  It has EP enabled. See `scripts/trt.just` for detailed commands.
  I used some commands recommended by NVIDIA. The original recommendation is
  ```
  trtllm-serve deepseek-ai/DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --kv_cache_free_gpu_memory_fraction 0.90 --max_batch_size 576 --max_num_tokens 1664 --trust_remote_code  --max_seq_len 2000 --extra_llm_api_options ./extra_llm_api_options.yaml

  #extra-llm-api-config.yml
  pytorch_backend_config:
  enable_overlap_scheduler: true
  use_cuda_graph: true
  cuda_graph_padding_enabled: true
  cuda_graph_batch_sizes: [1, 576]
  enable_attention_dp: true
  ```
  But the working version is the following (except 30k input)
  ```
  trtllm-serve /DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --kv_cache_free_gpu_memory_fraction 0.8 --max_batch_size 50 --max_num_tokens 11000
  ```
* SGLang DP: I tried to use dp attention per recommendation on the [doc](https://github.com/sgl-project/sglang/tree/main/benchmark/deepseek_v3) but it is not compatible with torch compile.
  So I tried running it without compile, and added EP.
  ```
  SGL_SERVE_ARGS="${SGL_SERVE_ARGS} --enable-dp-attention --data-parallel-size 8 --expert-parallel-size 8"
  ```
  The result is worse than torch compile + EP.
* SGLang DeepEP: I tried to use DeepEP but it crashed at nvshmem detect topo failed for single node.
  ```
  SGL_SERVE_ARGS="${SGL_SERVE_ARGS} --enable-deepep-moe --deepep-mode auto"
  ```
  I think this is mostly still my environment's problem but I ran out of cycles to debug it. So far I have tried:
  * Use the official docker image
  ```
  # clone SGL
  docker build -t sgl-deepep -f Dockerfile.deepep .
  docker run -it --rm --gpus all -p 30000:30000 --ipc=host \
    -v {{model_path}}:{{model_path}} \
    -e SGL_ENABLE_JIT_DEEPGEMM=1 \
    sgl-deepep:latest \
    python -m sglang.launch_server \
    --model {{model_path}} \
    --tp {{tp}} \
    ${SGL_ARGS}
  ```
  * Use [pack_nvshmem](https://github.com/youkaichao/pack_nvshmem) from Kaichao and build DeepEP from source.
  * Set `NVSHMEM_IB_ENABLE_IBGDA=0` when compiling nvshmem. This approach didn't compile.
  In the end the error is the same.
  ```
  /sgl-workspace/nvshmem/src/host/init/init.cu:nvshmemi_check_state_and_init:1080: nvshmem initialization failed, exiting
  /sgl-workspace/nvshmem/src/host/transport/transport.cpp:nvshmemi_transport_init:275: init failed for transport: IBGDA
  /sgl-workspace/nvshmem/src/host/init/init.cu:995: non-zero status: 7 nvshmem detect topo failed
  ```


