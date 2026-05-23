# ollama-info v0.5

WSL2 + Ollama + NVIDIA RTX 3090 health and performance toolkit.

This package is designed for a Windows 11 + WSL2 workstation running Ollama with an RTX 3090 24 GB GPU. It collects GPU telemetry, Ollama loaded-model state, raw API benchmark JSON, process snapshots, and Markdown summaries that are easy to archive and compare.

## What changed in v0.5

- Rebuilt `ollama-monitor.sh` as a more complete RTX/Ollama telemetry collector.
- Added automatic zip creation under `~/tmp` for monitor run directories.
- Added `ollama-test-RTX3090.sh` for practical local model health/performance tests.
- Added `ollama-test-and-monitor-RTX3090.sh` to run tests while monitoring in parallel.
- Made `ollama-gen` self-contained; it no longer depends on a missing external `lib/log.sh`.
- Made `ollama-start` call the package-local `ollama-status` instead of assuming `~/bin/ollama-status`.
- Updated `ollama-status` to show model disk usage, loaded models, GPU state, and recent Ollama logs.
- Added package review and reflection documents.

## Files

| File | Purpose |
|---|---|
| `ollama-monitor.sh` | GPU/Ollama monitor. Produces `gpu.csv`, `report.md`, snapshots, and `~/tmp/ollama-monitor-<run_id>.zip`. |
| `ollama-test-RTX3090.sh` | Runs sanity, throughput, sustained, long-context, optional concurrency, and optional CPU comparison tests. |
| `ollama-test-and-monitor-RTX3090.sh` | Starts the monitor, runs RTX3090 tests, stops the monitor cleanly, and creates a combined archive. |
| `ollama-start` | Starts Ollama server if it is not already reachable. |
| `ollama-status` | Shows server status, downloaded models, loaded models, disk usage, GPU status, and recent logs. |
| `ollama-stop` | Stops Ollama server and runner processes. |
| `ollama-gen` | Small self-contained `/api/generate` wrapper. |
| `ollama-perf`, `ollama-perf-table` | Existing benchmark scripts retained for compatibility. |
| `calc_perf_ollama.py`, `calc_perf_ollama_table.py` | CSV summary helpers. |
| `REVIEW-v0.5.md` | Deep review findings for the input package. |
| `REFLECTION-v0.5.md` | Reflection pass against the requested requirements. |

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

On WSL2, `nvidia-smi` is provided through the Windows NVIDIA driver. Your previous test showed driver `596.36`, CUDA `13.2`, RTX 3090, and Ollama `0.12.6`; this package does not hard-code those versions.

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
  --concurrency 2
```

Outputs:

```text
~/log/ollama-test-and-monitor-RTX3090/run-*/
~/tmp/ollama-test-and-monitor-RTX3090-*.zip
```

The combined run directory contains:

- `monitor.console.log`
- `test.console.log`
- `orchestrator-summary.md`
- nested monitor output with `gpu.csv` and `report.md`
- nested test output with raw Ollama JSON, payload JSON, `summary.csv`, and `summary.md`

## Monitor only

```bash
ollama-monitor.sh --interval 1 --profile deep
```

Stop with `Ctrl+C`.

Outputs:

```text
~/log/ollama-monitor/run-*/gpu.csv
~/log/ollama-monitor/run-*/report.md
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
ollama-test-RTX3090.sh --model qwen3:8b
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
```

Outputs:

```text
~/log/ollama-test-RTX3090/run-*/summary.md
~/log/ollama-test-RTX3090/run-*/summary.csv
~/log/ollama-test-RTX3090/run-*/raw/*.json
~/tmp/ollama-test-RTX3090-*.zip
```

## Qwen3 thinking-mode note

Your previous qwen3:8b test returned an empty `response` and populated the `thinking` field until `done_reason=length`. That is not a GPU failure. It means the model consumed the generation budget on thinking tokens before producing the final answer.

The RTX3090 test script prefixes prompts with `/no_think` by default:

```bash
PROMPT_PREFIX=/no_think ollama-test-RTX3090.sh --model qwen3:8b
```

If your model ignores that prefix, increase generation length:

```bash
ollama-test-RTX3090.sh --model qwen3:8b --num-predict 1024 --long-num-predict 2048
```

## What the monitor flags mean

| Flag | Meaning |
|---|---|
| `temp_warning_samples_ge_83_c` | GPU temperature reached the warning threshold. |
| `temp_critical_samples_ge_88_c` | GPU temperature reached a critical threshold. |
| `vram_high_samples_ge_90_pct` | VRAM usage exceeded the configured percentage threshold. |
| `low_gpu_util_high_power_samples` | Power is high while GPU utilization is low; can indicate stalled workload or display/driver overhead. |
| `busy_low_graphics_clock_samples` | GPU is busy but graphics clock is lower than expected. Check power state, thermal limits, or WSL/driver behavior. |
| `pcie_link_warnings_while_busy` | Current PCIe width is lower than max while GPU is busy. Not usually critical for LLM inference after model load, but worth checking slot/BIOS/seating. |

## Interpreting your earlier qwen3:8b result

Based on the test artifacts in this chat, qwen3:8b was loaded as `100% GPU`, used about `6.0 GB`, context was `4096`, RTX 3090 VRAM was about `7390 MiB`, and generation speed was about `51 tok/s`. v0.5 is designed to capture that evidence automatically instead of requiring manual interpretation.

## Safety notes

- The scripts do not change NVIDIA driver settings.
- The scripts do not overclock, undervolt, flash BIOS, or modify Windows registry.
- CPU-only tests are off by default because they can be slow and can force model reloads.
- `--pull` is off by default so the scripts do not unexpectedly download large model files.
