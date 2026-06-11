# ollama-info v1.7

Production-oriented RTX 3090 + WSL2 + Ollama diagnostics and benchmark package.

`ollama-info` provides shell tooling around Ollama, NVIDIA telemetry, and systemd so a local workstation can answer four operational questions quickly:

1. **Is Ollama running correctly?**
2. **Is the requested model available, loadable, and role-compatible?**
3. **Is the RTX 3090 healthy under a controlled Ollama workload?**
4. **How does the model behave for generation, embedding/RAG, load-state, and latency-sensitive local-agent workflows?**

The preferred v1.7 entry point is the role-aware benchmark command:

```bash
ollama bench qwen3.6:27b
ollama bench qwen3-embedding:4b
```

`ollama bench` resolves the local model, reads Ollama metadata, and routes by role:

```text
generation-capable model -> monitored /api/generate benchmark
embedding-only model     -> monitored /api/embed benchmark
unknown role             -> preflight refusal with evidence
```

Strict explicit commands remain available:

```bash
ollama test qwen3.6:27b          # generation benchmark only
ollama embed-test bge-m3:latest  # embedding benchmark only
```

Embedding-only models are no longer treated as failed generation benchmarks. In strict generation mode, v1.7 reports `UNSUPPORTED`, preserves the full model tag in the suggested next command, exits with code `2`, and does not count the capability preflight as an API error row.

---

## Current status

v1.7 builds on the v1.6 package and implements the requested benchmark-plan changes plus package cleanup. The package layout is:

```text
ollama-info/
  README.md
  PACKAGE-MANIFEST.txt
  bashrc/
    .bashrc
    README.md
  scripts/
    ollama-common.sh
    ollama-status
    ollama-start
    ollama-stop
    ollama-bench-RTX3090.sh
    ollama-test-and-monitor-RTX3090.sh
    ollama-test-RTX3090.sh
    ollama-embed-test-RTX3090.sh
    ollama-monitor.sh
    ollama-download.sh
    ollama-gen
    ollama-perf
    ollama-perf-table
  changelog/
    CHANGELOG.md
    atomic-requirements-v1.7.txt
    plan-1.7.txt
    REVIEW-v1.7.md
    VERIFY-v1.7.md
    REFLECTION-v1.7.md
    REVIEW-*.md
    VERIFY-*.md
    REFLECTION-*.md
  qa-evidence/
    ados-apply-verify-schema.json
    evidence-ledger.jsonl
```

Clean-up changes in v1.7:

```text
removed scripts/legacy/ Python calculators
removed obsolete changelog/plan.txt if present
removed generated run/archive/cache artifacts from the package boundary
removed the old legacy-Python dependency from ollama-perf-table
kept only source, docs, manifest, and ADOS evidence artifacts in the release archive
```

---

## v1.7 audit artifacts

The package includes explicit review, verification, and ADOS evidence artifacts:

```text
changelog/atomic-requirements-v1.7.txt   atomic requirements and final status
changelog/plan-1.7.txt                   applied plan, including cleanup requirements
changelog/REVIEW-v1.7.md                 implementation review and limitations
changelog/VERIFY-v1.7.md                 verification record and commands
changelog/REFLECTION-v1.7.md             final requirement completion check
qa-evidence/evidence-ledger.jsonl         single normative ADOS evidence ledger
qa-evidence/ados-apply-verify-schema.json validation schema used for the ledger
```

Verification used syntax checks, package hygiene checks, ADOS ledger schema validation, and a local fake Ollama/NVIDIA harness. The sandbox verification validates behavior and packaging, not real RTX 3090 performance numbers.

---

## Feature coverage

