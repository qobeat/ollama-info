# Deep Review of Input Package v0.4

## Goal

Review the attached `ollama-info-v0.4.zip` package and update it into a practical WSL2 + Ollama + RTX 3090 monitoring/testing toolkit.

## Findings

| Area | Finding | Impact | Fix in v0.5 |
|---|---|---|---|
| `ollama-monitor.sh` | Captured basic GPU metrics only and did not create a zip archive. | Good for quick checks, weak for repeatable evidence collection. | Rebuilt monitor to collect richer NVIDIA, Ollama, process, compute-app, and API snapshots; creates `~/tmp/ollama-monitor-*.zip`. |
| `ollama-monitor.sh` | Output path used flat files under `~/log/ollama-monitor`. | Harder to archive one complete run. | Uses `run-<id>/` directories with all artifacts grouped. |
| `ollama-monitor.sh` | Report did not compute PCIe busy warnings, VRAM percentage warnings, energy estimate, or clock-state flags. | Missed useful RTX 3090 diagnostic signals. | Added diagnostic flags and richer metric tables. |
| `ollama-monitor.sh` | Previous report showed `duration_sec=0` in metadata. | Metadata was misleading. | Report now records elapsed wall seconds and approximate sample duration. |
| Missing test script | No dedicated RTX 3090 model-health/performance runner. | User had to manually run curl commands and interpret JSON. | Added `ollama-test-RTX3090.sh`. |
| Missing orchestration | No script to run monitoring and tests together safely. | Easy to miss the real workload window. | Added `ollama-test-and-monitor-RTX3090.sh`. |
| `ollama-gen` | Sourced external `lib/log.sh` not included in the zip. | Broken if installed as this package alone. | Rewritten as a self-contained wrapper. |
| `ollama-start` | Called `$HOME/bin/ollama-status`, which may not exist. | Broken when installed in `~/.local/bin` or run from package dir. | Resolves package-local `ollama-status`. |
| `ollama-status` | Useful but shallow. | Did not fully expose model disk usage, GPU link/clock state, and recent log signals. | Expanded status output. |
| `ollama-perf-table` | Could depend on helper script being in PATH. | Less portable. | Patched to use package-local helper. |

## Design decisions

1. Keep scripts plain Bash with `curl`, `jq`, `nvidia-smi`, `ps`, and standard Unix tools.
2. Do not modify NVIDIA driver settings or hardware configuration.
3. Do not auto-download large models unless `--pull` is explicitly used.
4. Prefer raw artifacts plus Markdown summaries over only console output.
5. Keep CPU-only tests optional because they are slow and can disturb GPU keep-alive measurements.

## Known limitations

- `nvidia-smi` reports some fields as `N/A` under WSL2; the report handles that without failing.
- WSL2 may show compute process names/memory as `N/A`; snapshots are still useful for PID correlation.
- Qwen3 may populate `thinking` before `response`; tests record both fields and warn through summary interpretation.
