# ollama-info v1.3

RTX 3090 / WSL2 / Ollama diagnostic package.

## Layout

```text
ollama-info/
  scripts/                executable scripts
  bashrc/                 optional .bashrc integration
  changelog/              changelog, review, verify, reflection notes
  README.md
  PACKAGE-MANIFEST.txt
```

## Primary commands

After installing the packaged `.bashrc`, `~/dev/ollama-info/scripts` is put on `PATH`:

```bash
ollama status
ollama models
ollama test qwen3.6 --no-conc --concurrency 1
ollama-test-and-monitor-RTX3090.sh qwen3.6
```

Without updating `PATH`, run scripts explicitly:

```bash
./scripts/ollama-status
./scripts/ollama-test-and-monitor-RTX3090.sh qwen3.6 --no-conc --concurrency 1
```

## v1.3 changes

- All executable package scripts moved to `scripts/`.
- Changelog/review/verify/reflection files moved to `changelog/`.
- Operational log lines now start with ISO timestamps.
- Fixed false-positive `api_error` where successful Ollama JSON responses were incorrectly reported as API failures.
- `ollama-test-and-monitor-RTX3090.sh` now captures orchestrator-level `nvidia-smi` start/end snapshots under each run's `hardware/` directory.
- `.bashrc` now prepends `~/dev/ollama-info/scripts` and keeps one `ollama()` compatibility wrapper.

## nvidia-smi boundary snapshots

It makes sense to capture `nvidia-smi` at the beginning and end of a test. Continuous CSV telemetry remains the main performance signal, while boundary snapshots give a readable record of driver, clocks, PCIe link, power, memory, and active compute processes.

Files written by the orchestrator:

```text
hardware/nvidia-smi-start.txt
hardware/nvidia-smi-end.txt
hardware/nvidia-smi-q-start.txt
hardware/nvidia-smi-q-end.txt
hardware/nvidia-smi-query-start.csv
hardware/nvidia-smi-query-end.csv
hardware/nvidia-compute-apps-start.csv
hardware/nvidia-compute-apps-end.csv
```

## Bash integration

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
```

Server-side Ollama variables belong in the systemd service override, not in `.bashrc`.
