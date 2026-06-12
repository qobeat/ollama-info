# ollama-info

`ollama-info` is a local Ollama, WSL2/Linux, and RTX 3090 diagnostic toolkit for model selection and performance-setting selection.

It is designed for local development workflows where the wrong model or the wrong Ollama service configuration can waste minutes per prompt, silently push a model into CPU/GPU offload, or produce misleading benchmark results.

## GOAL

```text
Identify the best local Ollama model and the best safe Ollama configuration for the current host, GPU, model set, and target workload.
```

The tool must answer four practical questions:

1. Which tested model is the best coding model for OpenCode, Cursor, and code-heavy repair/apply loops?
2. Which tested model is the best chat / Hermes / ADOS runtime model?
3. Which models are only good when kept resident, and which are safe for frequent load/switch workflows?
4. Which WSL2/Linux Ollama service settings are confirmed, partially supported, or unconfirmed for each selected model?

## Objectives

| Objective | Success condition |
|---|---|
| Measure model performance | The result includes valid generation or embedding rows, TTFT, visible-answer speed, load duration, VRAM pressure, and residency classification. |
| Evaluate ADOS capability | Coding, essay, and internet-boundary prompts produce visible evidence and capability verdicts. |
| Compare models safely | Aggregate recommendations are emitted only from decision-grade rows. Failed rows do not produce winners. |
| Tune configuration | The output includes `recommended-ollama-env.conf`, `performance-settings.sh`, and `performance-settings.md` with confidence level and rationale. |
| Protect against misleading results | API/tool failures, unsupported roles, thinking-only output, CPU/GPU offload, and unvalidated context settings are surfaced as blocking or review states. |
| Preserve evidence | Every run produces compact reviewable artifacts: scorecard, recommendations, settings, environment facts, runner facts, raw payloads/metrics as configured by evidence level. |

## Installation

```bash
cd ~/dev
unzip ollama-info.zip
export OLLAMA_INFO_HOME="$HOME/dev/ollama-info"
source "$OLLAMA_INFO_HOME/bashrc/.bashrc"
```

The canonical entrypoint is:

```bash
$OLLAMA_INFO_HOME/scripts/ollama.sh
```

You may alias it as `ollama` only when you intentionally want unknown commands to pass through to the native Ollama CLI.

## Result validity model

The tool separates **measurement artifacts** from **decision claims**.

A run is **decision-grade** only when it has enough successful evidence for the requested decision. For example, a coding-model recommendation requires at least one valid visible coding row. A context recommendation above the baseline requires a passing context-pressure row. If all generation rows fail, the run is a tool/model/API failure, not a model-selection result.

Important states:

| State | Meaning |
|---|---|
| `PASS` | Required rows succeeded and can support recommendations. |
| `PASS_WITH_WARNINGS` | Core rows passed, but hardware/output/context warnings exist. |
| `PASS_WITH_REVIEW` | Rows ran, but visible-output or validator issues require review. |
| `PASS_WITH_SKIPS` | Required decision may be valid, but some optional/unsafe rows were skipped. |
| `TOOL_FAILURE` | Required rows failed because the request, API, runtime, or tool path failed. No winner is emitted. |
| `UNSUPPORTED` | The selected command is not valid for the model role, for example generation test against an embedding-only model. |
| `NO_ROWS` | No usable rows were produced. |

Decision labels:

| Label | Meaning |
|---|---|
| `FULL_GPU_RESIDENT` | The model appears fully GPU-resident in `ollama ps`. |
| `CPU_GPU_OFFLOAD_RISK` | The model is split between CPU and GPU; throughput is not a clean RTX 3090 resident result. |
| `GOOD_WARM_BAD_COLD` | Warm latency is good but first-load latency is high; use preload/keep-alive. |
| `RESIDENT_ONLY_RECOMMENDED` | Use this model after preloading; avoid frequent unload/reload workflows. |
| `VRAM_CRITICAL_HEADROOM` | VRAM pressure exceeds the critical threshold; do not raise context or parallelism by default. |
| `CONTEXT_INCREASE_NOT_RECOMMENDED` | Higher context was unsafe, untested, or blocked by VRAM/offload evidence. |
| `THINKING_ONLY_OUTPUT_RISK` | The model produced thinking text without visible answer text for a capability row. |
| `NO_VALID_GENERATION_ROWS` | No successful visible generation rows exist. |
| `NO_MODEL_RANKING` | The run cannot support best-model claims. |

