# VERIFY v1.0

Validation performed in the packaging environment.

## Static checks

```text
bash -n ollama-test-and-monitor-RTX3090.sh
bash -n ollama-test-RTX3090.sh
bash -n ollama-monitor.sh
bash -n ollama-download.sh
bash -n bashrc/.bashrc
```

Expected: all pass.

## CLI help checks

```text
./ollama-test-and-monitor-RTX3090.sh --help
./ollama-test-RTX3090.sh --help
```

Expected: help includes positional `MODEL_PATTERN`, short example, and no-argument model listing behavior.

## Fake Ollama selector checks

A local fake HTTP server was used to return `/api/tags` with:

```text
qwen3.6:35b
gemma3:1b
qwen2.5-coder:7b
```

Expected:

- `ollama-test-and-monitor-RTX3090.sh` with no arguments lists available models and exits before test startup.
- `ollama-test-and-monitor-RTX3090.sh` with no arguments lists available models and exits with rc=2.
- `ollama-test-and-monitor-RTX3090.sh missing-model` reports no local match, lists available models, and exits with rc=4.
- `ollama-test-and-monitor-RTX3090.sh qwen` reports an ambiguous pattern, lists matching models, and exits with rc=5.
- `ollama-test-RTX3090.sh qwen3.6 --no-conc --no-zip --no-terminal-summary --no-wsl-diagnostics --num-predict 1 --long-num-predict 1 --long-prompt-words 64 --timeout-sec 3` resolves to `qwen3.6:35b` and completes against the fake `/api/generate` endpoint.

## Package check

```text
zip -qr /mnt/data/ollama-info-v1.0.zip ollama-info
unzip -t /mnt/data/ollama-info-v1.0.zip
```

Expected: archive integrity passes.
