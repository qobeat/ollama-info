#!/usr/bin/env python3
import sys
import csv
import statistics

def main():
    # --- 1. Data Collection ---
    stats = {}
    metadata = {"model": "unknown"}

    # Handle input (File vs Stdin)
    input_file = sys.stdin
    if len(sys.argv) > 1:
        try:
            input_file = open(sys.argv[1], 'r', newline='')
        except FileNotFoundError:
            print(f"Error: File {sys.argv[1]} not found.")
            sys.exit(1)

    reader = csv.reader(input_file)
    
    try:
        headers = next(reader)
        
        # Robust column mapping
        try:
            h_map = {name: i for i, name in enumerate(headers)}
            col_test = h_map["test"]
            col_mode = h_map["mode"]
            col_conc = h_map["concurrency"]
            col_gen = h_map["gen_tps"]
            # Prompt TPS is optional (older CSVs might lack it)
            col_prmt = h_map.get("prompt_tps", -1) 
            col_model = h_map.get("model", -1)
        except KeyError as e:
            # If critical columns are missing, we can't function
            print(f"Error: CSV missing critical column {e}")
            sys.exit(1)

        for row in reader:
            if len(row) <= col_gen: continue
            
            try:
                # Extract values
                test_name = row[col_test]
                mode = row[col_mode]
                conc = int(row[col_conc]) if row[col_conc] else 1
                val_gen = float(row[col_gen])
                val_prmt = float(row[col_prmt]) if (col_prmt != -1 and row[col_prmt]) else 0.0

                if metadata["model"] == "unknown" and col_model != -1:
                    metadata["model"] = row[col_model]

                # Categorize
                if mode == "CPU":
                    key = "fixed_cpu"
                elif mode == "GPU":
                    key = "fixed_gpu" if conc == 1 else f"conc_{conc}"
                else:
                    continue

                if key not in stats:
                    stats[key] = {"gen": [], "prmt": []}
                
                stats[key]["gen"].append(val_gen)
                stats[key]["prmt"].append(val_prmt)

            except ValueError:
                continue 

    except StopIteration:
        pass
    finally:
        if input_file is not sys.stdin:
            input_file.close()

    # --- 2. Calculation & Formatting ---

    def get_med(key, metric):
        if key not in stats or not stats[key][metric]:
            return 0.0
        return statistics.median(stats[key][metric])

    # Save raw baselines for accurate speedup calculation
    raw_cpu_gen = get_med("fixed_cpu", "gen")
    raw_gpu_gen = get_med("fixed_gpu", "gen")

    # Layout Configuration
    # We define columns: Header Name, Width, Alignment (<, ^, >)
    cols = [
        ("TEST TYPE",  14, "<"),
        ("CONC",        6, "^"),
        ("GEN TPS",    10, ">"),
        ("PROMPT TPS", 12, ">"),
        ("TOTAL TPS",  12, ">")
    ]

    # Build Header Strings
    # e.g., "{:<14} | {:^6} | ..."
    fmt_str = " | ".join([f"{{:{c[2]}{c[1]}}}" for c in cols])
    
    # Separator line (matches widths)
    # e.g., "--------------+--------+..."
    sep_parts = ["-" * c[1] for c in cols]
    sep_line = "-+-".join(sep_parts)
    
    total_width = len(sep_line)

    # --- 3. Output ---

    print(f"\n{'='*total_width}")
    print(f" BENCHMARK REPORT: {metadata['model']}")
    print(f"{'='*total_width}")
    print(fmt_str.format(*[c[0] for c in cols]))
    print(sep_line)

    def print_row(label, conc_display, gen_med, prmt_med, tot_med):
        # Format numbers: if < 1.0 use 3 decimals, else 2
        # This fixes the "0.01" rounding visibility issue
        def fmt_num(n):
            return f"{n:.3f}" if n < 1.0 else f"{n:.2f}"

        print(fmt_str.format(
            label,
            conc_display,
            fmt_num(gen_med),
            fmt_num(prmt_med),
            fmt_num(tot_med)
        ))

    # Row 1: CPU
    if "fixed_cpu" in stats:
        print_row("CPU Baseline", "1", raw_cpu_gen, get_med("fixed_cpu", "prmt"), raw_cpu_gen)

    # Row 2: GPU Single
    if "fixed_gpu" in stats:
        print_row("GPU Single", "1", raw_gpu_gen, get_med("fixed_gpu", "prmt"), raw_gpu_gen)

    # Row 3+: Concurrency
    conc_keys = sorted([k for k in stats if k.startswith("conc_")], 
                       key=lambda x: int(x.split('_')[1]))
    
    for key in conc_keys:
        c_val = int(key.split('_')[1])
        g_med = get_med(key, "gen")
        p_med = get_med(key, "prmt")
        print_row(f"Concurrent x{c_val}", str(c_val), g_med, p_med, g_med * c_val)

    print(f"{'='*total_width}")

    # Speedup Calculation (Using RAW values)
    if raw_cpu_gen > 0 and raw_gpu_gen > 0:
        speedup = raw_gpu_gen / raw_cpu_gen
        print(f"GPU SPEEDUP: {speedup:.2f}x faster than CPU")
        
    print(f"{'='*total_width}\n")

if __name__ == "__main__":
    main()