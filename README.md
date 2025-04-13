This repo is used for vLLM's interative performance spot check.
For automated benchmark, please refer to vLLM's nightly set.

The goal for this repo is establish a set of commonly used benchmarks and worklaods for comparative analysis.

# Latest Numbers

As of April 11, 2025: H200, vLLM 0.8.4, SGL v0.4.5
```
    Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃    SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 1710.28 │ 441.42 │ 287.4% │
│         5000 │          1000 │ 1140.25 │ 636.37 │  79.2% │
│        10000 │           500 │  518.24 │ 260.94 │  98.6% │
│        30000 │           100 │   32.56 │  17.74 │  83.5% │
└──────────────┴───────────────┴─────────┴────────┴────────┘
                     Model: deepseek-r1
```

As of March 30, 2025: H200, vLLM 0.8.2, SGL v0.4.4
```
     Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃    SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 1688.75 │ 426.47 │ 296.0% │
│         5000 │          1000 │ 1138.18 │ 650.95 │  74.8% │
│        10000 │           500 │  368.27 │ 259.88 │  41.7% │
│        32000 │           100 │   34.71 │  19.15 │  81.3% │
└──────────────┴───────────────┴─────────┴────────┴────────┘
                     Model: deepseek-r1


     Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃     SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 4528.55 │ 4031.48 │  12.3% │
│         5000 │          1000 │ 2446.93 │ 1854.14 │  32.0% │
│        10000 │           500 │ 1149.16 │  891.53 │  28.9% │
│        32000 │           100 │   96.62 │   70.84 │  36.4% │
└──────────────┴───────────────┴─────────┴─────────┴────────┘
                       Model: llama-8b

```

# Usage
* All the commands are defined in `Justfile`.
* The environment should be exactly reproducible by using `uv`.

1. Install uv and just
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
```

2. Create the environment for vLLM and SGL
```bash
just list-versions
```

3. Clone vLLM benchmark scripts
```bash
just clone-vllm-benchmarks
```

4. Run the benchmark

In short: Run the server via `just serve vllm` or `just serve sgl`. Run the benchmark via `just run-sweeps` or `just run-sweeps sgl`.

* Note that for SGL, you need to download the model first because it cannot run with dummy format.
  Please modify the `Justfile` to point to the correct path.

* For TP1 (Llama-3.1-8B), you need to use `just serve vllm llama-8b` and `just serve sgl llama-8b`. With `just run-sweeps vllm llama-8b` and `just run-sweeps sgl llama-8b`, you can get the results.

* For TP4 (Qwen/QwQ-32B), you need to use `just serve vllm qwq-32b` and `just serve sgl qwq-32b`. With `just run-sweeps vllm qwq-32b` and `just run-sweeps sgl qwq-32b`, you can get the results.

5. Aggregate the results
```bash
just show-results
```

Documentation: `just list`
```
Available recipes:
    clone-vllm-benchmarks target_dir="vllm-benchmarks" # Clone only the benchmarks directory from vllm repository
    download-model model="deepseek-r1"                 # Utility to download models from huggingface
    list                                               # Default recipe, list all recipes
    list-versions
    run-guidellm model="deepseek-r1" prompt_tokens="512" generated_tokens="128" # Run guidellm's qps sweep
    run-scenario backend="vllm" model="deepseek-r1" lengths="1000,1000" # Run a single benchmark scenario
    run-sweeps backend="vllm" model="deepseek-r1"      # Run benchmark sweeps for a specific backend and model
    serve backend="vllm" model="deepseek-r1"           # Unified serve command for both backends.
    show-results model="deepseek-r1"                   # Generate table and graph
    uvx-sgl +args                                      # Run reproducible sGLang installation with `just uvx-sgl python -m sglang.launch_server ...`
    uvx-vllm +args                                     # Run reproducible vLLM installation with `just uvx-vllm vllm serve ...`
Available Models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b
```