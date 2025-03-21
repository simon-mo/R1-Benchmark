UV_PYTHON_VERSION := "3.11"

# Common arguments for all serving commands
COMMON_SERVE_ARGS := "--trust-remote-code"

# VLLM-specific arguments and env
VLLM_SERVE_ARGS := COMMON_SERVE_ARGS + "  --load-format dummy --no-enable-prefix-caching --disable-log-requests"
VLLM_ENV := "VLLM_USE_FLASHINFER_SAMPLER=1"

# SGL-specific arguments and env
SGL_ENV := "SGL_ENABLE_JIT_DEEPGEMM=1"
SGL_SERVE_ARGS := COMMON_SERVE_ARGS + " --enable-flashinfer-mla --disable-radix-cache"

# Model configurations
DEEPSEEK_R1_PATH := "/home/vllm-dev/DeepSeek-R1"
DEEPSEEK_R1_TP := "8"

QWQ_32B_PATH := "Qwen/QwQ-32B"
QWQ_32B_TP := "2"

LLAMA_8B_PATH := "deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
LLAMA_8B_TP := "1"

# Port configurations
VLLM_PORT := "8000"
SGL_PORT := "30000"

list:
  just --list

# Recipe for running uvx with vllm configuration
uvx-vllm +args:
  UV_PYTHON={{UV_PYTHON_VERSION}} uvx --with setuptools \
    --with 'vllm==0.8.1' \
    --with https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2.post1/flashinfer_python-0.2.2.post1+cu124torch2.6-cp38-abi3-linux_x86_64.whl \
    {{args}}

# Recipe for running uvx with sglang configuration
uvx-sgl +args:
  #!/usr/bin/env bash
  UV_PYTHON={{UV_PYTHON_VERSION}} uvx --with setuptools \
    --with 'sglang[all]==0.4.4.post1' \
    --find-links https://flashinfer.ai/whl/cu124/torch2.6/flashinfer-python \
    {{args}}

# Base recipes for serving
_serve-vllm model_path tp="1":
  {{VLLM_ENV}} just uvx-vllm vllm serve {{model_path}} \
    --tensor-parallel-size {{tp}} \
    {{VLLM_SERVE_ARGS}}

_serve-sgl model_path tp="1":
  #!/usr/bin/env bash
  if [[ "{{model_path}}" == *"DeepSeek-R1"* ]]; then
    SGL_ARGS="{{SGL_SERVE_ARGS}} --enable-torch-compile --torch-compile-max-bs 8"
  else
    SGL_ARGS="{{SGL_SERVE_ARGS}} --load-format dummy"
  fi
  {{SGL_ENV}} just uvx-sgl python -m sglang.launch_server \
    --model {{model_path}} \
    --tp {{tp}} \
    ${SGL_ARGS}

# Unified serve command for both backends
serve backend="vllm" model="deepseek-r1":
  #!/usr/bin/env bash
  # Validate backend
  if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ]; then
    echo "Invalid backend. Available backends: vllm, sgl"
    exit 1
  fi

  # Get model configuration and serve
  case "{{model}}" in
    "deepseek-r1")
      just _serve-{{backend}} {{DEEPSEEK_R1_PATH}} {{DEEPSEEK_R1_TP}}
      ;;
    "qwq-32b")
      just _serve-{{backend}} {{QWQ_32B_PATH}} {{QWQ_32B_TP}}
      ;;
    "llama-8b")
      just _serve-{{backend}} {{LLAMA_8B_PATH}} {{LLAMA_8B_TP}}
      ;;
    *)
      echo "Invalid model. Available models: deepseek-r1, qwq-32b, llama-8b"
      exit 1
      ;;
  esac

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

ensure-results-dir model:
  mkdir -p results/{{model}}

# Run a single benchmark scenario
run-scenario backend="vllm" model="deepseek-r1" lengths="1000,1000":
  #!/usr/bin/env bash
  set -ex

  just ensure-results-dir {{model}}

  # Validate backend
  if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ]; then
    echo "Invalid backend. Available backends: vllm, sgl"
    exit 1
  fi

  # Set port based on backend
  PORT=$([[ "{{backend}}" = "sgl" ]] && echo "{{SGL_PORT}}" || echo "{{VLLM_PORT}}")

  # Get model path based on alias
  case "{{model}}" in
    "deepseek-r1")
      MODEL_PATH={{DEEPSEEK_R1_PATH}}
      ;;
    "qwq-32b")
      MODEL_PATH={{QWQ_32B_PATH}}
      ;;
    "llama-8b")
      MODEL_PATH={{LLAMA_8B_PATH}}
      ;;
    *)
      echo "Invalid model. Available models: deepseek-r1, qwq-32b, llama-8b"
      exit 1
      ;;
  esac

  # Parse input and output lengths
  INPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f1)
  OUTPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f2)

  uvx --with-requirements requirements-benchmark.txt \
    python vllm-benchmarks/benchmarks/benchmark_serving.py \
    --model ${MODEL_PATH} \
    --port ${PORT} \
    --dataset-name random --ignore-eos \
    --num-prompts 50 \
    --request-rate 10 \
    --random-input-len ${INPUT_LEN} \
    --random-output-len ${OUTPUT_LEN} \
    --save-result \
    --result-dir results/{{model}} \
    --result-filename {{backend}}-${INPUT_LEN}-${OUTPUT_LEN}.json

# Run benchmark sweeps for a specific backend and model
run-sweeps backend="vllm" model="deepseek-r1":
  #!/usr/bin/env bash
  for pair in "1000,2000" "5000,1000" "10000,500" "32000,100"; do
    just run-scenario {{backend}} {{model}} ${pair}
  done

show-results model="deepseek-r1":
  uvx --with rich --with pandas python extract-result.py results/{{model}}