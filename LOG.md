# Experiment Log

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


