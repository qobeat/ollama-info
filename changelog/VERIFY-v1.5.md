# VERIFY v1.5

Validation performed in the build container. Real RTX 3090 execution was not available here, so hardware and Ollama behavior were validated with fake Ollama, fake nvidia-smi, and fake systemctl shims where required.

## Static validation

- PASS `bash -n` for all `scripts/ollama-*` files.
- PASS `bash -n bashrc/.bashrc`.
- PASS package layout contains `scripts/`, `changelog/`, `bashrc/`, `README.md`, and `PACKAGE-MANIFEST.txt`.
- PASS executable scripts are under `scripts/`.
- PASS change/audit files are under `changelog/`.

## CLI and status validation

- PASS no-argument orchestrator screen stays compact and lists status/models/commands without full help.
- PASS missing model path lists available local models and command lines without full help.
- PASS `ollama-status --models` supports `OLLAMA_MODEL_COMMAND="ollama test"`.
- PASS fake systemd fallback detects `ollama.service` as `load=loaded active=active enabled=enabled` even when `systemctl show LoadState` returns `not-found` but `systemctl status` shows loaded.
- PASS bashrc wrapper routes `ollama models` to package helper and preserves `ollama list` pass-through.
- PASS missing option value such as `--model` prints `ERROR: --model requires a value. Use -h for full help.`

## Test and monitor behavior

- PASS fake successful direct test run writes summary.csv, summary.md, failure-hints.txt, raw JSON, payload JSON, and plain terminal summary.
- PASS successful direct test failure hints report `primary_error_class=none` and `api_error_rows=0`.
- PASS fake successful orchestrated run starts monitor, captures NVIDIA boundary snapshots, runs direct test collector, builds orchestrator summary, and prints final summary.
- PASS fake HTTP 500 model-load run classifies `primary_error_class=model_load_error`, counts API error rows, extracts referenced sha256 blob path, and prints actionable likely cause/next action.
- PASS monitor self-test generates report.md, gpu.csv, terminal-summary.txt, and plain final summary.

## Display contract validation

- PASS direct test output: timestamped preflight/START/DONE progress lines appear before the final summary; final summary block has zero timestamp-prefixed lines.
- PASS orchestrator output: timestamped collector/progress lines appear before the final summary; final summary block has zero timestamp-prefixed lines.
- PASS monitor self-test output: timestamped monitor stop/progress line appears before the final summary; final summary block has zero timestamp-prefixed lines.
- PASS orchestrator suppresses the direct test collector's terminal summary; it emits one timestamped collector-completed line and one final plain orchestrator summary.

## Downloader validation

- PASS one-argument aria2 dry-run parses `unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`.
- PASS downloader infers destination path and model name.
- PASS downloader preserves compact `--method aria2 SOURCE` workflow.

## Archive validation

- PASS package manifest regenerated for v1.5.
- PASS zip archive integrity checked with `unzip -t`.

## Known validation limit

- A real RTX 3090 workload was not run inside this environment. The generated scripts retain the same real-run paths and were validated with deterministic shims.
