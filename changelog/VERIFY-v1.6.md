# VERIFY v1.6

## Static validation

- `bash -n scripts/ollama-common.sh`: PASS
- `bash -n scripts/ollama-test-RTX3090.sh`: PASS
- `bash -n scripts/ollama-test-and-monitor-RTX3090.sh`: PASS
- `bash -n scripts/ollama-embed-test-RTX3090.sh`: PASS
- `bash -n bashrc/.bashrc`: PASS

## Fake-Ollama validation

A fake `curl`, `ollama`, and `nvidia-smi` environment was used because the packaging sandbox has no real WSL2 RTX 3090/Ollama server.

### Generation preflight refusal for embedding-only model

Command shape:

```bash
PATH=fakebin:$PATH BASE_URL=http://fake ./scripts/ollama-test-RTX3090.sh bge-m3 --no-zip --terminal-summary
```

Expected and observed:

- model role detected as `embedding`.
- no four-test generation suite was run.
- one preflight row was recorded.
- `error_class=unsupported_generate_for_embedding_model` was written to summary/failure hints.
- terminal summary recommended `ollama embed-test bge-m3`.

### Embedding benchmark mode

Command shape:

```bash
PATH=fakebin:$PATH BASE_URL=http://fake ./scripts/ollama-test-RTX3090.sh bge-m3 --embedding --no-zip --terminal-summary
```

Expected and observed:

- three `/api/embed` rows were recorded.
- summary.csv included `endpoint=/api/embed`, `vector_count`, `vector_dim`, and `embedding_tps` fields.
- terminal summary printed `Embed`, `LongEmb`, and `Inference: PASS; completed embedding benchmark`.

### Wrapper/help checks

- `scripts/ollama-embed-test-RTX3090.sh --help`: PASS
- Direct and orchestrator syntax checks: PASS

## Not validated in sandbox

- Real Ollama 0.24.0 server execution.
- Real RTX 3090 telemetry under load.
- Real WSL2/systemd service control.

Those require the user workstation environment.
