list:
  just --list

# Recipe for running uvx with vllm configuration
uvx-vllm +args:
  uvx --with setuptools \
    --with vllm --extra-index-url https://wheels.vllm.ai/nightly \
    --with https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2.post1/flashinfer_python-0.2.2.post1+cu124torch2.6-cp38-abi3-linux_x86_64.whl \
    {{args}}

# Recipe for running uvx with sglang configuration
uvx-sgl +args:
  #!/usr/bin/env bash
  uvx --with setuptools \
    --with 'transformers<4.49.0' \
    --with 'sglang[all]>=0.4.3.post2' \
    --find-links https://flashinfer.ai/whl/cu124/torch2.6/flashinfer-python \
    {{args}}

list-versions:
  just uvx-vllm vllm --version
  just uvx-sgl python -c "'import sglang; print(sglang.__version__)'"

# Clone only the benchmarks directory from vllm repository
clone-vllm-benchmarks target_dir="vllm-benchmarks":
  #!/usr/bin/env bash
  set -euo pipefail
  rm -rf {{target_dir}}
  git clone --filter=blob:none --no-checkout https://github.com/vllm-project/vllm.git {{target_dir}}
  cd {{target_dir}}
  git sparse-checkout init --no-cone
  echo "benchmarks/**" > .git/info/sparse-checkout
  git checkout

serve-vllm:
  VLLM_USE_V1=1 VLLM_ATTENTION_BACKEND=FLASHMLA VLLM_USE_FLASHINFER_SAMPLER=1 \
    just uvx-vllm vllm serve /home/vllm-dev/DeepSeek-R1 \
      --tensor-parallel-size 8 \
      --trust-remote-code \
      --load-format dummy \
      --disable-log-requests \
      --no-enable-prefix-caching

serve-vllm-qwq-32b:
  VLLM_USE_FLASHINFER_SAMPLER=1 \
    just uvx-vllm vllm serve Qwen/QwQ-32B \
      --tensor-parallel-size 4 \
      --trust-remote-code \
      --disable-log-requests \
      --no-enable-prefix-caching

serve-vllm-llama-8b:
  just uvx-vllm vllm serve deepseek-ai/DeepSeek-R1-Distill-Llama-8B \
    --tensor-parallel-size 1 \
    --trust-remote-code \
    --disable-log-requests \
    --no-enable-prefix-caching

serve-sgl:
  # SGL doesn't support load-format dummy for R1,
  # so you do need to download the model first.
  SGL_ENABLE_JIT_DEEPGEMM=1 \
  just uvx-sgl python -m sglang.launch_server \
    --model /home/vllm-dev/DeepSeek-R1 \
    --trust-remote-code \
    --enable-torch-compile \
    --torch-compile-max-bs 8 \
    --enable-flashinfer-mla \
    --tp 8
  # We should disable radix cache but https://github.com/sgl-project/sglang/issues/4298
  # --disable-radix-cache

serve-sgl-qwq-32b:
  just uvx-sgl python -m sglang.launch_server \
    --model Qwen/QwQ-32B \
    --trust-remote-code \
    --tp 4 \
    --disable-radix-cache

serve-sgl-llama-8b:
  just uvx-sgl python -m sglang.launch_server \
    --model deepseek-ai/DeepSeek-R1-Distill-Llama-8B \
    --trust-remote-code \
    --tp 1 \
    --disable-radix-cache

ensure-results-dir:
  mkdir -p results

run-scenario backend_name="vllm" input_len="100" output_len="100" model_name="/home/vllm-dev/DeepSeek-R1": ensure-results-dir
  #!/usr/bin/env bash
  if [ "{{backend_name}}" = "sgl" ]; then
    PORT=30000
  else
    PORT=8000
  fi
  uvx --with-requirements requirements-benchmark.txt \
    python vllm-benchmarks/benchmarks/benchmark_serving.py \
    --model {{model_name}} \
    --port ${PORT} \
    --dataset-name random --ignore-eos \
    --num-prompts 50 \
    --request-rate 10 \
    --random-input-len {{input_len}} --random-output-len {{output_len}} \
    --save-result \
    --result-dir results \
    --result-filename {{backend_name}}-{{input_len}}-{{output_len}}.json

run-sweeps backend_name="vllm" model_name="/home/vllm-dev/DeepSeek-R1":
  just run-scenario {{backend_name}} "1000" "1000" {{model_name}}
  just run-scenario {{backend_name}} "5000" "1000" {{model_name}}
  just run-scenario {{backend_name}} "10000" "1000" {{model_name}}
  just run-scenario {{backend_name}} "32000" "1000" {{model_name}}

show-results:
  uvx --with rich --with pandas python extract-result.py