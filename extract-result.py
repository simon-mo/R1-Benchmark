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
    pattern = r'(vllm|sgl)-(\d+)-(\d+)\.json'
    match = re.search(pattern, filename)
    if not match:
        console.print(f"[yellow]Warning:[/yellow] Skipping file {filename} - doesn't match expected pattern")
        return None

    backend = match.group(1)
    input_tokens = int(match.group(2))
    output_tokens = int(match.group(3))

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

        if vllm_data is not None and sgl_data is not None:
            for metric in metrics:
                vllm_value = vllm_data[metric]
                sgl_value = sgl_data[metric]
                gap_percentage = ((vllm_value - sgl_value) / sgl_value) * 100

                scenario[f'vllm_{metric}'] = vllm_value
                scenario[f'sgl_{metric}'] = sgl_value
                scenario[f'gap_{metric}'] = gap_percentage

        scenarios.append(scenario)

    return pd.DataFrame(scenarios)

def display_rich_table(df, results_dir):
    if df.empty:
        console.print("[red]Error:[/red] No data to display")
        return

    # Create the table
    table = Table(title="Benchmark Comparison: vLLM vs SGL (Output Tokens/s)", caption=f"Model: {Path(results_dir).name}")

    # Add columns
    table.add_column("Input Tokens", justify="right", style="cyan")
    table.add_column("Output Tokens", justify="right", style="cyan")

    # Only show output tokens per second
    metric = 'output_toks/s'
    table.add_column("vLLM", justify="right", style="green")
    table.add_column("SGL", justify="right", style="blue")
    table.add_column("Diff %", justify="right", style="yellow")

    # Sort by input tokens, then output tokens
    df_sorted = df.sort_values(['input_tokens', 'output_tokens'])

    # Add rows
    for _, row in df_sorted.iterrows():
        values = [
            str(int(row['input_tokens'])),
            str(int(row['output_tokens'])),
            f"{row[f'vllm_{metric}']:.2f}",
            f"{row[f'sgl_{metric}']:.2f}",
            f"{row[f'gap_{metric}']:.1f}%"
        ]
        table.add_row(*values)

    # Print the table
    console.print(table)

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
