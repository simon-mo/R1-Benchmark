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
# DEEPSEEK_R1_PATH := "deepseek-ai/DeepSeek-R1"
DEEPSEEK_R1_PATH := "/data/nm/models/DeepSeek-R1"
DEEPSEEK_R1_TP := "8"

QWQ_32B_PATH := "Qwen/QwQ-32B"
QWQ_32B_TP := "2"

LLAMA_8B_PATH := "neuralmagic/Meta-Llama-3.1-8B-Instruct-FP8"
LLAMA_8B_TP := "1"

LLAMA_3B_PATH := "neuralmagic/Llama-3.2-3B-Instruct-FP8"
LLAMA_3B_TP := "1"

QWEN_1_5B_PATH := "Qwen/Qwen2.5-1.5B-Instruct"
QWEN_1_5B_TP := "1"

# Port configurations
VLLM_PORT := "8000"
SGL_PORT := "30000"

# Default recipe, list all recipes
list:
  @just --list
  @echo "Available Models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b"

# Run reproducible vLLM installation with `just uvx-vllm vllm serve ...`
uvx-vllm +args:
  UV_PYTHON={{UV_PYTHON_VERSION}} uvx --with setuptools \
    --with 'vllm==0.8.3' \
    --with https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2/flashinfer_python-0.2.2+cu124torch2.6-cp38-abi3-linux_x86_64.whl \
    {{args}} # (March 29: FlashInfer released v0.2.4, but it's not compatible with torch 2.6)

# Run reproducible SGLang installation with `just uvx-sgl python -m sglang.launch_server ...`
uvx-sgl +args:
  #!/usr/bin/env bash
  UV_PYTHON={{UV_PYTHON_VERSION}} uv run --with setuptools \
    --with 'sglang[all]==0.4.5' \
    --with '/data/xmo/DeepEP/dist/deep_ep-1.0.0+a0c6931-cp311-cp311-linux_x86_64.whl' \
    --find-links https://flashinfer.ai/whl/cu124/torch2.5/flashinfer-python \
    {{args}}

# Run reproducible TensorRT-LLM installation with `just uvx-trt trtllm-serve ...`
uvx-trt +args:
  UV_PYTHON={{UV_PYTHON_VERSION}} uv run \
    --with 'tensorrt_llm==0.18.1' \
    --extra-index-url https://pypi.nvidia.com \
    {{args}}

# Base recipes for serving
_serve-vllm model_path tp="1":
  {{VLLM_ENV}} just uvx-vllm vllm serve {{model_path}} \
    --tensor-parallel-size {{tp}} \
    {{VLLM_SERVE_ARGS}}

_serve-sgl model_path tp="1":
  #!/usr/bin/env bash
  if [[ "{{model_path}}" == *"DeepSeek-R1"* ]]; then
    # https://github.com/sgl-project/sglang/tree/main/benchmark/deepseek_v3
    SGL_ARGS="{{SGL_SERVE_ARGS}} --enable-torch-compile --torch-compile-max-bs 8 --expert-parallel-size 8"

    # (04/11/25): DP is crashing with torch compile, and the result with this is worse than no dp attention.
    # SGL_ARGS="{{SGL_SERVE_ARGS}} --enable-dp-attention --data-parallel-size 8"

    # (04/14/25): Tried DeepEP bad crashed at nvshmem detect topo failed for single node.
    # SGL_ARGS="{{SGL_SERVE_ARGS}} --enable-deepep-moe --deepep-mode auto"
  else
    # Dummy format doesn't work for DeepSeek-R1 in SGL.
    SGL_ARGS="{{SGL_SERVE_ARGS}} --load-format dummy"
  fi
  {{SGL_ENV}} just uvx-sgl python -m sglang.launch_server \
    --model {{model_path}} \
    --tp {{tp}} \
    ${SGL_ARGS}