## Commands

### `ollama.sh status`

Shows Ollama service state, API version, and RTX GPU snapshot.

Use it before testing to confirm:

```text
api: RUNNING
GPU visible through nvidia-smi
idle VRAM is not unexpectedly high
```

Interpretation:

- `api: RUNNING` means the local Ollama HTTP API responded.
- `gpu: NVIDIA ...` means the Linux/WSL2 environment can see the GPU.
- High idle VRAM means a model or another process may already be resident.

### `ollama.sh models`

Lists local models, inferred role, approximate size, and suggested commands.

Interpretation:

- `generate` models can be tested with `ollama.sh test`.
- `embedding` models should use `ollama.sh embed-test` or `ollama.sh bench`.
- Ambiguous patterns resolve by exact match first, then base tag, then unique substring.

### `ollama.sh test MODEL`

Runs the default fast resident-warm generation comparison for one model.

Default lane:

| Lane | Purpose |
|---|---|
| `resident-warm` | Preloads the model with `keep_alive` and runs ADOS capability prompts. |
| `settings` | Emits applyable Ollama service settings with confidence/rationale. |
| `environment` | Logs Ollama version, service environment, WSL/kernel facts, GPU facts, and model metadata. |

Use this for routine model comparison after you know the host is healthy. It avoids paying empty-card first-load cost for every routine run. Use `ollama.sh diagnose MODEL` or `--mode diagnostic` when you need first-load and context-pressure proof.

Main artifacts:

```text
summary.md
terminal-summary.txt
model-scorecard.csv
recommendations.md
recommended-ollama-env.conf
performance-settings.sh
performance-settings.md
environment-summary.md
runner-log-facts.md
capability-analysis.md
```

Important fields:

| Field | Meaning |
|---|---|
| `FirstTTFT` | Time to first stream chunk on the first request. |
| `FirstReqLoad` | Ollama load duration reported on the first request. This is not a pure disk-read benchmark. |
| `WarmTTFT` | First-answer latency for resident-warm rows. This is the key daily-use metric. |
| `Visible answer speed` | Tokens/sec for visible answer output. Thinking-only output is not counted as visible speed. |
| `Valid generation rows` | Number of successful visible-output rows. Zero means no model ranking. |
| `Valid capability rows` | Number of successful ADOS capability rows. Used for use-case recommendations. |
| `Valid context rows` | Number of successful context-pressure rows. Required before larger context is called confirmed. |
| `RootErr` | First captured API/tool error. This is the first place to look when rows fail. |
| `Settings confidence` | `HIGH_CONFIRMED`, `MEDIUM_PARTIAL`, or `LOW_UNCONFIRMED`. |

### `ollama.sh test MODEL --quick`

Runs the shortest generation/capability check. This is equivalent to a compact resident-warm ADOS probe.

Use it for smoke checks. Do not use a quick run alone to confirm larger context settings.

### `ollama.sh diagnose MODEL`

Runs the full diagnostic suite:

```text
empty-card first-load
resident-warm ADOS prompts
context-pressure settings validation
settings recommendation
environment/runner evidence
```

Use this when selecting final settings for a model, investigating cold-load time, or deciding whether 8K/16K context is safe.

### `ollama.sh test MODEL --mode empty-card`

Runs only the first-load lane.

Use it to answer:

```text
How expensive is the first prompt after unload/restart/model switch?
```

A model can be bad in this mode but still good as a resident model.

### `ollama.sh test MODEL --mode resident-warm`

Runs the daily-use lane after preloading the model.

Use it for OpenCode, Cursor, Hermes, and ADOS workflows where a model is intentionally kept loaded.

Best interpretation:

```text
WarmTTFT < 1s is usually interactive.
Visible tok/s determines output comfort.
Visible output and capability verdicts matter more than raw eval speed.
```

### `ollama.sh test MODEL --mode context-pressure`

Runs only context-pressure steps.

Use it before raising:

```text
OLLAMA_CONTEXT_LENGTH
num_ctx
```

Default context steps are:

```text
4096,8192,16384
```

The tool skips higher steps when current VRAM is already critical unless you pass:

```bash
--force-context-pressure
```

