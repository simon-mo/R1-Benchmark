This repo is used for vLLM's interative performance spot check.
For automated benchmark, please refer to vLLM's nightly set.

The goal for this repo is establish a set of commonly used benchmarks and worklaods for comparative analysis.

# Latest Numbers

As of April 16, 2025: H200, vLLM 0.8.4, SGL v0.4.5, TRT-LLM main
```
                         Benchmark Comparison for vLLM (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃    SGL ┃     TRT ┃ vLLM/SGL Diff % ┃ vLLM/TRT Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━┩
│         1000 │          2000 │ 1092.31 │ 922.29 │ 1014.95 │           18.4% │            7.6% │
│         5000 │          1000 │  791.24 │ 690.19 │  807.61 │           14.6% │           -2.0% │
│        10000 │           500 │  393.69 │ 290.93 │  431.46 │           35.3% │           -8.8% │
│        30000 │           100 │   29.45 │  20.63 │    0.00 │           42.8% │            0.0% │
│     sharegpt │      sharegpt │ 1374.43 │ 779.83 │  735.60 │           76.2% │           86.8% │
└──────────────┴───────────────┴─────────┴────────┴─────────┴─────────────────┴─────────────────┘
                                       Model: deepseek-r1
```

Flags:
* Benchmark: 50 queries for fixed length, 500 for sharegpt. 10 qps for a fast ramp up.
* vLLM: `--enable-expert-parallel`, `VLLM_USE_FLASHINFER_SAMPLER=1`.
* SGL: `--enable-torch-compile --torch-compile-max-bs 8 --expert-parallel-size 8`, `SGL_ENABLE_JIT_DEEPGEMM=1`. (DP and DeepEP are also attempted, see LOG.md)
* TRT-LLM: `--ep_size 8 --kv_cache_free_gpu_memory_fraction 0.8 --max_batch_size 50 --max_num_tokens 11000`.

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

