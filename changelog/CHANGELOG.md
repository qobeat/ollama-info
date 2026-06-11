# v1.8.0 - empty-card ADOS capability profile and unified wrapper

- Added `scripts/ollama.sh` as the canonical wrapper for `status`, `start`, `stop`, `models`, `gpu`, `logs`, `test`, `bench`, and `embed-test`.
- Added multi-model command support, for example `ollama test qwen3.6:35b qwen3.6:27b` and `ollama bench qwen3-embedding:4b qwen3.6:27b`.
- Changed the default generation profile to three ADOS capability prompts: coding, essay, and internet-access boundary behavior.
- Preserved the v1.7 performance rows under `--profile perf` / `--profile legacy-perf`.
- Changed default load mode to `empty-card`, which unloads all resident Ollama models before the first request and records `empty_card_requested`, `empty_card_verified`, and `load_state_verdict`.
- Refactored the bashrc integration to delegate to `ollama.sh` instead of duplicating benchmark/control logic.
- Converted `ollama-bench-RTX3090.sh` into a compatibility shim to the unified wrapper.
- Added capability-analysis evidence for the three default prompts.
- Added v1.8 ADOS plan, review, verification, reflection, self-evaluation, test-results review, and evidence ledger artifacts.

# v1.7.0 - role-aware benchmark routing, latency metrics, load-state semantics, and cleanup

## v1.7.1 - load-state/offload evidence fix

- Tightened observed-mode FirstReqLoad semantics: observed mode no longer claims verified cold merely because the tested model was absent.
- Added model-switch detection when another model is resident before a benchmark.
- Added post-run Ollama residency/offload classification from `ollama ps`.
- Replaced misleading orchestrator `single GPU` label with `single-request` unless full-GPU residency is established.
- Split TTFT reporting into FirstTTFT, WarmTTFT, and TTFTall.
- Added monitor report section for CPU/GPU mixed residency.


- Added `scripts/ollama-bench-RTX3090.sh` and Bash wrapper support for `ollama bench MODEL`, which auto-routes generation-capable models to `/api/generate` and embedding-only models to `/api/embed`; `--route-only` prints the route without running a benchmark.
- Changed strict generation behavior for embedding-only models from generic benchmark failure to `UNSUPPORTED`, exit code `2`, tag-preserving next actions, and zero API error-row inflation.
- Expanded embedding benchmark mode to four `/api/embed` rows: sanity, 32-item batch, long-context, and RAG-profile chunks.
- Added streaming generation instrumentation with `ttft_any_ms`, `ttft_thinking_ms`, `ttft_answer_ms`, `time_to_100_tokens_ms`, `end_to_end_500_ms`, `decode_tps_raw`, `visible_answer_tps`, and `thinking_only` fields.
- Renamed misleading `Cold` reporting to `FirstReqLoad` and added `--load-mode observed|warm|unload-model|restart-ollama` with saved load-state evidence.
- Added sample validity classification, including `SHORT_SAMPLE`, `UNDERFILLED`, and `UNSUPPORTED`, with minimum generated-token and long-context fill thresholds.
- Made model metadata extraction architecture-agnostic for context length and embedding length keys such as `gptoss.context_length`, `qwen35.context_length`, and other `*.context_length` / `*.embedding_length` fields.
- Calibrated RTX 3090 telemetry warnings: software power-limit samples are reported as power-cap behavior, hardware slowdown is critical, memory junction unavailable is unknown, and VRAM/PCIe warnings are severity-scoped.
- Added richer WSL/filesystem/storage diagnostics and broader `nvidia-smi -q` capture.
- Removed legacy/generated package debris: `scripts/legacy/`, obsolete `changelog/plan.txt`, run archives, cache files, and the legacy Python dependency in `ollama-perf-table`.
- Added ADOS apply/verify quality artifacts under `qa-evidence/`, including a schema-validated `evidence-ledger.jsonl`.

# v1.6.0 - capability-aware model roles and embedding benchmark mode

- Reviewed the `bge-m3` failure and classified it as an embedding-only model being sent to `/api/generate`, not as an RTX 3090/Ollama service failure.
- Reviewed the later `gemma3:1b` output as a successful generation benchmark on the RTX 3090 path.
- Added `/api/show` capability preflight and slim model metadata capture by default.
- Added `unsupported_generate_for_embedding_model` failure classification with targeted failure hints.
- Added `/api/embed` benchmark mode, vector count/dimension metrics, and embedding throughput fields.
- Added `scripts/ollama-embed-test-RTX3090.sh` and Bash wrapper command `ollama embed-test`.
- Updated `ollama models` suggestions to show model role, size, and role-appropriate command.
- Changed summary semantics to separate `Telemetry` from `Inference` and report LongCtx/LongEmb as N/A when prompt evaluation never occurred.
- Split dmesg scan into new-during-run and historical-since-boot sections.
- Updated README, Bash README, review, verify, reflection, and atomic requirement audit for v1.6.

# v1.5.0 - atomic requirements audit and Bash 5.2+ cleanup

- Added `changelog/atomic-requirements-v1.5.txt` with README/changelog-derived atomic requirements and final implementation status.
- Added `changelog/plan-1.5.txt` with implementation review findings, architecture issues, usability issues, and fix plan.
- Updated package target from generic Bash 4+ to Bash 5.2+.
- Centralized common Bash helpers for timestamps, warnings, integer checks, command checks, script path display, argument-value validation, and timestamped stream logging and plain summary printing in `ollama-common.sh`.
- Hardened option parsing so missing values such as `--model` or `--method` produce clear errors instead of shell `shift` failures.
- Kept `timeout` as optional by falling back to curl `--max-time` when GNU timeout is unavailable.
- Cleaned downloader duplicated code paths, timestamped downloader operational logs, and preserved one-source-argument aria2 workflow.
- Fixed README artifact naming drift: monitor CSV is `gpu.csv`, not `samples.csv`.
- Changed final terminal summary display so progress/collector lines remain timestamped, while final summary blocks are plain and untimestamped.
- Removed `realpath` from script-directory resolution; scripts now use Bash/core shell path resolution and keep `realpath` only as an optional downloader local-path convenience.

