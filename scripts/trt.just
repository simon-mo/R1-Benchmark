# trtllm guide:

# Note: trtllm pip install doesn't work with uv. so the build won't be easy to reproduce.
# uvx-trt +args:
#   UV_PYTHON=3.12 uv run --verbose \
#     --with 'tensorrt_llm==0.18.1' \
#     --extra-index-url https://pypi.nvidia.com \
#     {{args}}

# To run R1 on trtllm, as of 04/16/2025.
# 1. Build from source with docker container https://nvidia.github.io/TensorRT-LLM/installation/build-from-source-linux.html
# 2. Modify the file path, and run the following command:
# docker run --rm -it --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 \
#   --gpus=all \
#   --network host \
#   --volume /data/nm/models/DeepSeek-R1:/DeepSeek-R1  \
#   --volume /data/xmo/TensorRT-LLM:/code/tensorrt_llm \
#   --env "CCACHE_DIR=/code/tensorrt_llm/cpp/.ccache" \
#   --env "CCACHE_BASEDIR=/code/tensorrt_llm" \
#   --workdir /app/tensorrt_llm \
#   --hostname brewster-release \
#   --name tensorrt_llm-release-xmo \
#   --tmpfs /tmp:exec \
#   tensorrt_llm/release:latest
# 3. This will drop you into the container, which you can run:
#   trtllm-serve /DeepSeek-R1 --backend pytorch --tp_size 8 --ep_size 8 --kv_cache_free_gpu_memory_fraction 0.8 --max_batch_size 50 --max_num_tokens 11000