| Feature group | v1.7 coverage |
|---|---|
| Product scope | RTX 3090 + WSL2 + Ollama status, model availability/loadability, role-aware benchmark routing, controlled workload health, evidence archive. |
| Runtime contract | Bash 5.2+ target, strict-mode shell scripts, curl/jq core dependencies, optional `timeout`, optional aria2/journalctl. |
| CLI UX | Short primary `ollama bench MODEL` command, strict `ollama test MODEL`, explicit `ollama embed-test MODEL`, no-arg compact dashboard, concise errors. |
| Model resolution | `/api/tags` model discovery, exact/full/base/substring resolution, role-aware suggested commands. |
| Dynamic metadata | Architecture-agnostic extraction for family, architecture, parameter size/count, quantization, context length, embedding length, capabilities, and size on disk. |
| Generation benchmark | `/api/generate` sanity/throughput/sustained/long-context rows, streaming enabled by default, TTFT fields, visible-answer throughput, thinking-only detection, sample quality status. |
| Embedding benchmark | `/api/embed` sanity, batch, long-context, and RAG-profile rows with vector count, vector dimension, prompt tokens, embeddings/sec, and embedding token throughput. |
| Capability preflight | Embedding-only generation refusal reports `UNSUPPORTED`, not generic `FAIL`; `ollama bench` auto-routes by model role. |
| Load-state semantics | Replaces misleading `Cold` label with `FirstReqLoad`; records load-state preconditions and supports `--load-mode observed|warm|unload-model|restart-ollama`. |
| Sample validity | Marks rows as `OK`, `SHORT_SAMPLE`, or `UNDERFILLED`; default thresholds include decode512 >=384 tokens, decode1024 >=900 tokens, longctx >=65% fill and >=256 eval tokens. |
| Monitoring | Continuous `gpu.csv`, monitor `report.md`, start/end NVIDIA snapshots, calibrated thermal/power/VRAM/PCIe warning levels. |
| Hardware warnings | `sw_power` is reported as power-cap behavior; `hw_slowdown` is separated as critical. Memory junction unavailable is `unknown`, not pass/fail. |
| Environment diagnostics | Captures filesystem/mount/lsblk/WSL/kernel diagnostics and richer `nvidia-smi -q` sections. |
| Evidence retention | Raw JSON, streaming NDJSON, TTFT metrics, stderr, payload JSON, summaries, failure hints, load-state, server log tail, WSL diagnostics, zip archive. |
| Bash integration | `ollama status/start/stop/models/bench/test/embed-test/logs/gpu` helpers with upstream CLI pass-through. |

---

## Production readiness by script

| Script | Status | Purpose |
|---|---:|---|
| `scripts/ollama-bench-RTX3090.sh` | Primary / production | Auto-routes a model to generation or embedding benchmark by Ollama model role. |
| `scripts/ollama-test-and-monitor-RTX3090.sh` | Primary / production | Orchestrates test + monitor + NVIDIA boundary snapshots + archive. |
| `scripts/ollama-test-RTX3090.sh` | Production engine | Runs deterministic `/api/generate` or `/api/embed` requests, captures raw artifacts, CSV, summary, and failure classification. |
| `scripts/ollama-embed-test-RTX3090.sh` | Production wrapper | Convenience wrapper for monitored `/api/embed` benchmark mode. |
| `scripts/ollama-monitor.sh` | Production monitor | Samples GPU, PCIe, power, VRAM, clocks, throttling, Ollama process/model state, and writes CSV/report artifacts. |
| `scripts/ollama-status` | Production helper | Reports systemd service state, API status, GPU quick state, models, logs, disk usage, and loaded runners. |
| `scripts/ollama-start` | Production helper | Starts system `ollama.service` with sudo when needed; falls back only when no service exists. |
| `scripts/ollama-stop` | Production helper | Stops system `ollama.service` with sudo when needed; has optional direct process-kill fallback. |
| `scripts/ollama-download.sh` | Production utility | Downloads GGUF models from Hugging Face or local source, optionally through `aria2c`, creates an Ollama Modelfile/model. |
| `scripts/ollama-common.sh` | Internal shared library | Shared model resolution, status, systemd, API, metadata, and command-printing functions. Source only; do not run directly. |
| `scripts/ollama-gen` | Utility | General Ollama generation helper retained for convenience. |
| `scripts/ollama-perf` / `scripts/ollama-perf-table` | Utility | Older ad-hoc performance helpers retained without legacy Python dependencies. Prefer `ollama bench` for governed evidence. |

