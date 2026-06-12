# ollama-info

`ollama-info` is a local Ollama and RTX 3090 diagnostic toolkit for choosing usable local models and producing applyable performance settings for a WSL2/Linux Ollama service.

The primary goal is decision support:

1. identify the best model or models for coding, agentic runtime, ADOS-style workflows, Hermes-style workflows, and RAG/embedding work;
2. identify the safest high-performance configuration settings for the selected model on the current hardware and service environment;
3. produce compact evidence that explains why a model is recommended, warned, or rejected.

## Install

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

You may alias it as `ollama` only if you intentionally want the wrapper to pass unknown commands through to the native Ollama CLI.

## Command overview

### `ollama.sh status`

Shows the Ollama service state, API version, and RTX GPU snapshot.

Use it before tests to confirm that the API is reachable and that the GPU is visible.

Interpretation:

- `api: RUNNING` means the local Ollama HTTP API responded.
- `gpu: NVIDIA GeForce RTX 3090 ...` means `nvidia-smi` is available to the Linux/WSL2 environment.
- high idle VRAM before a test means another model or process may be resident.

### `ollama.sh models`

Lists local models, inferred role, approximate size, and suggested commands.

Interpretation:

- `generate` models are valid targets for `ollama.sh test`.
- `embedding` models should be tested with `ollama.sh embed-test` or `ollama.sh bench`.
- Ambiguous model patterns are resolved by exact match first, then base tag, then unique substring.

### `ollama.sh test MODEL`

Runs the default generation diagnostic for one model. The default diagnostic includes:

1. `empty-card` first-load lane: unloads resident models when possible and measures first-request load cost.
2. `resident-warm` lane: preloads/keeps the model resident and runs ADOS capability prompts.
3. `context-pressure` lane: checks safe context growth and skips unsafe larger context when VRAM is already critical.
4. environment logging: Ollama version, service variables, WSL/kernel facts, GPU facts, model metadata.
5. output generation: `summary.md`, `terminal-summary.txt`, `model-scorecard.csv`, `recommendations.md`, `performance-settings.sh`, and `performance-settings.md`.

Use it when selecting a daily model or tuning a large model.

Important output fields:

- `FirstTTFT`: first token latency for the first request.
- `FirstReqLoad`: Ollama load duration on the first request.
- `WarmTTFT`: first-token latency after the model is already resident.
- `Visible answer speed`: output speed for visible answer text; thinking-only output is not counted.
- `VRAM used`: observed GPU memory pressure.
- `Residency`: whether the model is fully on GPU or split CPU/GPU.
- `Classifications`: decision labels such as `GOOD_WARM_BAD_COLD`, `VRAM_CRITICAL_HEADROOM`, or `RESIDENT_ONLY_RECOMMENDED`.

### `ollama.sh test MODEL --quick`

Runs a shorter capability check. Use this after a full diagnostic has already established safe settings.

### `ollama.sh test MODEL --mode resident-warm`

Tests daily practical behavior when the model is already loaded. Use this for OpenCode, Cursor, Hermes, and ADOS workflows that keep a model resident.

### `ollama.sh test MODEL --mode context-pressure`

Tests context growth under current hardware constraints. Use it before increasing `OLLAMA_CONTEXT_LENGTH`.

The script skips higher context by default if current VRAM pressure is already critical. Use `--force-context-pressure` only when you intentionally accept risk of CPU/GPU offload or out-of-memory behavior.

### `ollama.sh test MODEL_A MODEL_B ...`

Runs multiple generation models and produces one aggregate ZIP. The aggregate output includes:

- `multi-model-index.csv`
- aggregate `model-scorecard.csv`
- aggregate `recommendations.md`
- per-model subdirectories containing settings and evidence

Use this to compare candidates for OpenCode, Cursor, Hermes, and ADOS.

### `ollama.sh bench MODEL_A MODEL_B ...`

Role-aware benchmark command.

- generation models route to `ollama.sh test`;
- embedding models route to `ollama.sh embed-test`;
- mixed model lists are split into generation and embedding result groups.

Use it when a model list may contain both generation and embedding models.

### `ollama.sh embed-test MODEL`

Runs `/api/embed` tests for embedding/RAG models.

Rows:

- short sanity input;
- 32-chunk batch input;
- RAG-like document chunks.

Interpretation:

- `vector_dim` identifies embedding width.
- `embeddings_per_s` measures embedding request throughput.
- `embed_tokens_per_s` approximates indexing throughput.

### `ollama.sh preload MODEL --ctx 4096 --keep-alive 24h`

Preloads a model and keeps it resident. Use this when a model has good warm performance but bad first-load behavior.

### `ollama.sh gpu`

Displays the current `nvidia-smi` output.

### `ollama.sh logs [N]`

Shows recent Ollama systemd logs. Use this when diagnostics report slow runner startup, missing KV cache type, or offload warnings.

## Main setting output

Every generation diagnostic produces:

```text
performance-settings.sh
performance-settings.md
```

`performance-settings.sh` is the applyable WSL2/Linux systemd override. It sets:

```text
OLLAMA_KEEP_ALIVE
OLLAMA_MAX_LOADED_MODELS
OLLAMA_NUM_PARALLEL
OLLAMA_FLASH_ATTENTION
OLLAMA_CONTEXT_LENGTH
OLLAMA_KV_CACHE_TYPE
```

Apply only after reviewing `performance-settings.md` and the classification labels.

## Classification labels

| Label | Meaning |
|---|---|
| `FULL_GPU_RESIDENT` | Ollama reports the tested model fully resident on GPU. |
| `CPU_GPU_OFFLOAD_RISK` | The model is split between CPU and GPU; throughput is not a clean RTX 3090 resident result. |
| `GOOD_WARM_BAD_COLD` | Warm latency is good but first-load latency is high. Keep the model resident. |
| `RESIDENT_ONLY_RECOMMENDED` | Use the model after preloading; avoid frequent unload/reload workflows. |
| `VRAM_CRITICAL_HEADROOM` | VRAM exceeds the critical threshold. Avoid raising context or parallelism. |
| `CONTEXT_INCREASE_NOT_RECOMMENDED` | The current hardware/model state does not support larger context safely. |
| `THINKING_ONLY_OUTPUT_RISK` | The model produced thinking text without visible answer text for a capability row. |

## Recommended workflow

For a new model:

```bash
ollama.sh test qwen3.6:27b
```

Review:

```text
terminal-summary.txt
recommendations.md
performance-settings.md
performance-settings.sh
model-scorecard.csv
```

Apply settings only when the scorecard and classification support the chosen use case.

For multiple candidates:

```bash
ollama.sh test qwen2.5-coder:7b qwen3:8b qwen3.6:27b
```

Compare aggregate:

```text
model-scorecard.csv
recommendations.md
performance-settings-all.md
```

## Evidence levels

```bash
ollama.sh test MODEL --evidence-level compact
ollama.sh test MODEL --evidence-level standard
ollama.sh test MODEL --evidence-level full
```

`standard` keeps human summaries, scorecards, settings, environment facts, runner facts, CSVs, and key raw files. `compact` removes low-value raw stream files. `full` keeps all raw stream artifacts.
