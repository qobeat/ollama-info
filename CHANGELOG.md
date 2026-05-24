# CHANGELOG

## v0.6.0 - 2026-05-23

- Added compact ASCII terminal summaries for monitor, test, and orchestrated runs.
- Made orchestrator stream test progress to terminal via `tee` while preserving `test.console.log`.
- Added top-level Ollama `think` request control with default `false`; this addresses Qwen3 thinking-token runs that produced empty `response` fields.
- Reduced `orchestrator-summary.md` duplication; it now references nested detailed files instead of embedding all content.
- Added terminal summary artifacts to archives.
- Updated README retention guidance explaining why summary.md/report.md, CSV, raw JSON, payload JSON, and gpu.csv should all be kept.

## v0.5.0 - 2026-05-23

- Added RTX3090 monitor/test/orchestrator scripts.
- Added automatic zip creation under `~/tmp`.
- Added richer GPU/Ollama telemetry capture.