---

## Quick start

From the package directory:

```bash
cd ~/dev/ollama-info
chmod +x scripts/ollama-*
```

Optional shell integration:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
hash -r
```

Check the setup:

```bash
ollama status
ollama models
```

Run the role-aware benchmark:

```bash
ollama bench qwen3.6:27b
ollama bench qwen3-embedding:4b
```

Run strict explicit paths:

```bash
ollama test qwen3.6:27b
ollama embed-test bge-m3:latest
```

Direct forms without the `.bashrc` wrapper:

```bash
./scripts/ollama-bench-RTX3090.sh qwen3.6:27b
./scripts/ollama-test-and-monitor-RTX3090.sh qwen3.6:27b
./scripts/ollama-test-and-monitor-RTX3090.sh bge-m3:latest --embedding
```

---

## Requirements

Core runtime:

```text
Bash 5.2+
curl
jq
awk / sed / grep
zip / unzip
Ollama CLI and reachable Ollama API
NVIDIA driver exposed to WSL2 with nvidia-smi available
systemd, for the recommended Ollama service setup
```

Optional utilities:

```text
aria2c      faster/resumable GGUF downloads
journalctl  richer service-log capture
timeout     safer command time limits
```

Full help is printed only when explicitly requested:

```bash
ollama-bench-RTX3090.sh -h
ollama-test-and-monitor-RTX3090.sh -h
ollama-test-RTX3090.sh -h
ollama-download.sh -h
ollama-status --help
```

---

## Command behavior

### No parameters

```bash
ollama-test-and-monitor-RTX3090.sh
```

Shows a compact operational screen:

```text
short usage
Ollama status
available local models
command line for each model
pointer to -h / --help
```

It does not print the full help.

### Role-aware model commands

`ollama models` now asks Ollama for model details and prints role-aware command suggestions using `ollama bench` by default.

Example shape:

```text
MODEL                 ROLE        SIZE     SUGGESTED COMMAND
bge-m3:latest         embedding   1.2GB    ollama bench bge-m3:latest
gemma3:1b             generate    0.8GB    ollama bench gemma3:1b
```

### Model pattern resolution

The scripts query local Ollama tags from `/api/tags` and resolve the model pattern in this order:

1. exact full model name, for example `qwen3.6:27b`;
2. exact base name before `:`, for example `qwen3.6`;
3. unique case-insensitive substring match.

If the model is missing, the scripts list available local models and suggested commands. If the pattern is ambiguous, they list only matching models and exact commands.

### Strict generation vs auto-route

Use `ollama test MODEL` when the intent is specifically generation. For an embedding-only model, v1.7 records a single preflight evidence row and exits `2` with:

```text
result_state=UNSUPPORTED
error_class=unsupported_generate_for_embedding_model
recommended_endpoint=/api/embed
next_action=use ollama embed-test MODEL or ollama bench MODEL
```

Use `ollama bench MODEL` when you want the package to choose the correct benchmark mode from model metadata.

For verification or scripting, `ollama bench MODEL --route-only` resolves the model role and prints the selected route without running the benchmark.

---

## Bash integration

`bashrc/.bashrc` adds `~/dev/ollama-info/scripts` to `PATH` and wraps a few convenience subcommands while preserving normal Ollama CLI behavior.

Package helper commands:

```bash
ollama status            # package status helper
ollama start             # sudo-aware systemctl start ollama.service
ollama stop              # sudo-aware systemctl stop ollama.service
ollama models            # local models + role-aware suggested commands
ollama bench qwen3.6     # auto-route benchmark workflow
ollama test qwen3.6      # strict generation benchmark workflow
ollama embed-test bge-m3 # strict embedding benchmark workflow
ollama logs 200          # journalctl tail
ollama gpu               # nvidia-smi CSV snapshot
```

Normal upstream Ollama commands still pass through:

```bash
ollama list
ollama ps
ollama pull llama3.2
ollama run llama3.2
ollama serve
```

Important: upstream Ollama may not provide native `status`, `bench`, or `embed-test` subcommands in your installed CLI. These are package wrapper conveniences.

If the wrapper still shows an old script version, refresh the shell command cache and inspect path order:

```bash
hash -r
type -a ollama-bench-RTX3090.sh
type -a ollama-test-and-monitor-RTX3090.sh
type -a ollama-status
type ollama
```

---

## Systemd and Ollama service model

This package assumes the preferred production setup is systemd-managed Ollama:

```bash
sudo systemctl start ollama
sudo systemctl stop ollama
systemctl status ollama --no-pager
journalctl -u ollama -n 120 --no-pager
```

`ollama-start` and `ollama-stop` are sudo-aware. Server-side Ollama environment variables should live in a systemd override, not `.bashrc`, because a system service does not inherit interactive shell variables.

Example override path:

```bash
sudo systemctl edit ollama
```

Typical conservative service settings for a single RTX 3090 baseline:

```ini
[Service]
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_FLASH_ATTENTION=1"
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## Test architecture

