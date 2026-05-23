# CHANGELOG

## v0.5 - 2026-05-23

- Rebuilt `ollama-monitor.sh` with richer RTX/Ollama telemetry and automatic zip archive generation.
- Added `ollama-test-RTX3090.sh` for model sanity, throughput, sustained generation, long-context, concurrency, and optional CPU-reference tests.
- Added `ollama-test-and-monitor-RTX3090.sh` orchestrator to run tests while collecting telemetry.
- Made `ollama-gen` self-contained.
- Fixed `ollama-start` to call package-local `ollama-status`.
- Expanded `ollama-status` GPU/model diagnostics.
- Added `REVIEW-v0.5.md` and `REFLECTION-v0.5.md`.