_serve-trtllm model_path tp="1":
  # (04/14/2025): NVIDIA team recommended the following for 1k:1k settings but I removed it to keep it general.
  # --max_num_tokens 1170 \
  # --max_seq_len 2000 \
  just uvx-trt trtllm-serve {{model_path}} \
    --backend pytorch \
    --tp_size {{tp}} \
    --ep_size {{tp}} \
    --kv_cache_free_gpu_memory_fraction 0.90 \
    --max_batch_size 324 \
    --trust_remote_code  \
    --extra_llm_api_options ./configs/trtllm-deepseek-r1-options.yaml

# Helper command to get model path from alias
_get-model-path model:
    #!/usr/bin/env bash
    case "{{model}}" in
        "deepseek-r1")
            echo {{DEEPSEEK_R1_PATH}}
            ;;
        "qwq-32b")
            echo {{QWQ_32B_PATH}}
            ;;
        "llama-8b")
            echo {{LLAMA_8B_PATH}}
            ;;
        "llama-3b")
            echo {{LLAMA_3B_PATH}}
            ;;
        "qwen-1.5b")
            echo {{QWEN_1_5B_PATH}}
            ;;
        *)
            echo "Invalid model. Available models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b" >&2
            exit 1
            ;;
    esac

# Unified serve command for both backends.
serve backend="vllm" model="deepseek-r1":
    #!/usr/bin/env bash
    # Validate backend
    if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ]; then
        echo "Invalid backend. Available backends: vllm, sgl"
        exit 1
    fi

    # Get model path and tensor parallel size
    MODEL_PATH=$(just _get-model-path {{model}})
    case "{{model}}" in
        "deepseek-r1")
            TP={{DEEPSEEK_R1_TP}}
            ;;
        "qwq-32b")
            TP={{QWQ_32B_TP}}
            ;;
        "llama-8b")
            TP={{LLAMA_8B_TP}}
            ;;
        "llama-3b")
            TP={{LLAMA_3B_TP}}
            ;;
    esac

    just _serve-{{backend}} ${MODEL_PATH} ${TP}

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

_ensure-results-dir model:
  mkdir -p results/{{model}}

# Run a single benchmark scenario
run-scenario backend="vllm" model="deepseek-r1" lengths="1000,1000":
    #!/usr/bin/env bash
    set -ex

    just _ensure-results-dir {{model}}

    # Validate backend
    if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ]; then
        echo "Invalid backend. Available backends: vllm, sgl"
        exit 1
    fi

    # Set port based on backend
    PORT=$([[ "{{backend}}" = "sgl" ]] && echo "{{SGL_PORT}}" || echo "{{VLLM_PORT}}")

    # Get model path
    MODEL_PATH=$(just _get-model-path {{model}})

    # Parse input and output lengths
    INPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f1)
    OUTPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f2)

    uv run --with-requirements requirements-benchmark.txt \
        vllm-benchmarks/benchmarks/benchmark_serving.py \
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
  set -ex

  for pair in "1000,2000" "5000,1000" "10000,500" "30000,100"; do
    just run-scenario {{backend}} {{model}} ${pair}
    sleep 10
  done

# Generate table and graph
show-results model="deepseek-r1":
  uv run --with rich --with pandas extract-result.py results/{{model}}

# Run guidellm's qps sweep
run-guidellm model="deepseek-r1" prompt_tokens="512" generated_tokens="128":
    #!/usr/bin/env bash
    set -ex

    # Get model path
    MODEL_PATH=$(just _get-model-path {{model}})

    just _ensure-results-dir {{model}}

    uvx --with guidellm guidellm \
        --target "http://localhost:8000/v1" \
        --model "$MODEL_PATH" \
        --data-type emulated \
        --data "prompt_tokens={{prompt_tokens}},generated_tokens={{generated_tokens}}" \
        --max-seconds 30 \
        --output-path results/{{model}}/guidellm-{{prompt_tokens}}-{{generated_tokens}}.json

# Utility to download models from huggingface
download-model model="deepseek-r1":
    #!/usr/bin/env bash
    set -ex

    # Get model path
    MODEL_PATH=$(just _get-model-path {{model}})

    huggingface-cli download ${MODEL_PATH}
