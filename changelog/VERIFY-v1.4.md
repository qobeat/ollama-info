# VERIFY v1.4

Validation performed in build container:

- `bash -n` for all package shell scripts.
- `bash -n bashrc/.bashrc`.
- `scripts/ollama-monitor.sh --self-test`.
- Confirmed `ollama-test-and-monitor-RTX3090.sh` defaults to `run_conc=0` and `concurrency=1`.
- Confirmed `--stress` maps to concurrency probe with concurrency at least 2.
- Confirmed no-argument output remains compact and does not dump full help.
- Confirmed `ollama-status --models` supports `OLLAMA_MODEL_COMMAND`.
- Confirmed package zip integrity with `unzip -t`.

Real RTX 3090 execution was not available in the build container.
