# ollama-info

`ollama-info` is a local Ollama evaluation and configuration toolkit for an RTX 3090 workstation on WSL2/Linux. It measures model latency, throughput, residency, VRAM pressure, context-window behavior, and role suitability for coding, chat, Hermes, ADOS, embedding/RAG, and explicit image/vision workflows.

The package is intentionally evidence-first: every recommendation is backed by generated CSV, Markdown, raw response, and settings artifacts. It does not treat model metadata as sufficient proof of runtime context compatibility.

## Version

Current package version: **v1.13.0**.

v1.13 fixes the v1.12 production blockers:

| Area | v1.13 behavior |
|---|---|
| Bash integration | `ollama test ...` works through a safe wrapper; native commands such as `ollama list` pass through. |
| Vision workflow | `ollama vision-test MODEL --image PATH` is implemented; vision is not inferred from text-only tests. |
| Exit codes | Single-model runs read status from `model-scorecard.csv`, not legacy Markdown. |
| Streamed text | Joined `answer.txt` and `thinking.txt` artifacts are written for capability checks. |
| Capability gates | Coding, essay, and internet/current-facts boundary gates are tracked separately. |
| Hermes context | Skipped context rows are not reported as runtime-tested. |
| Aggregate ranking | Balanced, TTFT, TPS, and context-only summaries are separated. |

## Goal

Identify the best local Ollama model and the safest performance configuration for each target use case on the current RTX 3090 / WSL2 / Ollama environment.

| Facet | Required result |
|---|---|
| Performance measurement | Warm TTFT, visible tokens/sec, preload/model-ready cost, VRAM use, residency, and error state are captured per model. |
| Use-case selection | Results are reported separately for coding, chat, Hermes, ADOS, ADOS code repair, heavy reasoning, embedding/RAG, and explicit vision. |
| Context validation | A model is not considered Hermes main-chat compatible unless a real runtime row passes the requested context gate, normally `--min-context 65536`. |
| Settings output | The run emits `recommended-ollama-env.conf` and `performance-settings.sh` with confidence labels. |
| Evidence discipline | Recommendations are downgraded when capability, context, or runtime evidence is partial, skipped, contaminated, or missing. |

## Installation

Copy the repository folder somewhere on your WSL2/Linux host. Recommended location:

```bash
mkdir -p ~/dev
cp -R ollama-info ~/dev/ollama-info
cd ~/dev/ollama-info
```

