# ollama-info v0.6

WSL2 + Ollama + NVIDIA RTX 3090 health and performance toolkit.

This package is designed for a Windows 11 + WSL2 workstation running Ollama with an RTX 3090 24 GB GPU. It collects GPU telemetry, Ollama loaded-model state, raw API benchmark JSON, process snapshots, compact terminal summaries, and Markdown summaries that are easy to archive and compare.

## What changed in v0.6

- Added compact final ASCII terminal summaries (`terminal-summary.txt`) for monitor, test, and orchestrator runs.
- The orchestrator now streams test progress to the terminal instead of hiding it in `test.console.log`.
- Added explicit `--think false|true|none|low|medium|high`; default is `--think false` for Qwen3 and other thinking-capable models.
- Changed `orchestrator-summary.md` from a huge concatenation into a compact index + terminal summary + retention guidance.
- Kept raw JSON/CSV artifacts because they are evidence and reproducibility data; do not delete them when comparing runs.
- `ollama-monitor.sh` still creates one zip archive in `~/tmp` for every monitor run.
- `ollama-test-and-monitor-RTX3090.sh` creates one combined zip archive in `~/tmp` for the full run; nested monitor/test component zip creation is disabled during orchestration to avoid duplicate archives.

## Files

| File | Purpose |
|---|---|
| `ollama-monitor.sh` | GPU/Ollama monitor. Produces `gpu.csv`, `report.md`, `terminal-summary.txt`, snapshots, and `~/tmp/ollama-monitor-<run_id>.zip`. |
| `ollama-test-RTX3090.sh` | Runs sanity, throughput, sustained, long-context, optional concurrency, and optional CPU comparison tests. Prints START/DONE progress and compact ASCII summary. |
| `ollama-test-and-monitor-RTX3090.sh` | Starts the monitor, streams RTX3090 test progress, stops the monitor cleanly, prints compact ASCII summary, and creates a combined archive. |
| `ollama-start` | Starts Ollama server if it is not already reachable. |
| `ollama-status` | Shows server status, downloaded models, loaded models, disk usage, GPU status, and recent logs. |
| `ollama-stop` | Stops Ollama server and runner processes. |
| `ollama-gen` | Small self-contained `/api/generate` wrapper. |
| `ollama-perf`, `ollama-perf-table` | Existing benchmark scripts retained for compatibility. |
| `calc_perf_ollama.py`, `calc_perf_ollama_table.py` | CSV summary helpers. |
| `REVIEW-v0.6.md` | Review of the real v0.5 run and problems found. |
| `REFLECTION-v0.6.md` | Reflection pass against the requested requirements. |

## Dependencies

Required for the main RTX3090 workflow:

```bash
sudo apt update
sudo apt install -y curl jq zip procps coreutils gawk
```

Also required:

```bash
ollama --version
nvidia-smi
```

On WSL2, `nvidia-smi` is provided through the Windows NVIDIA driver.

## Install

From the extracted package directory:

```bash
mkdir -p ~/.local/bin
cp ollama-* calc_perf_ollama*.py ~/.local/bin/
chmod +x ~/.local/bin/ollama-* ~/.local/bin/calc_perf_ollama*.py
```

Confirm:

```bash
which ollama-monitor.sh
ollama-status
```

## Recommended workflow: test and monitor together

Use this as the primary RTX 3090 validation command:

```bash
ollama-test-and-monitor-RTX3090.sh \
  --model qwen3:8b \
  --interval 1 \
  --monitor-profile deep \
  --num-ctx 4096 \
  --long-ctx 8192 \
  --num-predict 512 \
  --long-num-predict 1024 \
  --concurrency 2 \
  --think false
```

Screen behavior in v0.6:

- Prints the run plan.
- Prints `START` and `DONE` for each test.
- Prints a compact final ASCII summary under 50 lines.
- Uses no color and no ESC control sequences.

Outputs:

```text
~/log/ollama-test-and-monitor-RTX3090/run-*/
~/tmp/ollama-test-and-monitor-RTX3090-*.zip
```

The combined run directory contains:

- `monitor.console.log`
- `test.console.log`
- `terminal-summary.txt` - compact ASCII result screen
- `orchestrator-summary.md` - compact index, not a full duplicate of nested reports
- nested monitor output with `gpu.csv`, `report.md`, and monitor `terminal-summary.txt`
- nested test output with raw Ollama JSON, payload JSON, `summary.csv`, `summary.md`, and test `terminal-summary.txt`

## Monitor only

```bash
ollama-monitor.sh --interval 1 --profile deep
```

