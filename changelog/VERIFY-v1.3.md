# VERIFY v1.3

Validation performed:

- `bash -n` on all shell scripts in `scripts/` and on `bashrc/.bashrc`.
- `scripts/ollama-monitor.sh --self-test`.
- Fake successful Ollama `/api/generate`: no false `api_error`, `primary_error_class=none`.
- Fake HTTP 500 Ollama `/api/generate`: error classification still works.
- Fake `nvidia-smi`: orchestrator created start/end hardware snapshot files.
- Timestamp check: operational console output begins with ISO timestamps.
- `ollama status` Bash wrapper delegates to `scripts/ollama-status` and normal `ollama list` pass-through is preserved.
- Zip integrity check with `unzip -t`.

Not performed: real RTX 3090 benchmark in this container.