### High-level flow

```text
user command
  -> bash wrapper, optional
  -> ollama-bench-RTX3090.sh, optional auto-router
  -> ollama-test-and-monitor-RTX3090.sh
      -> preflight status/model/API checks
      -> capture start nvidia-smi snapshots
      -> start ollama-monitor.sh in background
      -> run ollama-test-RTX3090.sh
      -> stop monitor
      -> capture end nvidia-smi snapshots
      -> build orchestrator summary
      -> zip full run directory
```

### Generation benchmark mode

The default v1.7 generation baseline runs four `/api/generate` GPU API tests:

| Test | Purpose |
|---|---|
| `01_sanity_gpu` | Confirms the model loads and generates visible output. |
| `02_throughput_gpu` | Measures normal short-context generation throughput. |
| `03_sustained_gpu` | Measures longer generation stability and throughput. |
| `04_longctx_gpu` | Measures long-context prompt ingestion and generation. |

Default parameters:

```text
num_ctx=4096
long_ctx=8192
num_predict=512
long_num_predict=1024
long_prompt_words=3200
think=false
stream=true
load_mode=observed
run_conc=0
concurrency=1
monitor_profile=deep
interval=1s
```

Generated summary fields include:

```text
FirstReqLoad
ttft_any_ms
ttft_thinking_ms
ttft_answer_ms
time_to_100_tokens_ms
end_to_end_500_ms
decode_tps_raw
visible_answer_tps
thinking_only
sample_status
result_state
```

Optional probes:

```bash
ollama test qwen3.6 --run-conc --concurrency 2
ollama test qwen3.6 --stress
ollama test qwen3.6 --soak-minutes 10
ollama test qwen3.6 --run-vram-pressure --vram-model larger-model:tag
```

### Embedding benchmark mode

Use embedding mode for retrieval/RAG models:

```bash
ollama embed-test bge-m3:latest
ollama test bge-m3:latest --embedding
./scripts/ollama-test-and-monitor-RTX3090.sh bge-m3:latest --embedding
```

Embedding mode uses `/api/embed`, not `/api/generate`, and records:

```text
endpoint=/api/embed
vector_count
vector_dim
embedding_tps
embedding_tokens_per_s
prompt_eval_tokens
context_fill_pct
sample_status
result_state
```

Default embedding rows:

| Test | Purpose |
|---|---|
| `01_embed_sanity` | Confirms the model returns at least one embedding vector. |
| `02_embed_batch` | Confirms a 32-item batch produces vectors and records vector count/dimension. |
| `03_embed_longctx` | Exercises long text embedding and reports prompt-token fill when Ollama returns it. |
| `04_embed_rag_profile` | Exercises realistic code/doc chunks for local RAG indexing. |

### Load-state / cold-mode semantics

v1.7 stops calling the first request a verified cold load unless the preconditions are observed.

```text
FirstReqLoad     Ollama load_duration on the first request
ColdVerified     true only if model absence/unload/restart preconditions were verified
```

Supported modes:

