import json
import glob
import re
import sys
from pathlib import Path
import pandas as pd
from rich.console import Console
from rich.table import Table

console = Console()

def extract_info_from_filename(filename):
    # Extract backend and tokens from filename pattern
    pattern = r'(vllm|sgl|trt)-(?:(\d+)-(\d+)|sharegpt)\.json'
    match = re.search(pattern, filename)
    if not match:
        console.print(f"[yellow]Warning:[/yellow] Skipping file {filename} - doesn't match expected pattern")
        return None

    backend = match.group(1)
    if match.group(2) and match.group(3):
        input_tokens = int(match.group(2))
        output_tokens = int(match.group(3))
    else:
        # For sharegpt files, set both to 'sharegpt'
        input_tokens = 'sharegpt'
        output_tokens = 'sharegpt'

    return {
        'backend': backend,
        'input_tokens': input_tokens,
        'output_tokens': output_tokens
    }

def load_results(results_dir):
    data = []
    files = glob.glob(f"{results_dir}/*.json")

    if not files:
        console.print(f"[red]Error:[/red] No JSON files found in {results_dir}")
        return pd.DataFrame()

    console.print(f"Found {len(files)} JSON files")

    # Process all JSON files in the directory
    for file in files:
        filename = Path(file).name
        console.print(f"Processing {filename}")

        file_info = extract_info_from_filename(filename)
        if not file_info:
            continue

        try:
            with open(file, 'r') as f:
                result = json.load(f)

            data.append({
                'backend': file_info['backend'],
                'input_tokens': file_info['input_tokens'],
                'output_tokens': file_info['output_tokens'],
                'output_toks/s': result['output_throughput']
            })
        except (json.JSONDecodeError, KeyError) as e:
            console.print(f"[red]Error processing {filename}:[/red] {str(e)}")
            continue

    df = pd.DataFrame(data)
    if df.empty:
        console.print("[red]Error:[/red] No valid data found in JSON files")
    else:
        console.print(f"Successfully loaded data with columns: {list(df.columns)}")
        console.print("\nData Preview:")
        console.print(df)
        console.print()

    return df

def calculate_comparison(df):
    if df.empty:
        console.print("[red]Error:[/red] No data to compare")
        return pd.DataFrame()

    # Only focus on output tokens per second
    metrics = ['output_toks/s']
    scenarios = []

    for (input_tokens, output_tokens), group in df.groupby(['input_tokens', 'output_tokens']):
        scenario = {
            'input_tokens': input_tokens,
            'output_tokens': output_tokens
        }

        # Get values for each backend
        vllm_data = group[group['backend'] == 'vllm'].iloc[0] if len(group[group['backend'] == 'vllm']) > 0 else None
        sgl_data = group[group['backend'] == 'sgl'].iloc[0] if len(group[group['backend'] == 'sgl']) > 0 else None
        trt_data = group[group['backend'] == 'trt'].iloc[0] if len(group[group['backend'] == 'trt']) > 0 else None

        for metric in metrics:
            vllm_value = vllm_data[metric] if vllm_data is not None else 0
            sgl_value = sgl_data[metric] if sgl_data is not None else 0
            trt_value = trt_data[metric] if trt_data is not None else 0

            # Calculate gap percentages only if both values are non-zero
            gap_vllm_sgl = ((vllm_value - sgl_value) / sgl_value * 100) if sgl_value != 0 else 0
            gap_vllm_trt = ((vllm_value - trt_value) / trt_value * 100) if trt_value != 0 else 0

            scenario[f'vllm_{metric}'] = vllm_value
            scenario[f'sgl_{metric}'] = sgl_value
            scenario[f'trt_{metric}'] = trt_value
            scenario[f'gap_vllm_sgl_{metric}'] = gap_vllm_sgl
            scenario[f'gap_vllm_trt_{metric}'] = gap_vllm_trt

        scenarios.append(scenario)

    return pd.DataFrame(scenarios)

def display_rich_table(df, results_dir):
    if df.empty:
        console.print("[red]Error:[/red] No data to display")
        return

    # Create the table
    table = Table(title="Benchmark Comparison for vLLM (Output Tokens/s)", caption=f"Model: {Path(results_dir).name}")

    # Add columns
    table.add_column("Input Tokens", justify="right", style="cyan")
    table.add_column("Output Tokens", justify="right", style="cyan")

    # Only show output tokens per second
    metric = 'output_toks/s'
    table.add_column("vLLM", justify="right", style="green")
    table.add_column("SGL", justify="right", style="blue")
    table.add_column("TRT", justify="right", style="red")
    table.add_column("vLLM/SGL Diff %", justify="right", style="yellow")
    table.add_column("vLLM/TRT Diff %", justify="right", style="yellow")
    # Sort by input tokens, then output tokens
    df_sorted = df.sort_values(['input_tokens', 'output_tokens'])

    # Add rows
    for _, row in df_sorted.iterrows():
        values = [
            str(row['input_tokens']),
            str(row['output_tokens']),
            f"{row[f'vllm_{metric}']:.2f}",
            f"{row[f'sgl_{metric}']:.2f}",
            f"{row[f'trt_{metric}']:.2f}",
            f"{row[f'gap_vllm_sgl_{metric}']:.1f}%",
            f"{row[f'gap_vllm_trt_{metric}']:.1f}%"
        ]
        table.add_row(*values)

    # Print the table
    console.print(table)

    # Print CSV for Easy Plotting
    from io import StringIO

    output = StringIO()
    df.to_csv(output, index=False)
    console.print("----- CSV for Easy Plotting -----")
    console.print(output.getvalue())

def main():
    # Load and process results
    results_dir = sys.argv[1]
    console.print(f"\nLoading results from {Path(results_dir).absolute()}")

    df = load_results(results_dir)
    if not df.empty:
        comparison_df = calculate_comparison(df)
        display_rich_table(comparison_df, results_dir)


if __name__ == "__main__":
    main()