A larger context setting is confirmed only when a matching context-pressure row passes the minimum-output gate. A row that returns HTTP 200 but generates only one or a few tokens is classified as `SHORT_CONTEXT_SAMPLE` / `CONTEXT_PRESSURE_INCONCLUSIVE`; it proves request acceptance only and does not validate speed or settings.

Default minimum-output gate:

```text
eval_tokens >= 128
response_chars >= 200
```

### `ollama.sh test MODEL_A MODEL_B ...`

Runs multi-model resident-warm generation comparison and produces one aggregate ZIP. Use `ollama.sh diagnose MODEL_A MODEL_B ...` for the slower full diagnostic comparison with empty-card and context-pressure lanes.

Aggregate artifacts:

```text
multi-model-index.csv
multi-model-summary.md
model-scorecard.csv
recommendations.md
performance-settings-all.md
runs/run-*/...
```

Aggregate recommendations are emitted only from rows where `ranking_allowed=1`. If all candidates fail, `recommendations.md` explicitly says no winner was emitted.

### `ollama.sh bench MODEL_A MODEL_B ...`

Role-aware benchmark command.

Routing:

```text
generation model -> generation diagnostic
embedding model  -> embedding/RAG benchmark through /api/embed
mixed list       -> one aggregate benchmark ZIP
```

Use this when the model list may contain both generation and embedding models.

### `ollama.sh embed-test MODEL`

Runs embedding/RAG tests through Ollama `/api/embed`.

Rows:

```text
short sanity input
batch chunks
RAG-like document chunks
```

Interpretation:

| Field | Meaning |
|---|---|
| `vector_dim` | Embedding width. |
| `vector_count` | Number of vectors returned. |
| `embeddings_per_s` | Request-level embedding throughput. |
| `embed_tokens_per_s` | Approximate indexing throughput. |

Do not compare embedding models with generation models by tokens/sec. They answer different workload questions.

### `ollama.sh preload MODEL --ctx 4096 --keep-alive 24h`

Preloads a model and asks Ollama to keep it resident.

Use this when a diagnostic reports:

```text
GOOD_WARM_BAD_COLD
RESIDENT_ONLY_RECOMMENDED
```

After preloading, verify:

```bash
ollama ps
```

Expected evidence:

```text
model present
100% GPU when full residency is expected
keep-alive expiry in the future
```

### `ollama.sh compare MODEL_A MODEL_B ...`

Alias for multi-model generation comparison. It is intended for decision-grade model selection.

### `ollama.sh gpu`

Shows raw `nvidia-smi` output.

Use it when investigating thermal, power, PCIe, or VRAM behavior.

### `ollama.sh logs [N]`

Shows recent Ollama systemd logs.

Use this when the summary reports:

```text
slow runner startup
missing or unconfirmed KV cache type
CPU/GPU offload
API root error
invalid request payload
```

## Test configuration options

| Option | Meaning | When to use |
|---|---|---|
| `--num-ctx N` | Baseline context for generation rows. | Start at `4096` for large models on 24 GB VRAM. |
| `--num-predict N` | Output budget for ADOS capability rows. | Increase when coding/essay rows truncate. |
| `--context-steps CSV` | Context-pressure sequence. | Use `4096,8192` for conservative tests; add `16384` only with enough VRAM. |
| `--keep-alive V` | Ollama keep-alive for resident-warm testing. | Use `24h` for heavy resident models. |
| `--think false|true|low|medium|high|max|none` | Controls Ollama thinking parameter. | Default is JSON boolean `false`; `none` omits the field. |
| `--temperature X` | Generation temperature. | Keep low for repeatable diagnostics. |
| `--evidence-level compact|standard|full` | Controls runtime artifact volume. | Use `standard` for review; `compact` for routine tests; `full` for debugging. |
| `--strict-exit` | Nonzero exit for review/fail states. | Use in CI or scripted regression checks. |
| `--route-only` | Resolve route without executing. | Use to verify role and command routing. |

### Thinking parameter nuance

The `think` field must be valid JSON. Boolean false must be sent as:

```json
"think": false
```

not as:

```json
"think": "false"
```

The diagnostic payloads preserve this distinction. Use `--think none` to omit the field entirely.

## Performance setting output

Each generation run emits:

```text
recommended-ollama-env.conf
performance-settings.sh
performance-settings.md
```

`recommended-ollama-env.conf` is the systemd drop-in body. `performance-settings.sh` applies that drop-in. `performance-settings.md` explains why the settings were chosen and whether the recommendation is confirmed.