```bash
--load-mode observed       # default; records model residency before the run
--load-mode warm           # does not claim cold verification
--load-mode unload-model   # attempts role-aware keep_alive:0 unload before measuring
--load-mode restart-ollama # attempts service restart before measuring
```

The package does not infer disk throughput from Ollama `load_duration`.

### Sample validity

v1.7 classifies rows before using them as clean benchmark evidence:

```text
OK             row met the validity threshold
SHORT_SAMPLE   generation ended too early for stable throughput comparison
UNDERFILLED    long-context row did not fill enough of the target context
UNSUPPORTED    role/capability mismatch, such as embedding-only model in generation mode
```

Default thresholds:

```text
decode512:   eval_tokens >= 384
decode1024:  eval_tokens >= 900
longctx8k:   context_fill >= 65%, eval_tokens >= 256
```

---

## Monitoring and collected evidence

Each orchestrated run writes artifacts under:

```text
~/log/ollama-test-and-monitor-RTX3090/run-YYYYMMDD-HHMMSS/
```

Key files:

```text
orchestrator-summary.md
terminal-summary.txt
errors.log
hardware/
  nvidia-smi-start.txt
  nvidia-smi-end.txt
  nvidia-smi-q-start.txt
  nvidia-smi-q-end.txt
  nvidia-smi-query-start.csv
  nvidia-smi-query-end.csv
  nvidia-compute-apps-start.csv
  nvidia-compute-apps-end.csv
monitor/
  run-*-monitor/report.md
  run-*-monitor/gpu.csv
test/
  run-*-test/summary.md
  run-*-test/summary.csv
  run-*-test/load-state.txt
  run-*-test/failure-hints.txt
  run-*-test/raw/*.json
  run-*-test/raw/*.stream.ndjson
  run-*-test/raw/*.stream-metrics.json
  run-*-test/raw/*.stderr
  run-*-test/payloads/*.json
  run-*-test/ollama-server-log-tail.txt
```

A zip archive is also written under:

```text
~/tmp/ollama-test-and-monitor-RTX3090-YYYYMMDD-HHMMSS.zip
```

### Hardware warning calibration

A successful run should distinguish inference success from telemetry warnings:

```text
Inference: PASS or PASS_WITH_WARNINGS
Telemetry: PASS or PASS_WITH_WARNINGS
```

Common interpretation:

| Signal | Meaning |
|---|---|
| `Test: PASS` | Ollama API requests completed for the selected mode. |
| `Test: UNSUPPORTED` | The requested mode is not supported by the model role. |
| `Inference: PASS` | A completed generation or embedding benchmark was observed. |
| `Telemetry: PASS` | GPU telemetry stayed inside package thresholds during the run. |
| `Telemetry: PASS_WITH_WARNINGS` | Telemetry collection succeeded, but one or more calibrated warnings deserve attention. |
| `Power: WARN sw_power_cap` | GPU hit the software power limit; common under heavy load and not thermal failure by itself. |
| `Hardware slowdown` | NVIDIA reported hardware slowdown; treated as critical. |
| `Memory junction: unknown` | Memory temperature is unavailable from current telemetry; not a pass/fail assertion. |
| `VRAM >92%` | High occupancy warning; treat model switching/concurrency carefully. |
| `VRAM >97%` | High-risk memory pressure for OOM/fragmentation/model switching. |
| `PCIe Gen3 x8` | Warning for load/offload/concurrency; resident decode may still be valid when the model fits in VRAM. |

---

## Troubleshooting

### `ollama status` returns `unknown command "status"`

That is the upstream Ollama CLI, not this package wrapper. Install/source `bashrc/.bashrc`, or call the helper directly:

```bash
./scripts/ollama-status --full
```

### Ollama API is not reachable

Start the system service:

```bash
sudo systemctl start ollama
systemctl status ollama --no-pager
curl -fsS http://127.0.0.1:11434/api/version && echo
```

### An embedding model says it does not support generate

This means the selected model is embedding-only. It is not an RTX 3090 failure and not an Ollama service failure.

Use:

```bash
ollama bench bge-m3:latest
ollama embed-test bge-m3:latest
```

