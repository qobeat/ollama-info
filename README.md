# ollama-info

`ollama-info` is a local Ollama evaluation and configuration tool for an RTX 3090 workstation. It measures local model behavior, qualifies model suitability for coding/chat/Hermes/ADOS workflows, and emits reviewable WSL2/Linux Ollama settings that can be applied through a systemd drop-in.

The tool is designed for a single-developer workstation where practical latency, model residency, context window, GPU memory pressure, and repeatable evidence matter more than a single raw tokens-per-second number.

## GOAL

Identify the best local Ollama model and the safest performance configuration for each target use case on the current RTX 3090 / WSL2 / Ollama environment.

The goal surface has five mandatory facets:

| Facet | Required result |
|---|---|
| Performance measurement | Warm TTFT, visible tokens/sec, preload/model-ready cost, VRAM use, residency, and error state are captured per model. |
| Use-case selection | Results are reported separately for coding, chat, Hermes, ADOS, ADOS code-repair, heavy reasoning, and vision. |
| Context validation | A model is not considered Hermes main-chat compatible unless it passes the requested context gate, normally `--min-context 65536`. |
| Settings output | The run emits `recommended-ollama-env.conf` and `performance-settings.sh` with confidence labels. |
| Evidence discipline | Every recommendation is backed by CSV/Markdown evidence and downgraded when evidence is partial, contaminated, or missing. |

## Objectives

| Objective | Implementation surface | Success condition |
|---|---|---|
| Measure daily model usability | `ollama test MODEL` | Runs resident-warm ADOS probes and reports warm TTFT/TPS. |
| Measure full model readiness | `ollama test --full MODEL` | Runs empty-card, resident-warm, and context-pressure lanes. |
| Validate Hermes context | `ollama test --full --min-context 65536 MODEL` or `ollama context-test MODEL --min-context 65536` | Reports `Hermes65K=PASS` only when the context row passes fill/output gates. |
| Avoid false context positives | `context-summary.csv`, `hermes-compatibility.md` | HTTP 200 with one/few tokens becomes `CONTEXT_ACCEPTED_SHORT_OUTPUT`, not a pass. |
| Produce clear summaries | `terminal-summary.txt`, `summary.md`, aggregate summary | Output uses tables for execution state, performance, capability rows, context, settings, and use-case recommendations. |
| Produce applyable settings | `recommended-ollama-env.conf`, `performance-settings.sh` | Settings include confidence and conservative defaults when context is not confirmed. |
| Support future enhancement | `requirements.md`, `schema.json`, `qa-evidence/` | Project surfaces remain compact, traceable, and evidence-backed. |

## Installation

Copy the repository folder somewhere on your WSL2/Linux host, then source or install the wrapper from `bashrc/.bashrc` so that `ollama` subcommands delegate to `scripts/ollama.sh` when appropriate.

Typical direct usage from the project root:

```bash
scripts/ollama.sh status
scripts/ollama.sh test qwen3:8b
```

## Command reference

### `ollama status`

Shows Ollama service status, API version, and RTX 3090 state.

Use when checking whether Ollama and the GPU are ready before testing.

### `ollama models`

Lists local models, inferred role, size, and suggested command.

Use when deciding which local tag to benchmark. Embedding models should be tested with `embed-test` or `bench`, not plain generation tests.

### `ollama test MODEL [MODEL...]`

Runs the default daily benchmark: resident-warm ADOS probes at the baseline context, normally `4096`.

It measures:

| Metric | Meaning |
|---|---|
| Preload wait | Time spent making the model resident before measured prompts. |
| Warm TTFT | Time to first answer token when the model is resident. |
| Visible tok/s | Answer throughput from resident-warm capability rows only. |
| VRAM | GPU memory pressure during or after the run. |
| Capability rows | Coding, essay, and internet-access boundary probes. |

Use this for fast daily comparisons and for deciding which model feels responsive for OpenCode, Cursor, Hermes fallback chat, or ADOS at ordinary context sizes.