Install the Bash wrapper without replacing your current `.bashrc`:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cat bashrc/.bashrc >> ~/.bashrc
source ~/.bashrc
hash -r
```

Direct usage from the project root also works without shell integration:

```bash
scripts/ollama.sh status
scripts/ollama.sh test qwen3:8b
```

## Bash wrapper behavior

The wrapper intercepts only `ollama-info` subcommands:

```bash
ollama status
ollama models
ollama test qwen3:8b
ollama test --full qwen3:8b --min-context 65536
ollama context-test qwen3:8b --min-context 65536
ollama vision-test qwen2.5vl:7b --image /path/to/test-image.png
ollama embed-test bge-m3
ollama bench qwen3:8b bge-m3
ollama preload qwen3:8b --ctx 4096 --keep-alive 24h
```

Native Ollama commands pass through unchanged:

```bash
ollama list
ollama ps
ollama pull llama3.1:8b
ollama run llama3.1:8b
```

Disable the wrapper if needed:

```bash
export OLLAMA_INFO_WRAP_CLI=0
```

## Command reference

### `ollama status`

Shows Ollama service status, API version, and RTX 3090 state.

Use before tests to confirm the API and GPU are visible.

### `ollama models`

Lists local models, inferred role, size, and suggested test command.

Embedding models should be tested with `embed-test` or `bench`, not plain generation tests.

### `ollama test MODEL [MODEL...]`

Runs the default daily generation benchmark: resident-warm ADOS capability probes at the baseline context, normally `4096`.

It measures:

| Metric | Meaning |
|---|---|
| Preload wait | Time spent making the model resident before measured prompts. |
| Warm TTFT | Time to first visible answer token when the model is resident. |
| Visible tok/s | Answer throughput from visible response text, excluding thinking-only output. |
| VRAM | GPU memory pressure after the run. |
| Capability gates | Coding, essay, and internet/current-facts boundary checks. |

`ollama test` does **not** confirm Hermes 65K context compatibility. It reports the required context as `NOT_TESTED` unless context-pressure rows are run.

Example:

```bash
ollama test llama3.1:8b qwen2.5vl:7b qwen3:8b
```

### `ollama test --full MODEL [MODEL...]`

Runs all generation lanes:

| Lane | Purpose |
|---|---|
| Empty-card | Measures first-load/model-switch behavior after unloading resident models. |
| Resident-warm | Measures daily practical performance and capability gates. |
| Context-pressure | Tests larger context windows up to the configured minimum context. |

By default, `--full` builds a context ladder up to `65536`, unless `--min-context` or `--context-steps` changes it.

Example:

```bash
ollama test --full --min-context 65536 qwen3:8b llama3.1:8b
```

### `ollama context-test MODEL [MODEL...] --min-context 65536`

Runs context-pressure validation only. This is the shortest command for checking large-context suitability.

A context row passes only when all gates pass:

| Gate | Default requirement |
|---|---:|
| HTTP status | `200` |
| Prompt fill | at least `65%` of requested context |
| Eval tokens | at least `128` |
| Response chars | at least `500` |
| Root error | none |

Skipped rows are labeled `CONTEXT_NOT_RUN_SKIPPED` and do not count as runtime-tested. A one-token or very short answer is labeled `CONTEXT_ACCEPTED_SHORT_OUTPUT`; it is not a pass.

Example:

```bash
ollama context-test qwen3:8b qwen2.5vl:7b llama3.1:8b --min-context 65536
```

### `ollama vision-test MODEL --image PATH`

Runs an explicit image/vision test through `/api/generate` with the Ollama `images` payload field.

Vision is **not** part of text-only `ollama test` runs. You must provide a local image path.

Example:

```bash
ollama vision-test qwen2.5vl:7b --image ./test-image.png
```

Output includes `summary.md`, `summary.csv`, `raw/vision.answer.txt`, `raw/vision.ndjson`, and a ZIP unless `--no-zip` is used.

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
| generation | generation test through `/api/generate` |
| embedding | embedding test through `/api/embed` |

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

Each single-model generation run emits a folder and, unless disabled, a ZIP. The important files are:

| File | Purpose |
|---|---|
| `terminal-summary.txt` | Table-first summary shown in the console. |
| `summary.md` | Full human-readable per-model report. |
| `model-scorecard.csv` | Machine-readable decision, gates, and metric row. |
| `context-summary.csv` | Machine-readable context-window evidence. |
| `context-summary.md` | Human-readable context evidence and verdicts. |
| `hermes-compatibility.md` | Explicit required-context/Hermes result. |
| `recommendations.md` | Per-model use-case recommendation. |
| `recommended-ollama-env.conf` | Systemd drop-in body. |
| `performance-settings.sh` | Script to apply recommended settings. |
| `performance-settings.md` | Rationale for settings confidence. |
| `environment-summary.md` | Ollama, service, WSL2, and GPU environment facts. |
| `runner-log-facts.md` | Extracted runner/server facts from Ollama logs. |
| `raw/*.answer.txt` | Joined visible answer text for each probe. |
| `raw/*.thinking.txt` | Joined thinking text, if the model emits it. |
| `raw/*.ndjson` | Timestamped raw streaming chunks. |

Multi-model generation runs additionally emit:

| File | Purpose |
|---|---|
| `aggregate-terminal-summary.txt` | Final aggregate table printed to the terminal. |
| `model-scorecard.csv` | Combined model scorecard. |
| `recommendations.md` | Aggregate use-case winners and caveats. |
| `performance-settings-all.md` | Settings rationale from each sub-run. |
| `multi-model-index.csv` | Index of sub-runs and scorecards. |
| `multi-model-summary.md` | Concatenated per-model terminal summaries. |

Vision runs emit:

| File | Purpose |
|---|---|
| `summary.md` | Human-readable vision test summary and answer preview. |
| `summary.csv` | Machine-readable vision row. |
| `raw/vision.answer.txt` | Joined answer text. |
| `raw/vision.ndjson` | Raw streaming chunks. |
| `raw/image.base64.txt` | Base64 image payload used for the request. |

## Decision and recommendation rules

### Generation decision-grade

A normal generation run is decision-grade only when:

1. the run status starts with `PASS`,
2. at least one visible non-context generation row exists, and
3. all required capability gates pass:
   - coding,
   - essay,
   - internet/current-facts boundary.

A context-only run is decision-grade only when at least one context-pressure row passes.

### Hermes/main-chat context gate

A model is not confirmed for Hermes main chat unless a real runtime row at or above `--min-context` passes. Metadata such as `context_length=131072` is useful but not sufficient.

Possible required-context results:

| Result | Meaning |
|---|---|
| `PASS` | A real row at or above required context passed prompt-fill, eval-token, and response-char gates. |
| `FAIL` | A real row at or above required context was attempted but failed. |
| `NOT_RUN_SKIPPED` | A row exists only as a skip marker; it was not runtime-tested. |
| `NOT_TESTED` | No row at or above required context exists. |

## Settings safety

Generated settings are conservative:

```ini
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_CONTEXT_LENGTH=<recommended_context>"
# Optional after explicit validation: Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

Apply only after reviewing `performance-settings.md` and the confidence label.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `Hermes required context = NOT_TESTED` | Only resident-warm test was run. | Run `ollama test --full --min-context 65536 MODEL`. |
| `CONTEXT_NOT_RUN_SKIPPED` | A lower context step failed or VRAM was critical, so higher steps were skipped. | Inspect `context-summary.csv`; rerun with `--force-context-pressure` only if safe. |
| `CONTEXT_ACCEPTED_SHORT_OUTPUT` | Model accepted the context but produced too little output. | Treat as not confirmed; reduce context or model size. |
| `internet_boundary_gate=NEEDS_REVIEW` | The current-facts boundary answer was ambiguous. | Inspect `raw/*internet*.answer.txt`. |
| `Visible tok/s` is missing | No visible answer or thinking-only output. | Inspect raw answer/thinking files. |
| `ollama vision-test` fails with missing image | No local image was provided. | Run with `--image /path/to/test-image.png`. |
| Very long preload wait | Model switch/cold load or storage/runtime cost. | Use `ollama preload` and keep the model resident. |
| High VRAM before run | Other models/apps are resident. | Stop other Ollama sessions and rerun. |

## Project files

| Path | Purpose |
|---|---|
| `scripts/ollama.sh` | Main wrapper/router. |
| `scripts/ollama-test-RTX3090.sh` | Single-model generation/context test runner. |
| `scripts/ollama-test-and-monitor-RTX3090.sh` | Single-model orchestrator with hardware snapshots. |
| `scripts/ollama-summarize-results.py` | Per-model summarizer and settings generator. |
| `scripts/ollama-aggregate-summary.py` | Multi-model aggregate summarizer. |
| `scripts/ollama-run-generate.py` | Streaming `/api/generate` runner with joined text artifacts. |
| `scripts/ollama-vision-test-RTX3090.sh` | Explicit image/vision test runner. |
| `scripts/ollama-embed-test-RTX3090.sh` | Embedding/RAG test runner. |
| `bashrc/.bashrc` | Optional Bash integration snippet. |
| `requirements.md` | Atomic requirements. |
| `qa-evidence/` | Verification and release evidence. |