For generation health, use a generation-capable model:

```bash
ollama bench gemma3:1b
ollama test qwen3.6:27b
```

### Model pattern is not found or ambiguous

List local models and use one of the suggested commands:

```bash
ollama models
ollama bench qwen3.6:27b
```

### The model fails to load with HTTP 500

The test runner preserves the response body and classifies likely load failures. Inspect:

```text
test/run-*-test/failure-hints.txt
test/run-*-test/raw/*.json
test/run-*-test/raw/*.stderr
test/run-*-test/ollama-server-log-tail.txt
```

Typical next actions:

```bash
ollama show MODEL
ollama rm MODEL
ollama pull MODEL
```

For custom GGUF imports, recreate the model from the Modelfile.

---

## Downloader

The downloader supports one source argument. Keep `--method aria2` only when you explicitly want aria2:

```bash
./scripts/ollama-download.sh --method aria2 \
  'unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf'
```

Equivalent Hugging Face URL form:

```bash
./scripts/ollama-download.sh --method aria2 \
  'https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf?download=true'
```

The script infers repo, file, local GGUF path, Ollama model name, Modelfile, and default `PARAMETER num_ctx 8192`. Override only when needed:

```bash
./scripts/ollama-download.sh --method aria2 \
  'unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf' \
  --name qwen3.6:35b \
  --num-ctx 8192
```

---

## Version highlights

| Version | Main change |
|---|---|
| v1.7 | Role-aware `ollama bench`, strict `UNSUPPORTED` generation refusal for embedding models, first-class `/api/embed` batch/long/RAG rows, streaming TTFT, `FirstReqLoad` semantics, load-state evidence, dynamic metadata extraction, sample validity states, calibrated hardware warnings, ADOS evidence ledger, and cleanup of legacy/generated files. |
| v1.6 | Capability-aware `/api/show` preflight, embedding `/api/embed` benchmark mode, `ollama embed-test`, role-aware model commands, slim model metadata by default, `Telemetry` vs `Inference` summaries, LongCtx N/A after API rejection, dmesg new-vs-historical split. |
| v1.5 | Atomic requirements audit, Bash 5.2+ target, shared helper cleanup, clear option-value validation, optional `timeout` fallback, plain final summaries after timestamped collector progress. |
| v1.4 | Production README, safe default baseline, `--stress` shorthand, model command UX cleanup. |
| v1.3 | Timestamped operational logs, fixed false API-error classification, NVIDIA start/end snapshots, `scripts/` + `changelog/` layout. |
| v1.2 | Sudo-aware systemd start/stop helpers, improved `.bashrc`, simplified one-argument downloader. |
| v1.1 | Short no-arg screen, status-gated tests, compact missing-model behavior. |
| v1.0 | Short model-pattern command and automatic local model resolution. |
| v0.9 | Model-load failure triage and richer WSL/Ollama/server evidence capture. |

Full notes are in `changelog/`.

---

## Design principles

1. **Do not hide raw evidence.** Summaries are generated from saved raw responses, CSVs, and logs.
2. **Do not run destructive/stress probes by default.** Concurrency, soak, CPU comparison, and VRAM pressure are explicit.
3. **Prefer systemd for Ollama lifecycle.** Shell variables are client-side only; service variables belong in systemd overrides.
4. **Make failure modes actionable.** Missing model, ambiguous model, API down, unsupported role, and model-load errors each produce targeted next commands.
5. **Keep benchmark intent explicit.** Use `ollama bench` for auto-routing, `ollama test` for strict generation, and `ollama embed-test` for strict embedding.

## v1.7.1 maintenance note

v1.7.1 tightens evidence semantics after reviewing real qwen3.6:27b and qwen3.6:35b result archives. Observed-mode `FirstReqLoad` no longer claims verified-cold execution by default; model-switch runs are classified explicitly; and mixed CPU/GPU Ollama residency is reported as an offload warning rather than a clean full-GPU benchmark. Orchestrator throughput wording now uses `single-request` unless full-GPU residency is actually observed.