`ollama test` does **not** confirm Hermes 65K context compatibility. It will report context as not tested.

Example:

```bash
ollama test llama3.1:8b qwen2.5vl:7b qwen3:8b
```

### `ollama test --full MODEL [MODEL...]`

Runs all lanes:

| Lane | Purpose |
|---|---|
| Empty-card | Measures first-load/model-switch behavior. |
| Resident-warm | Measures daily practical performance. |
| Context-pressure | Tests larger context windows up to the configured minimum context. |

By default, `--full` builds a context ladder up to `65536`, unless `--min-context` or `--context-steps` changes it.

Use this when confirming settings or checking whether a model can serve as a main Hermes chat model.

Example:

```bash
ollama test --full --min-context 65536 qwen3:8b llama3.1:8b
```

### `ollama context-test MODEL [MODEL...] --min-context 65536`

Runs context-pressure validation only. This is the shortest command for checking large-context suitability.

A context row passes only when all required gates pass:

| Gate | Default requirement |
|---|---:|
| HTTP status | `200` |
| Prompt fill | at least `65%` of requested context |
| Eval tokens | at least `128` |
| Response chars | at least `500` |
| Root error | none |

If the model accepts the request but emits only one/few tokens, the row is classified as `CONTEXT_ACCEPTED_SHORT_OUTPUT`. That is not a pass and cannot confirm settings.

For Hermes main chat, run:

```bash
ollama context-test qwen3:8b qwen2.5vl:7b llama3.1:8b --min-context 65536
```

### `ollama diagnose MODEL [MODEL...]`

Alias for a full diagnostic. It prepends `--full` and is intended for deeper validation, not daily quick comparisons.

Example:

```bash
ollama diagnose qwen2.5-coder:14b --min-context 65536
```

### `ollama compare MODEL [MODEL...]`

Alias for multi-model generation comparison. It uses the same options as `test`.

Example:

```bash
ollama compare qwen3:8b qwen2.5-coder:14b llama3.1:8b
```

### `ollama bench MODEL [MODEL...]`

Role-aware benchmark route:

| Model role | Route |
|---|---|
| generation | generation benchmark/test |
| embedding | `/api/embed` benchmark |

Use this when the model list may mix generation and embedding models.

### `ollama embed-test MODEL [MODEL...]`

Runs embedding/RAG checks through `/api/embed`. It reports vector count, vector dimension, embedding throughput, and batch behavior.

Use for `bge-m3`, `qwen3-embedding`, and other embedding-only models.

### `ollama preload MODEL --ctx N --keep-alive 24h`

Preloads a model and verifies residency with `ollama ps`.

Use before OpenCode, Cursor, Hermes, or ADOS sessions when a model has good warm performance but high preload/model-switch cost.

Example:

```bash
ollama preload qwen3.6:27b-q4_K_M --ctx 4096 --keep-alive 24h
```

## Output files

Each single-model run emits a folder and, unless disabled, a ZIP. The most important files are:

| File | Purpose |
|---|---|
| `terminal-summary.txt` | Table-first summary shown in the console. |
| `summary.md` | Full human-readable per-model report. |
| `model-scorecard.csv` | Machine-readable decision and metric row. |
| `context-summary.csv` | Machine-readable context-window evidence. |
| `context-summary.md` | Human-readable context evidence and verdicts. |
| `hermes-compatibility.md` | Explicit Hermes 65K result. |
| `recommendations.md` | Per-model use-case recommendation. |
| `recommended-ollama-env.conf` | Systemd drop-in body. |
| `performance-settings.sh` | Script to apply recommended settings. |
| `environment-summary.md` | Ollama, service, WSL2, and GPU environment facts. |
| `runner-log-facts.md` | Extracted runner/server facts from Ollama logs. |

Multi-model runs additionally emit:

| File | Purpose |
|---|---|
| `aggregate-terminal-summary.md` | Final aggregate table summary. |
| `model-scorecard.csv` | Merged scorecard for all models. |
| `recommendations.md` | Use-case winners and next tests. |
| `performance-settings-all.md` | Settings rationale for all tested models. |

## Interpreting settings confidence

| Confidence | Meaning |
|---|---|
| `LOW_UNCONFIRMED` | The run did not produce enough valid evidence. Do not treat settings as tuned. |
| `MEDIUM_WARM_ONLY` | Resident-warm performance passed, but larger context was not validated. |
| `MEDIUM_CONTEXT_PARTIAL` | Some context evidence passed, but not the requested full context gate. |
| `HIGH_CONTEXT_CONFIRMED` | Generation and requested context gates passed. |

Hermes main chat requires `HIGH_CONTEXT_CONFIRMED` or at least `Hermes65K=PASS` for the chosen model.

## Use-case logic

The aggregate recommendations separate use cases instead of selecting one generic winner.

| Use case | Selection considerations |
|---|---|
| OpenCode / Cursor coding | coding probe, coder-family bonus, warm TTFT, speed, VRAM. |
| Chat default | warm TTFT, visible output speed, lower VRAM, no slow-thinking penalty. |
| Hermes main chat | requires `Hermes65K=PASS`. |
| Hermes fallback 4K | can use resident-warm performance when 65K is not yet validated. |
| ADOS default | balanced runtime, visible output, internet-boundary behavior, speed. |
| ADOS coding repair | coding-specialized model and coding row evidence. |
| Vision default | requires vision-specific rows; text-only qwen2.5vl tests do not prove vision quality. |
| Heavy reasoning | larger model lane, usually resident-only. |

## Context-window rules

Context validation is deliberately strict. A large context row is not accepted merely because Ollama returns HTTP 200.

A passing context row must ingest enough prompt tokens, generate enough output tokens, produce enough visible text, and avoid root API errors. If a row emits only one token, it is marked short/inconclusive.

This prevents false positives where a model appears to support 65K context but does not actually produce a meaningful answer at that context.

## Recommended safe baseline

Until a specific model receives context-confirmed settings, use:

```ini
[Service]
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_CONTEXT_LENGTH=4096"
# Optional after explicit validation: Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

Apply only after reviewing `performance-settings.md` and the generated confidence label.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `HTTP 400 invalid think value` | Old package or bad request serialization | Upgrade package and rerun. |
| `Visible tok/s` is missing | No visible answer or thinking-only output | Inspect raw output and capability-analysis. |
| `Hermes65K=NOT_TESTED` | The run was resident-warm only | Run `ollama test --full --min-context 65536 MODEL`. |
| `CONTEXT_ACCEPTED_SHORT_OUTPUT` | Model accepted context but did not produce enough output | Treat as inconclusive; do not confirm settings. |
| Very long preload wait | Model switch/cold load or storage/runtime cost | Use `ollama preload` and keep the model resident. |
| High VRAM before run | Other models/apps are resident | Stop Hermes/OpenCode/manual chat and rerun. |

## Development and extension notes

The package is organized around small shell/Python scripts:

| Script | Role |
|---|---|
| `scripts/ollama.sh` | command router and multi-model aggregation |
| `scripts/ollama-test-RTX3090.sh` | generation/context test engine |
| `scripts/ollama-test-and-monitor-RTX3090.sh` | hardware-snapshot wrapper |
| `scripts/ollama-run-generate.py` | streaming `/api/generate` metrics collector |
| `scripts/ollama-summarize-results.py` | scorecards, summaries, settings, recommendations |
| `scripts/ollama-embed-test-RTX3090.sh` | `/api/embed` benchmark |
| `scripts/ollama-common.sh` | shared helpers |

Add new test lanes by extending `ollama-test-RTX3090.sh`, then update `ollama-summarize-results.py` so the new evidence appears in scorecards and recommendation gates.
