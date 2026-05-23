#!/usr/bin/env python3
import sys, csv, json, statistics, os

def safe_median(values):
    return round(statistics.median(values), 3) if values else None

def safe_mean(values):
    return round(statistics.mean(values), 3) if values else None

def main():
    data = {"gpu": [], "cpu": [], "conc": []}
    meta = {"file": None, "model": None, "timestamp": None}

    infile = sys.argv[1] if len(sys.argv) > 1 else None
    if infile:
        meta["file"] = os.path.basename(infile)
        with open(infile, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                test = row.get("test", "")
                tps = row.get("gen_tps")
                if not tps: continue
                try: val = float(tps)
                except: continue
                if test.startswith("fixed_gpu_"): data["gpu"].append(val)
                elif test.startswith("fixed_cpu_"): data["cpu"].append(val)
                elif test.startswith("conc_"): data["conc"].append(val)
                if not meta["model"] and "model" in row:
                    meta["model"] = row["model"]
                if not meta["timestamp"] and "timestamp" in row:
                    meta["timestamp"] = row["timestamp"]
    else:
        sys.exit("Usage: calc_perf_ollama.py <csv_file>")

    result = {
        "meta": meta,
        "gpu_med": safe_median(data["gpu"]),
        "gpu_mean": safe_mean(data["gpu"]),
        "cpu_med": safe_median(data["cpu"]),
        "cpu_mean": safe_mean(data["cpu"]),
        "conc_med": safe_median(data["conc"]),
        "conc_mean": safe_mean(data["conc"]),
        "speedup_med": None,
        "speedup_mean": None,
        "samples": {k: len(v) for k, v in data.items()}
    }

    if result["cpu_med"] and result["gpu_med"]:
        result["speedup_med"] = round(result["gpu_med"]/result["cpu_med"], 2)
    if result["cpu_mean"] and result["gpu_mean"]:
        result["speedup_mean"] = round(result["gpu_mean"]/result["cpu_mean"], 2)

    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