Stop with `Ctrl+C`.

Outputs:

```text
~/log/ollama-monitor/run-*/gpu.csv
~/log/ollama-monitor/run-*/report.md
~/log/ollama-monitor/run-*/terminal-summary.txt
~/tmp/ollama-monitor-*.zip
```

Automatic archive creation is enabled by default. Disable it with:

```bash
ollama-monitor.sh --interval 1 --profile deep --no-zip
```

Run a short fixed-duration capture:

```bash
ollama-monitor.sh --interval 1 --duration 60 --profile deep
```

Run monitor self-test:

```bash
ollama-monitor.sh --self-test
```

## RTX 3090 test only

```bash
ollama-test-RTX3090.sh --model qwen3:8b --think false
```

Useful variants:

```bash
# Pull model if missing
ollama-test-RTX3090.sh --model qwen3:8b --pull

# Heavier sustained generation
ollama-test-RTX3090.sh --model qwen3:8b --num-predict 1024 --long-num-predict 2048

# Disable concurrency
ollama-test-RTX3090.sh --model qwen3:8b --no-conc

# Add CPU reference, can be slow
ollama-test-RTX3090.sh --model qwen3:8b --run-cpu

# Explicitly allow thinking for quality/reasoning comparison
ollama-test-RTX3090.sh --model qwen3:8b --think true
```

Outputs:

```text
~/log/ollama-test-RTX3090/run-*/terminal-summary.txt
~/log/ollama-test-RTX3090/run-*/summary.md
~/log/ollama-test-RTX3090/run-*/summary.csv
~/log/ollama-test-RTX3090/run-*/raw/*.json
~/tmp/ollama-test-RTX3090-*.zip
```

## Qwen3 thinking-mode note

Your previous qwen3:8b test returned many tokens in the `thinking` field and sometimes an empty `response`. That is not a GPU failure. It means the model consumed the generation budget on reasoning tokens before producing the final answer.

v0.6 sends Ollama's top-level `think:false` by default:

```bash
ollama-test-RTX3090.sh --model qwen3:8b --think false
```

If a future model or Ollama version ignores `think:false`, the raw JSON still captures `thinking`, and the terminal summary reports `thinking-only rows`.

## What the monitor flags mean

| Flag | Meaning |
|---|---|
| `temp_warning_samples_ge_83_c` | GPU temperature reached the warning threshold. |
| `temp_critical_samples_ge_88_c` | GPU temperature reached a critical threshold. |
| `vram_high_samples_ge_90_pct` | VRAM usage exceeded the configured percentage threshold. |
| `low_gpu_util_high_power_samples` | Power is high while GPU utilization is low; can indicate stalled workload or display/driver overhead. |
| `busy_low_graphics_clock_samples` | GPU is busy but graphics clock is lower than expected. Check power state, thermal limits, or WSL/driver behavior. |
| `pcie_link_warnings_while_busy` | Current PCIe width is lower than max while GPU is busy. Not usually critical for LLM inference after model load, but worth checking slot/BIOS/seating. |

## Interpreting the run you uploaded

Your v0.5 run was technically successful:

- qwen3:8b ran without API errors.
- Average GPU generation speed was about 46.93 tok/s across 6 GPU rows.
- Max GPU temperature was 49C.
- Max power was about 233W, below the 350W limit.
- Max VRAM was about 7953 MiB out of 24576 MiB.
- The first request had a cold model load of about 68.35s.
- PCIe was x8 current / x16 max while busy. This is worth checking physically/BIOS-wise, but it is not a blocker for this qwen3:8b inference run.

## Do we need both summaries and raw files?

Yes. Keep them for different purposes:

- `terminal-summary.txt`: compact screen result, safe for standard ASCII terminal.
- `summary.md` / `report.md`: human-readable explanation and interpretation.
- `summary.csv`: sortable benchmark rows and regression comparisons.
- `raw/*.json`: exact Ollama API evidence, including `response`, `thinking`, durations, token counts, and done reason.
- `payloads/*.json`: reproducibility; shows exactly what was sent to Ollama.
- `gpu.csv`: independent GPU telemetry source; needed to recalculate temperature, power, VRAM, clocks, PCIe, and utilization.

The v0.6 orchestrator summary intentionally no longer embeds the full nested monitor report and full nested test report; it points to them instead.

## Safety notes

- The scripts do not change NVIDIA driver settings.
- The scripts do not overclock, undervolt, flash BIOS, or modify Windows registry.
- CPU-only tests are off by default because they can be slow and can force model reloads.
- `--pull` is off by default so the scripts do not unexpectedly download large model files.