# v1.4.0 - production README and safe default baseline

- Reworked README into a production-grade project document covering functionality, architecture, script status, artifact layout, operations, and troubleshooting.
- Changed default baseline to single-request mode: `RUN_CONC=0`, `CONCURRENCY=1`.
- Normal command is now `ollama test qwen3.6`; previous `--no-conc --concurrency 1` flags are no longer needed.
- Added `--stress` shorthand for `--run-conc --concurrency 2`.
- Updated short help text to distinguish baseline and stress runs.
- Updated `ollama models` UX through `.bashrc` so suggested commands use `ollama test <model>`.
- Added `OLLAMA_MODEL_COMMAND` override to `ollama-status --models`.

# v1.3.0 - timestamped logs, clean error hints, NVIDIA snapshots, package reorg

- Moved executable scripts into `scripts/`.
- Moved changelog/review/verify/reflection files into `changelog/`.
- Fixed false-positive `api_error` classification where successful Ollama `/api/generate` JSON was treated as an error body.
- Suppressed terminal error-hint blocks when `primary_error_class=none`.
- Added ISO timestamp prefixes to operational test/monitor/orchestrator log lines.
- Added orchestrator-level NVIDIA start/end snapshots to `ollama-test-and-monitor-RTX3090.sh` under `hardware/`.
- Cleaned `.bashrc` so it prepends `~/dev/ollama-info/scripts` and uses one Ollama compatibility wrapper.

# Changelog

## v1.2.0

- Added interactive `.bashrc` shell wrapper for `ollama status`, `ollama start`, `ollama stop`, `ollama models`, `ollama logs`, `ollama gpu`, and `ollama test ...` while preserving pass-through for normal Ollama CLI commands.
- Hardened `.bashrc` fallback service detection with `systemctl cat/status` and unit-file path checks.

- Fixed `ollama-start` and `ollama-stop` for system services that require privileged systemd actions. Non-root callers now go through `sudo systemctl start|stop ollama.service` and get the normal sudo password prompt.
- Fixed systemd service detection by removing the hard dependency on PID 1 being named `systemd`; helpers now use `systemctl show/cat/list-unit-files/list-units/status` and correctly detect `/etc/systemd/system/ollama.service` in the observed WSL setup.
- Updated `ollama-status --brief` to report system service load/active/enabled state more accurately.
- Updated the packaged `.bashrc` fallback helpers for sudo-aware systemd start/stop and improved service detection.
- Added an optional `.bashrc` compatibility wrapper so `ollama status`, `ollama start`, `ollama stop`, `ollama logs`, `ollama models`, `ollama gpu`, and `ollama test` route to package helpers while ordinary Ollama CLI subcommands still call the real CLI.
- Simplified `ollama-download.sh`: it now accepts one positional source argument, including a Hugging Face file URL, `ORG/REPO/model.gguf` shorthand, or a local GGUF path.
- Added automatic inference of GGUF filename, download directory, Ollama model name, and default `PARAMETER num_ctx 8192` in one-argument downloader mode.
- Improved downloader resume behavior by skipping already-complete destination files unless `--force` is used.
- Validated the `aria2` path with a fake `aria2c` transfer that created a GGUF file and triggered `ollama create` with the inferred model name.

## v1.1.0

- Changed no-argument behavior for `ollama-test-and-monitor-RTX3090.sh` and `ollama-test-RTX3090.sh` to show compact usage, Ollama status, and local model run commands only.
- Kept full help behind `-h` / `--help`; unknown, missing, and ambiguous model paths no longer dump the full option list.
- Added pre-run Ollama API gating. Tests do not auto-start Ollama; if the API is down, the scripts stop and print a systemd start/check command.
- Added `ollama-common.sh` shared helpers for compact status, systemd detection, model resolution, and model command printing.
- Updated `ollama-start`, `ollama-stop`, and `ollama-status` for systemd-managed `ollama.service`; `ollama-status --short` and `ollama-status --models` were added.
- Updated packaged `.bashrc` to call `ollama-status --short` and keep Ollama server configuration out of the interactive shell.

## v1.0.0

- Added short model-pattern runner support, for example `ollama-test-and-monitor-RTX3090.sh qwen3.6`.
- Added model-pattern resolution to the direct RTX test script.
- Added reviewed WSL2 `.bashrc` candidate and systemd-oriented Ollama helper commands.

## v0.9.0

- Upgraded RTX test, monitor, and orchestrator scripts to v0.9 signatures.
- Preserved HTTP status and Ollama API error body for failed generation requests.
- Added `http_code`, `error_class`, and `error_body` columns to `summary.csv`.
- Added `failure-hints.txt` with model-load classification, referenced blob path, likely cause, next action, model size GiB, and free VRAM when available.
- Added preflight artifacts: `/api/version`, `/api/tags`, `/api/show`, `ollama show`, `ollama list`, WSL diagnostics, and Ollama server log tail.
- Added `--server-log-lines`, `--wsl-diagnostics`, and `--no-wsl-diagnostics`.
- Updated monitor reports to state whether an Ollama loaded-model snapshot was observed, preventing idle/failed-load telemetry from being misread as completed inference health.
- Updated orchestrator summaries to mark inference health as inconclusive when tests fail before valid token generation.
- Updated README with RTX 3090 + WSL2 setup recommendations and model-load failure remediation.

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
