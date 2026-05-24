# REVIEW-v0.9

## Triggering observation

The supplied run of `ollama-test-and-monitor-RTX3090.sh` against `qwen3.6:35b` failed every test request with HTTP 500. The old terminal output reduced the actionable evidence to `curl: (22)`, while the raw JSON contained the actual Ollama error:

```text
unable to load model: /home/alex/.ollama/models/blobs/sha256-f5ee307a2982106a6eb82b62b2c00b575c9072145a759ae4660378acda8dcf2d
```

The monitor simultaneously reported low VRAM use and no loaded Ollama model snapshots, so `Health: PASS` described idle/failed-load telemetry rather than completed inference health.

## v0.9 review decisions

- Preserve HTTP bodies on failed `/api/generate` responses.
- Add explicit `http_code`, `error_class`, and `error_body` fields to the test CSV.
- Add a first-pass failure classifier for model-load, model-file/manifest, memory, permission, timeout, transport, and generic HTTP/server errors.
- Capture preflight model/server state before the test begins.
- Capture Ollama server log tails after the run.
- Capture WSL configuration evidence when available.
- Add `failure-hints.txt` as a compact next-action artifact.
- Make terminal summaries state `INCONCLUSIVE` when no valid tokens were generated.
- Make monitor reports state whether any loaded Ollama model snapshot was observed.
- Keep all changes read-only and diagnostic; do not alter GPU, WSL, service, or model-store state automatically.

## Code review notes

- `curl --fail-with-body` was replaced in the generation path with explicit `--output` + `--write-out '%{http_code}'` so HTTP error bodies are retained.
- Parallel CSV writes remain lock-protected.
- New artifacts are included in Markdown and terminal file lists.
- Orchestrator propagates `--server-log-lines` and `--no-wsl-diagnostics` to the test script.
- `ollama-monitor.sh --self-test` still works and now includes inference exercise coverage.

## Follow-up opportunities

- Add an optional `--preload` phase to isolate model-load time from benchmark rows.
- Add a small known-good model smoke test before large-model tests.
- Add optional comparison between `ollama ps` processor placement and requested GPU/CPU mode.
- Add a machine-readable `verdict.json` for automation.