Typical safe RTX 3090 baseline:

```ini
[Service]
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_CONTEXT_LENGTH=4096"
# Optional after explicit validation: Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

Settings confidence:

| Confidence | Meaning |
|---|---|
| `HIGH_CONFIRMED` | Required generation and context-pressure rows passed the minimum-output gates. |
| `MEDIUM_PARTIAL` | Main generation evidence passed, but not all tuning dimensions are confirmed. |
| `LOW_UNCONFIRMED` | A safe baseline was emitted, but no best-parameter claim is made. |

Do not apply a setting as “best” just because a file exists. Check `settings_confidence`, `context_validated`, root errors, and classifications first.

## Recommended workflow

### One model

```bash
ollama.sh test qwen2.5-coder:7b
```

For full settings confirmation, run:

```bash
ollama.sh diagnose qwen2.5-coder:7b
```

Review:

```text
terminal-summary.txt
summary.md
model-scorecard.csv
recommendations.md
performance-settings.md
recommended-ollama-env.conf
```

Apply settings only when:

```text
status is PASS / PASS_WITH_WARNINGS / PASS_WITH_SKIPS
ranking_allowed=1 for model-selection decisions
settings_confidence is MEDIUM_PARTIAL or HIGH_CONFIRMED
root_error is empty
```

### Multiple models

```bash
ollama.sh test qwen2.5-coder:7b qwen3:8b qwen3.6:27b-q4_K_M
```

Review aggregate:

```text
model-scorecard.csv
recommendations.md
performance-settings-all.md
```

A winner is valid only if the aggregate recommendation was generated from decision-grade rows. Context-pressure rows are excluded from visible speed averages, so one-token long-context rows cannot inflate rankings.

### Embedding/RAG candidates

```bash
ollama.sh bench bge-m3:latest qwen3-embedding:4b
```

Use embedding results for RAG/indexing decisions, not for coding/chat generation decisions.

## Output ZIP naming

Single generation model:

```text
ollama-test-and-monitor-RTX3090-qwen2.5-coder_7b-YYYYMMDD-HHMMSS.zip
```

Multi-model generation:

```text
ollama-test-and-monitor-RTX3090-3models-YYYYMMDD-HHMMSS-multi.zip
```

Embedding:

```text
ollama-embed-test-RTX3090-bge-m3_latest-YYYYMMDD-HHMMSS.zip
```

## Evidence levels

| Level | Behavior |
|---|---|
| `compact` | Keeps decision artifacts and removes low-value raw stream files. |
| `standard` | Keeps summaries, scorecards, settings, environment facts, runner facts, CSVs, payloads, and useful raw metrics. |
| `full` | Keeps all raw stream artifacts and debugging sidecars. |

## Troubleshooting

| Symptom | Likely meaning | Action |
|---|---|---|
| `TOOL_FAILURE` and all rows HTTP 400 | Request/API payload problem or unsupported parameter. | Read `RootErr`, inspect `payloads/*.json`, rerun after repair. |
| `NO_MODEL_RANKING` | No valid generation evidence. | Do not use recommendations; repair first. |
| `Visible: N/A` | No visible answer speed was measured. | Check thinking-only rows, API errors, and raw outputs. |
| `CONTEXT_INCREASE_NOT_RECOMMENDED` | VRAM/offload/context evidence blocks context increase. | Keep baseline context or use smaller model. |
| `CONTEXT_PRESSURE_INCONCLUSIVE` | Context row returned too little output to validate speed/settings. | Do not treat 8K/16K as confirmed; rerun diagnose with better prompt or larger budget if needed. |
| `CPU_GPU_OFFLOAD_RISK` | Model does not fully fit as tested. | Reduce context, reduce parallelism, or use smaller/quantized model. |
| `Settings confidence: LOW_UNCONFIRMED` | Config file is a safe baseline only. | Do not treat it as best parameters. |

## Package evidence

The package includes ADOS-style QA evidence surfaces:

```text
MANIFEST.md
PACKAGE.json
SOURCE-OF-TRUTH.json
schema.json
qa-evidence/evidence-ledger.jsonl
qa-evidence/self-evaluation.md
qa-evidence/verification-output.txt
qa-evidence/QUALITY-EVIDENCE-SUMMARY.md
```

These files exist to keep goal, objectives, validation, repair decisions, and package finalization reviewable.
