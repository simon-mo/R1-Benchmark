TensorRT-LLM guide:

Note: trtllm pip install doesn't work with uv. so the build won't be easy to reproduce.
```bash
# This doesn't work yet.
uvx-trt +args:
  UV_PYTHON=3.12 uv run --verbose \
    --with 'tensorrt_llm==0.18.1' \
    --extra-index-url https://pypi.nvidia.com \
    {{args}}
```

To run R1 on trtllm, as of 04/18/2025.
1. Build from source with docker container https://nvidia.github.io/TensorRT-LLM/installation/build-from-source-linux.html
2. Modify the file path, and run the following command:
```bash
docker run --rm -it --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
  --gpus=all \
  --network host \
  --volume /data/nm/models/DeepSeek-R1:/DeepSeek-R1  \
  --volume /data/xmo/TensorRT-LLM:/code/tensorrt_llm \
  --env "CCACHE_DIR=/code/tensorrt_llm/cpp/.ccache" \
  --env "CCACHE_BASEDIR=/code/tensorrt_llm" \
  --workdir /app/tensorrt_llm \
  --hostname brewster-release \
  --name tensorrt_llm-release-xmo \
  --tmpfs /tmp:exec \
  tensorrt_llm/release:latest
```
3. This will drop you into the container, which you can run some commands.
   Note that because prefix cache cannot be disabled, you have to restart the server after each scenario.
   For the non 30K scenario, you need to set a config yaml:
```yaml
# trt-extra-llm-api-options.yaml
pytorch_backend_config:
  enable_overlap_scheduler: true
  use_cuda_graph: true
  cuda_graph_max_batch_size: 256
  cuda_graph_padding_enabled: true
# This cause OOM
# kv_cache_config:
#   enable_block_reuse: false
```
4. Once the file is set, you can run the following command:
```bash
trtllm-serve /DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --max_num_tokens 11000 --kv_cache_free_gpu_memory_fraction 0.80 --trust_remote_code --extra_llm_api_options trt-extra-llm-api-options.yaml
# Benchmark command:
just run-scenario trt deepseek-r1 "1000,2000"
# Important: restart the server between each scenario to clear the prefix cache.
just run-scenario trt deepseek-r1 "5000,1000"
# Important: restart the server between each scenario to clear the prefix cache.
just run-scenario trt deepseek-r1 "10000,500"
# Important: restart the server between each scenario to clear the prefix cache.
just run-scenario trt deepseek-r1 "sharegpt"
```
5. For the 30K scenario, you need to run the following commands:
```bash
trtllm-serve /DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --kv_cache_free_gpu_memory_fraction .60 --max_batch_size 50 --max_seq_len 31000 --max_num_tokens 31000 --trust_remote_code
# Benchmark command:
just run-scenario trt deepseek-r1 "30000,100"
```
