import json
import glob
import re
import sys
from pathlib import Path
import pandas as pd
from rich.console import Console
from rich.table import Table
import numpy as np

console = Console()

def extract_info_from_filename(filename):
    # Extract backend and tokens from filename pattern
    pattern = r'(vllm|sgl|trt)-(?:(\d+)-(\d+)|sharegpt)(?:-(.*))?\.json'
    match = re.search(pattern, filename)
    if not match:
        console.print(f"[yellow]Warning:[/yellow] Skipping file {filename} - doesn't match expected pattern")
        return None

    backend = match.group(1)
    tag = match.group(4)
    if tag is not None and tag != "default":
        backend = f"{backend}-{tag}"

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

        vllm_data = group[group['backend'] == 'vllm'].iloc[0] if len(group[group['backend'] == 'vllm']) > 0 else None
        for backend in group['backend'].unique():
            backend_data = group[group['backend'] == backend].iloc[0] if len(group[group['backend'] == backend]) > 0 else None

            for metric in metrics:
                vllm_value = vllm_data[metric] if vllm_data is not None else 0
                backend_value = backend_data[metric] if backend_data is not None else 0
                scenario[f'{backend}_{metric}'] = backend_value

                if backend != 'vllm': # calculate gap percentages only if backend is not vllm
                    gap_vllm_to_backend = ((vllm_value - backend_value) / backend_value * 100) if backend_value != 0 else 0
                    scenario[f'gap_vllm_to_{backend}_{metric}'] = gap_vllm_to_backend

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

    # Dynamically determine columns and their order
    column_display_map = {
        'input_tokens': "Input Tokens",
        'output_tokens': "Output Tokens",
    }
    df_columns_ordered = ['input_tokens', 'output_tokens']

    vllm_col = 'vllm_output_toks/s'
    vllm_display_name = "vLLM"
    column_display_map[vllm_col] = vllm_display_name
    df_columns_ordered.append(vllm_col)
    table.add_column(vllm_display_name, justify="right", style="magenta")

    backends = sorted([col.split('_output_toks/s')[0] for col in df.columns if '_output_toks/s' in col and col != vllm_col and 'gap' not in col])

    for backend in backends:
        backend_col = f"{backend}_output_toks/s"
        gap_col = f"gap_vllm_to_{backend}_output_toks/s"
        display_backend_name = backend.upper().replace('-', '_') # Ensure valid display name
        display_gap_name = f"vLLM/{display_backend_name} Gap %"

        if backend_col in df.columns:
            column_display_map[backend_col] = display_backend_name
            df_columns_ordered.append(backend_col)
            table.add_column(display_backend_name, justify="right", style="green")

        if gap_col in df.columns:
            column_display_map[gap_col] = display_gap_name
            df_columns_ordered.append(gap_col)
            table.add_column(display_gap_name, justify="right", style="yellow")


    # Add rows with formatting
    for _, row in df.iterrows():
        row_values = []
        for df_col in df_columns_ordered:
            value = row[df_col]
            display_name = column_display_map[df_col]

            if isinstance(value, (int, float)):
                if np.isnan(value):
                    row_values.append("")
                elif "Gap %" in display_name:
                    style = "[green]" if value > 0 else "[red]" if value < 0 else ""
                    row_values.append(f"{style}{value:+.2f}%[/]")
                elif display_name in ["Input Tokens", "Output Tokens"]:
                     row_values.append(f"{int(value)}") # Display tokens as integers
                else: # Throughput columns
                    row_values.append(f"{value:.2f}")
            else: # Handle 'sharegpt' or other non-numeric values
                row_values.append(str(value))

        table.add_row(*row_values)

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
        print(comparison_df)
        display_rich_table(comparison_df, results_dir)


if __name__ == "__main__":
    main()
