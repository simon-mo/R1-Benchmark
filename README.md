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
Run the server via `just serve-vllm` or `just serve-sgl`.
Run the benchmark via `just run-sweeps` or `just run-sweeps sgl`.

* Note that for SGL, you need to download the model first because it cannot run with dummy format.
  Please modify the `Justfile` to point to the correct path.

5. Aggregate the results
```bash
just show-results
```

As of March 16, 2025, the results are as follows:
```
    Benchmark Comparison: vLLM vs SGL (Output Tokens/s)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━┳━━━━━━━┓
┃ Input Tokens ┃ Output Tokens ┃    vLLM ┃    SGL ┃ Gap % ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━╇━━━━━━━┩
│         1000 │          1000 │ 1292.41 │ 834.83 │ 54.8% │
│         5000 │          1000 │ 1041.09 │ 682.85 │ 52.5% │
│        10000 │          1000 │  747.04 │ 419.65 │ 78.0% │
│        32000 │          1000 │  104.88 │ 112.04 │ -6.4% │
└──────────────┴───────────────┴─────────┴────────┴───────┘
```