# VERIFY-v0.9

Validation for `ollama-info` v0.9 focused on the RTX 3090/Ollama load-failure path, monitor inference-coverage reporting, and package consistency.

## Static syntax validation

Command:

```bash
for f in \
  ollama-test-RTX3090.sh \
  ollama-monitor.sh \
  ollama-test-and-monitor-RTX3090.sh \
  ollama-download.sh \
  ollama-gen \
  ollama-perf \
  ollama-perf-table \
  ollama-start \
  ollama-status \
  ollama-stop; do
  bash -n "$f"
done
```

Result: PASS.

## Help/version validation

Commands:

```bash
./ollama-test-RTX3090.sh --help
./ollama-monitor.sh --help
./ollama-test-and-monitor-RTX3090.sh --help
```

Checks:

- Each primary RTX script reports `v0.9.0`.
- Test and orchestrator help expose `--server-log-lines`.
- Test help exposes `--wsl-diagnostics` / `--no-wsl-diagnostics`.

Result: PASS.

## Monitor self-test

Command:

```bash
./ollama-monitor.sh --self-test --no-zip
```

Checks:

- Report generation completes.
- Terminal summary is generated.
- Inference exercise coverage is printed.
- Self-test still flags synthetic PCIe/clock observations without requiring `nvidia-smi` on the validation host.

Result: PASS.

## Fake Ollama HTTP 500 model-load classification

A local fake Ollama API server returned successful `/api/tags`, `/api/version`, `/api/show`, and `/api/ps`, but returned HTTP 500 for `/api/generate`:

```json
{"error":"unable to load model: /home/alex/.ollama/models/blobs/sha256-f5ee307a2982106a6eb82b62b2c00b575c9072145a759ae4660378acda8dcf2d"}
```

Command:

```bash
./ollama-test-RTX3090.sh \
  --base-url http://127.0.0.1:<port> \
  --model qwen3:fake \
  --no-conc \
  --no-cpu \
  --no-vram-pressure \
  --no-zip \
  --no-terminal-summary \
  --no-wsl-diagnostics \
  --timeout-sec 5
```

Expected result:

- Script exits `1` because all generation rows fail.
- `summary.csv` contains `http_code=500`, `error_class=model_load_error`, and the full API error body.
- `failure-hints.txt` contains `primary_error_class=model_load_error`, `api_error_rows=4`, and the referenced blob path.
- `terminal-summary.txt` marks inference health as `INCONCLUSIVE`.

Result: PASS.

## Package validation

Commands performed during final packaging:

```bash
find ollama-info -type f | sort
sha256sum <package files>
zip -r ollama-info-v0.9.zip ollama-info
unzip -q ollama-info-v0.9.zip -d verify
```

Result: PASS.

## Known limitations

- The validation host did not run a real RTX 3090/Ollama inference workload. The synthetic validation checks the failure-classification path and monitor report generation.
- WSL2/NVIDIA driver recommendations in the README are operational guidance; the scripts still do not modify Windows, WSL, NVIDIA, or Ollama service settings automatically.
