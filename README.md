This repo is used for vLLM's interative performance spot check.
For automated benchmark, please refer to vLLM's nightly set.

* All the commands are defined in `Justfile`.
* The environment should be exactly reproducible by using `uv`.

## Usage

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
Run the server via `just serve-vllm` or `just serve-sgl`. Run the benchmark via `just run-sweeps` or `just run-sweeps sgl`.

* Note that for SGL, you need to download the model first because it cannot run with dummy format.
  Please modify the `Justfile` to point to the correct path.

* For TP4 (Qwen/QwQ-32B), you need to use `just serve-vllm-qwq-32b` and `just serve-sgl-qwq-32b`. With `just run-sweeps vllm 'Qwen/QwQ-32B'` and `just run-sweeps sgl 'Qwen/QwQ-32B'`, you can get the results.

* For TP1 (Llama-3.1-8B), you need to use `just serve-vllm-llama-8b` and `just serve-sgl-llama-8b`. With `just run-sweeps vllm 'deepseek-ai/DeepSeek-R1-Distill-Llama-8B'` and `just run-sweeps sgl 'deepseek-ai/DeepSeek-R1-Distill-Llama-8B'`, you can get the results.

5. Aggregate the results
```bash
just show-results
```

As of March 21, 2025: H200
```

    Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃   vLLM ┃    SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 938.18 │ 887.88 │   5.7% │
│         5000 │          1000 │ 724.35 │ 640.24 │  13.1% │
│        10000 │           500 │ 387.74 │ 273.90 │  41.6% │
│        32000 │           100 │  30.30 │  18.20 │  66.5% │
└──────────────┴───────────────┴────────┴────────┴────────┘
                    Model: deepseek-r1

     Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃     SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 2865.57 │ 3630.32 │ -21.1% │
│         5000 │          1000 │ 1455.46 │ 1603.86 │  -9.3% │
│        10000 │           500 │  734.53 │  724.40 │   1.4% │
│        32000 │           100 │   67.51 │   55.86 │  20.8% │
└──────────────┴───────────────┴─────────┴─────────┴────────┘
                       Model: llama-8b

     Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃     SGL ┃ Diff % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━┩
│         1000 │          2000 │ 1597.60 │ 2701.13 │ -40.9% │
│         5000 │          1000 │  950.13 │  978.87 │  -2.9% │
│        10000 │           500 │  423.11 │  494.34 │ -14.4% │
│        32000 │           100 │   31.85 │   31.49 │   1.1% │
└──────────────┴───────────────┴─────────┴─────────┴────────┘
                       Model: qwq-32b
```