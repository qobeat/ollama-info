# VERIFY v1.7.1

## Verification performed

1. Bash syntax validation across packaged shell scripts.
2. Deterministic fake Ollama/NVIDIA shim test for direct benchmark output.
3. Deterministic fake Ollama/NVIDIA shim test for orchestrator output and monitor report.
4. Archive hygiene validation.

## Acceptance evidence

- `ollama-test-RTX3090.sh` emits `LoadState=model_switch_observed` and `ColdVerified=0` when another model is resident before the tested model.
- `ollama-test-RTX3090.sh` emits `Residency: WARN cpu_gpu_offload (15%/85% CPU/GPU); not a clean full-GPU-resident benchmark` when post-run `ollama ps` indicates mixed residency.
- `ollama-test-and-monitor-RTX3090.sh` uses `Visible : single-request ...` instead of `Visible : single GPU ...`.
- `ollama-test-and-monitor-RTX3090.sh` emits the same residency warning as direct test mode.
- `ollama-monitor.sh` writes an `Ollama residency/offload classification` section to the monitor report.

## Limitations

Verification used deterministic local shims, not live RTX 3090 reruns. It validates reporting logic, load-state semantics, package integrity, and archive hygiene. It does not claim new live hardware throughput.
