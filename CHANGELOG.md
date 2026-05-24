# Changelog

## v0.8.0

- Added `ollama-download.sh`, a resumable GGUF downloader/importer for unstable WSL2 connections.
- Added `--method auto|hf|aria2|curl` with retry loops and resume-aware local destination handling.
- Added Hugging Face repo/file support with `--repo`, `--file`, and `--revision`.
- Added direct URL support with aria2/curl resume behavior.
- Added private/gated Hugging Face support through `hf auth login`, `HF_TOKEN`, or `HUGGING_FACE_HUB_TOKEN`; token-bearing downloader inputs are written to temporary files instead of process argv.
- Added local GGUF verification: non-empty check, GGUF magic-byte warning, computed SHA256 logging, and optional `--sha256` enforcement.
- Added automatic Modelfile generation and `ollama create` integration through `--name`, `--param`, and `--num-ctx`.
- Updated README with downloader requirements, quick start, command reference, output structure, safety note, and v0.8 validation notes.

## v0.7.0

- Added true long-context prompt generation with `--long-prompt-words`.
- Added category-aware performance summaries: cold, warm, long-context, concurrency, optional soak, optional VRAM pressure.
- Added `concurrency-aggregate.csv` to avoid misleading per-request-only concurrency interpretation.
- Fixed curl/timeout return-code capture.
- Added lock-protected CSV appends for parallel requests.
- Added optional `--soak-minutes` probe.
- Added optional `--run-vram-pressure --vram-model ...` probe.
- Added `nvidia-smi -q` start/end snapshots.
- Added GPU-related `dmesg` scan.
- Added monitor health verdicts and clearer PCIe/throttle/memory-temperature observations.
- Moved Python helpers to `tools/legacy/`; main RTX3090 workflow is Bash-only.
- Rewrote README as a first-class package document.

## v0.6.0

- Added compact final ASCII terminal summaries for monitor, test, and orchestrator runs.
- Streamed test progress to terminal.
- Added explicit `--think false|true|none|low|medium|high`.
- Changed orchestrator summary from a full nested report dump into a compact index.

## v0.5.0

- Added RTX3090 test script and combined test+monitor orchestrator.
- Added ZIP archive creation under `~/tmp`.
- Added monitor report and raw evidence retention.
