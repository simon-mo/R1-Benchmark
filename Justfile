import 'scripts/utils.just'

UV_PYTHON_VERSION := "3.11"

# Model configurations
DEEPSEEK_R1_PATH := "deepseek-ai/DeepSeek-R1"
DEEPSEEK_R1_TP := "8"

QWQ_32B_PATH := "Qwen/QwQ-32B"
QWQ_32B_TP := "2"

LLAMA_8B_PATH := "neuralmagic/Meta-Llama-3.1-8B-Instruct-FP8"
LLAMA_8B_TP := "1"

LLAMA_3B_PATH := "neuralmagic/Llama-3.2-3B-Instruct-FP8"
LLAMA_3B_TP := "1"

QWEN_1_5B_PATH := "Qwen/Qwen2.5-1.5B-Instruct"
QWEN_1_5B_TP := "1"

# Default recipe, list all recipes
list:
  @just --list
  @echo "Available Models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b"

# Run reproducible vLLM installation with `just uvx-vllm vllm serve ...`
[group('serve')]
uvx-vllm +args:
  #!/usr/bin/env bash
  UV_PYTHON={{UV_PYTHON_VERSION}} uvx --with setuptools \
    --with 'vllm==0.8.4' \
    --with https://github.com/flashinfer-ai/flashinfer/releases/download/v0.2.2/flashinfer_python-0.2.2+cu124torch2.6-cp38-abi3-linux_x86_64.whl \
    {{args}}

# Run reproducible SGLang installation with `just uvx-sgl python -m sglang.launch_server ...`
[group('serve')]
uvx-sgl +args:
  #!/usr/bin/env bash
  UV_PYTHON={{UV_PYTHON_VERSION}} uv run --with setuptools \
    --with 'sglang[all]==0.4.5' \
    --find-links https://flashinfer.ai/whl/cu124/torch2.5/flashinfer-python \
    {{args}}

# Base recipes for serving vLLM
_serve-vllm model_path tp="1":
  #!/usr/bin/env bash
  set -ex

  VLLM_SERVE_ARGS="--trust-remote-code --no-enable-prefix-caching --disable-log-requests"

  if [[ "{{model_path}}" == *"DeepSeek-R1"* ]]; then
    VLLM_SERVE_ARGS="${VLLM_SERVE_ARGS} --enable-expert-parallel"
  else
    VLLM_SERVE_ARGS="${VLLM_SERVE_ARGS} --load-format dummy"
  fi

  VLLM_USE_FLASHINFER_SAMPLER=1 just uvx-vllm vllm serve {{model_path}} \
    --tensor-parallel-size {{tp}} \
    ${VLLM_SERVE_ARGS}

# Base recipes for serving SGLang
_serve-sgl model_path tp="1":
  #!/usr/bin/env bash
  SGL_SERVE_ARGS="--trust-remote-code --enable-flashinfer-mla --disable-radix-cache"

  if [[ "{{model_path}}" == *"DeepSeek-R1"* ]]; then
    # Flag guide: https://github.com/sgl-project/sglang/tree/main/benchmark/deepseek_v3
    SGL_SERVE_ARGS="${SGL_SERVE_ARGS} --enable-torch-compile --torch-compile-max-bs 8 --expert-parallel-size 8"
  else
    SGL_SERVE_ARGS="${SGL_SERVE_ARGS} --load-format dummy"
  fi

  SGL_ENABLE_JIT_DEEPGEMM=1 just uvx-sgl python -m sglang.launch_server \
    --model {{model_path}} \
    --port 8000 \
    --tp {{tp}} \
    ${SGL_SERVE_ARGS}

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

_get-model-tp model:
  #!/usr/bin/env bash
  case "{{model}}" in
    "deepseek-r1")
      echo {{DEEPSEEK_R1_TP}}
      ;;
    "qwq-32b")
      echo {{QWQ_32B_TP}}
      ;;
    "llama-8b")
      echo {{LLAMA_8B_TP}}
      ;;
    "llama-3b")
      echo {{LLAMA_3B_TP}}
      ;;
    "qwen-1.5b")
      echo {{QWEN_1_5B_TP}}
      ;;
    *)
      echo "Invalid model. Available models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b" >&2
      exit 1
      ;;
  esac

# Unified serve command for both backends.
[group('serve')]
serve backend="vllm" model="deepseek-r1":
    #!/usr/bin/env bash
    # Validate backend
    if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ] && [ "{{backend}}" != "trt" ]; then
        echo "Invalid backend. Available backends: vllm, sgl, trt"
        exit 1
    fi

    if [ "{{backend}}" == "trt" ]; then
      echo "Please check scripts/trt.just for instructions on how to run TRT-LLM."
      exit 1
    fi

    # Get model path and tensor parallel size
    MODEL_PATH=$(just _get-model-path {{model}})
    TP=$(just _get-model-tp {{model}})

    just _serve-{{backend}} ${MODEL_PATH} ${TP}

# Run a single benchmark scenario
[group('benchmark')]
run-scenario backend="vllm" model="deepseek-r1" lengths="1000,1000":
    #!/usr/bin/env bash
    set -ex

    just _ensure-results-dir {{model}}

    # Validate backend
    if [ "{{backend}}" != "vllm" ] && [ "{{backend}}" != "sgl" ] && [ "{{backend}}" != "trt" ]; then
        echo "Invalid backend. Available backends: vllm, sgl, trt"
        exit 1
    fi

    # Get model path
    MODEL_PATH=$(just _get-model-path {{model}})

    # Parse input and output lengths
    INPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f1)
    OUTPUT_LEN=$(echo "{{lengths}}" | cut -d',' -f2)

    if [[ "{{lengths}}" == "sharegpt" ]]; then
      uv run --with-requirements requirements-benchmark.txt \
        vllm-benchmarks/benchmarks/benchmark_serving.py \
        --model ${MODEL_PATH} \
        --dataset-name sharegpt --ignore-eos \
        --dataset-path vllm-benchmarks/benchmarks/sharegpt.json \
        --num-prompts 500 \
        --request-rate 10 \
        --save-result \
        --result-dir results/{{model}} \
        --result-filename {{backend}}-sharegpt.json
    else
      uv run --with-requirements requirements-benchmark.txt \
          vllm-benchmarks/benchmarks/benchmark_serving.py \
          --model ${MODEL_PATH} \
          --dataset-name random --ignore-eos \
          --num-prompts 50 \
          --request-rate 10 \
          --random-input-len ${INPUT_LEN} \
          --random-output-len ${OUTPUT_LEN} \
          --save-result \
          --result-dir results/{{model}} \
          --result-filename {{backend}}-${INPUT_LEN}-${OUTPUT_LEN}.json
    fi

# Run benchmark sweeps for a specific backend and model
[group('benchmark')]
run-sweeps backend="vllm" model="deepseek-r1":
  #!/usr/bin/env bash
  set -ex

  for pair in "1000,2000" "5000,1000" "10000,500" "30000,100" "sharegpt"; do
    # trt crashes on 30k input.
    if [ "{{backend}}" == "trt" ] && [ "${pair}" == "30000,100" ]; then
      continue
    fi

    just run-scenario {{backend}} {{model}} ${pair}

    sleep 6
  done

# Generate table and graph
[group('benchmark')]
show-results model="deepseek-r1":
  uv run --with rich --with pandas extract-result.py results/{{model}}
