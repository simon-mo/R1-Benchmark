This repo is used for vLLM's interative performance spot check.
For automated benchmark, please refer to vLLM's nightly set.

The goal for this repo is establish a set of commonly used benchmarks and worklaods for comparative analysis.

# Latest Numbers

As of April 18, 2025: H200, vLLM 0.8.4, SGL v0.4.5.post1, TRT-LLM main. Data in `saved-results/vllm-0.8.4/deepseek-r1/`.

Nebius H200 (CPU Xeon 8468)
```
                          Benchmark Comparison for vLLM (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃     SGL ┃ vLLM/SGL Gap % ┃ VLLM_EP ┃ vLLM/VLLM_EP Gap % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━┩
│         1000 │          2000 │ 1500.11 │ 1437.85 │         +4.33% │ 1372.98 │             +9.26% │
│         5000 │          1000 │ 1049.73 │  980.88 │         +7.02% │  830.49 │            +26.40% │
│        10000 │           500 │  497.91 │  439.94 │        +13.18% │  356.38 │            +39.71% │
│        30000 │           100 │   30.62 │   34.54 │        -11.35% │   26.83 │            +14.10% │
│     sharegpt │      sharegpt │ 1512.76 │  999.28 │        +51.38% │ 1487.22 │             +1.72% │
└──────────────┴───────────────┴─────────┴─────────┴────────────────┴─────────┴────────────────────┘
                                         Model: deepseek-r1
```

DGX H200 (CPU Xeon 8480C)
```
                                  Benchmark Comparison for vLLM (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━┓
┃              ┃       Output ┃         ┃        ┃ vLLM/SGL Gap ┃         ┃  vLLM/TRT Gap ┃         ┃ vLLM/VLLM_EP ┃
┃ Input Tokens ┃       Tokens ┃    vLLM ┃    SGL ┃            % ┃     TRT ┃             % ┃ VLLM_EP ┃        Gap % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━┩
│         1000 │         2000 │ 1145.36 │ 960.76 │      +19.21% │ 1602.40 │       -28.52% │ 1086.94 │       +5.37% │
│         5000 │         1000 │  853.46 │ 799.91 │       +6.69% │ 1039.03 │       -17.86% │  793.69 │       +7.53% │
│        10000 │          500 │  446.90 │ 383.09 │      +16.66% │  424.69 │        +5.23% │  395.92 │      +12.88% │
│        30000 │          100 │   37.31 │  34.22 │       +9.03% │   32.47 │       +14.89% │   29.44 │      +26.74% │
│     sharegpt │     sharegpt │ 1380.59 │ 996.01 │      +38.61% │ 1565.39 │       -11.81% │ 1375.64 │       +0.36% │
└──────────────┴──────────────┴─────────┴────────┴──────────────┴─────────┴───────────────┴─────────┴──────────────┘
                                                 Model: deepseek-r1
```

Flags:
* Benchmark: 50 queries for fixed length, 500 for sharegpt. 10 qps for a fast ramp up.
* vLLM: `VLLM_USE_FLASHINFER_SAMPLER=1`.
  * vLLM\_EP: `--enable-expert-parallel`
* SGL: `--enable-dp-attention --dp-size 8`, `SGL_ENABLE_JIT_DEEPGEMM=1`. (DP and DeepEP are also attempted, see LOG.md)
  * Important: SGLang needs to warm up the DEEPGEMM JIT kernels. So the very first run will be slow.
    You need to run the full sweep once, discard the result, and run the sweep again to get the final result.
* TRT-LLM: complicated. See `trt.md`. TL;DR: overlap scheduler, ep8, tp8.

# Usage
* All the commands are defined in `Justfile`.
* The environment should be exactly reproducible by using `uv`.

1. Install uv and just
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
```

2. Create the environment for vLLM and SGL, this command will download and cache the dependencies.
```bash
just list-versions
```

3. Clone vLLM benchmark scripts
```bash
just clone-vllm-benchmarks
```

4. Run the benchmark

You will need two terminal windows for this step.
* To run the server: `just serve vllm` or `just serve sgl`.
* To run the benchmark: `just run-sweeps vllm` or `just run-sweeps sgl`. The results will be saved in `results/{{model_name}}` directory.

For both command you can append model name to run the benchmark for a specific model. The current default is `deepseek-r1`. To see the supported models, run `just list`.
```
Available Models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b
```
For example, `just serve vllm llama-8b` and `just run-sweeps vllm llama-8b` will produce output for the model.
The exact model path can be found in `Justfile`.
The benchmark scenarios can also be found in `Justfile`.

5. Aggregate the results
```bash
just show-results
```

# Documentation
```
$ just list
Available recipes:
    list                                               # Default recipe, list all recipes

    [benchmark]
    run-scenario backend="vllm" model="deepseek-r1" lengths="1000,1000" # Run a single benchmark scenario
    run-sweeps backend="vllm" model="deepseek-r1"      # Run benchmark sweeps for a specific backend and model
    show-results model="deepseek-r1"                   # Generate table and graph

    [serve]
    serve backend="vllm" model="deepseek-r1"           # Unified serve command for both backends.
    uvx-sgl +args                                      # Run reproducible SGLang installation with `just uvx-sgl python -m sglang.launch_server ...`
    uvx-vllm +args                                     # Run reproducible vLLM installation with `just uvx-vllm vllm serve ...`

    [utility]
    clone-vllm-benchmarks target_dir="vllm-benchmarks" # Clone only the benchmarks directory from vllm repository
    download-dataset dataset="sharegpt"                # Utility to download datasets
    download-model model="deepseek-r1"                 # Utility to download models from huggingface
    list-versions                                      # List versions of vLLM and SGLang
    run-guidellm model="deepseek-r1" prompt_tokens="512" generated_tokens="128" # Run guidellm's qps sweep
Available Models: deepseek-r1, qwq-32b, llama-8b, llama-3b, qwen-1.5b
```

# Contributing
* Please submit a PR to add new models or benchmarks workloads! If you run into anything worth noting, please also feel free to modify `LOG.md` so we can keep track of the changes.
* For results that are worth keeping, please copy the output to `saved-results/{vllm-version}/{model_name}/{hardware_name}/{date}` directory.

