# Run guidellm's qps sweep
[group('utility')]
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
[group('utility')]
download-model model="deepseek-r1":
    #!/usr/bin/env bash
    set -ex

    # Get model path
    MODEL_PATH=$(just _get-model-path {{model}})

    huggingface-cli download ${MODEL_PATH}

# Utility to download datasets
[group('utility')]
download-dataset dataset="sharegpt":
  #!/usr/bin/env bash
  set -ex

  if [[ "{{dataset}}" == "sharegpt" ]]; then
    wget https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json -O vllm-benchmarks/benchmarks/sharegpt.json
  else
    echo "Invalid dataset. Available datasets: sharegpt"
  fi

# List versions of vLLM and SGLang
[group('utility')]
list-versions:
  just uvx-vllm vllm --version
  just uvx-sgl python -c "'import sglang; print(sglang.__version__)'"

# Clone only the benchmarks directory from vllm repository
[group('utility')]
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
