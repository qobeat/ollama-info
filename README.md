# ollama-info

`ollama-info` provides a local RTX 3090 + Ollama command layer for model health checks, capability probes, monitored benchmarks, embedding tests, and compact evidence archives. It is designed for WSL2/Linux workstations where Ollama runs as a local service and an NVIDIA RTX 3090 is the primary inference device.

The package installs a small Bash wrapper, `scripts/ollama.sh`, that can be exposed as `ollama` through `bashrc/.bashrc`. Known `ollama-info` commands are handled by the wrapper. Unknown subcommands pass through to the native Ollama CLI.

## Installation

From the package root:

```bash
chmod +x scripts/*
```

To expose the wrapper through your shell, review and install the provided Bash integration:

```bash
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
```

The integration adds helper aliases and functions while keeping server-side Ollama configuration in systemd or your normal Ollama service configuration.

## Command overview

| Command | Primary use | Output style |
|---|---|---|
| `ollama status` | Check Ollama API, service, GPU, and quick readiness. | Terminal dashboard. |
| `ollama start` | Start or restart the local Ollama service. | Service command output and status. |
| `ollama stop` | Stop the local Ollama service. | Service command output and status. |
| `ollama models` | List local models, classify generation vs embedding, and show suggested benchmark commands. | Terminal model table. |
| `ollama gpu` | Run `nvidia-smi` through the wrapper. | NVIDIA telemetry. |
| `ollama logs` | Show recent Ollama systemd logs. | Journal text. |
| `ollama test MODEL...` | Run the default generation capability profile. | Monitored run directory and ZIP archive. |
| `ollama bench MODEL...` | Auto-route each model to the correct generation or embedding benchmark. | Monitored run directory and ZIP archive. |
| `ollama embed-test MODEL...` | Force the embedding benchmark through `/api/embed`. | Monitored embedding run directory and ZIP archive. |
| `ollama <native command>` | Pass unknown commands to the native Ollama CLI. | Native Ollama output. |

## `ollama status`

```bash
ollama status
ollama status --brief
```

### What it does

`ollama status` checks whether the local Ollama API responds, whether the system service is active when systemd is available, and whether the NVIDIA GPU is visible. It prints the configured API URL, Ollama API version when reachable, GPU name, temperature, memory use, and utilization.

### How to interpret it

A healthy local setup shows:

```text
api: RUNNING
service: active
GPU: NVIDIA GeForce RTX 3090
```

High idle VRAM use before a benchmark means another model, desktop process, or WSL graphics component may already be occupying memory. That matters for large models because high VRAM occupancy can push a run into CPU/GPU offload or make model switching slow.

### When to use it

Use `ollama status` before model tests, after restarting Ollama, after a failed benchmark, and when you need a quick readiness check for Cursor, OpenCode, Hermes Agent, or ADOS local workflows.

## `ollama start`

```bash
ollama start
```

### What it does

`ollama start` starts the Ollama service through the available local service manager. It then reports whether the API is reachable.

### How to interpret it

The command is successful when the API reports `RUNNING`. If the service starts but the API is not reachable, inspect `ollama logs` and confirm that the service is bound to the expected host and port.

### When to use it

Use it after boot, after changing service configuration, or when `ollama status` says the API is not reachable.

## `ollama stop`

```bash
ollama stop
```

### What it does

`ollama stop` stops the local Ollama service through the available local service manager.

### How to interpret it

A successful stop means the API should no longer respond. GPU memory used by Ollama should be released after the service exits.

### When to use it

Use it before service-level configuration changes, before a verified restart-style load test, or when you need to clear all resident models by stopping the service.

## `ollama models`

```bash
ollama models
```

### What it does

`ollama models` queries the local Ollama API, lists locally available models, classifies each model role, and prints suggested commands. Generation-capable models are suggested for `ollama test` and `ollama bench`; embedding-only models are suggested for `ollama bench` or `ollama embed-test`.

### How to interpret it

The `ROLE` column is important:

```text
generate   use /api/generate tests
embedding  use /api/embed tests
unknown    inspect the model before benchmarking
```

`ollama test` is intentionally strict generation mode. It does not silently treat an embedding-only model as a generation model. Use `ollama bench` when you want automatic role routing.

### When to use it

Use it when choosing model names, when a pattern is ambiguous, after pulling a new model, or before running a multi-model comparison.

## `ollama gpu`

```bash
ollama gpu
ollama gpu --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu --format=csv
```

### What it does

`ollama gpu` passes arguments to `nvidia-smi`. It is a convenience wrapper for direct GPU inspection.

### How to interpret it

Key fields:

| Field | Meaning |
|---|---|
| `memory.used` | VRAM already occupied. High values before a run can contaminate residency results. |
| `temperature.gpu` | GPU core temperature. Core temperature is not the same as GDDR6X memory-junction temperature. |
| `utilization.gpu` | Current GPU compute activity. |
| power draw / power limit | Whether the card is near its configured power cap. |
| PCIe generation and width | Link state; lower-than-maximum width mainly affects load/offload/model switching, not necessarily resident decode. |

### When to use it

Use it during debugging, after a benchmark warning, and when validating that no old model is still occupying VRAM.

## `ollama logs`

```bash
ollama logs
ollama logs 300
```

### What it does

`ollama logs` displays recent systemd journal entries for the Ollama service. The optional numeric argument controls how many lines are shown.

### How to interpret it

Look for model-load failures, missing blobs, permission errors, GPU allocation failures, HTTP errors, and service restarts. Pair log review with the generated `failure-hints.txt` inside benchmark archives.

### When to use it

Use it after HTTP failures, unexpected model unloads, slow first request loads, or service instability.

## `ollama test`

```bash
ollama test qwen2.5-coder:7b
ollama test qwen3.6:35b qwen3.6:27b gpt-oss:20b
ollama test qwen3.6:27b --profile perf
ollama test qwen3.6:27b --load-mode observed
```

### What it does

`ollama test` runs generation tests through `/api/generate`. By default it uses an empty-card load policy and a three-prompt ADOS capability profile:

| Prompt | Category | Purpose |
|---|---|---|
| `01_coding_first_prompt` | coding | Checks whether the model can produce useful code and concise tests. |
| `02_essay_second_prompt` | essay | Checks structured prose and technical explanation. |
| `03_internet_access_third_prompt` | internet access | Checks whether the local model honestly states that it cannot browse live web unless tools are provided. |

Before the first prompt, the command attempts to unload resident Ollama models. This makes the run less dependent on the model currently loaded on the RTX card. The first prompt measures the first-request load path. The second and third prompts show warm interactive behavior after the model is loaded.

When several models are provided in one command, the wrapper creates a single aggregate run directory and one ZIP archive containing all sub-runs.

### How to interpret the results

The terminal summary is the first artifact to read. Important lines:

| Summary field | Meaning | Good result |
|---|---|---|
| `Test` | Overall test state and row counts. | `PASS` or `PASS_WITH_WARNINGS` with explainable warnings. |
| `Residency` | Whether Ollama reports the tested model as fully GPU-resident or CPU/GPU offloaded. | `full GPU (100% GPU)` for clean RTX 3090 comparisons. |
| `FirstReqLoad` | Ollama first request load duration after the selected load policy. | Lower is better; compare only under the same load mode. |
| `FirstTTFT` | Time to first streamed token on the first prompt. | Expected to include load time in empty-card mode. |
| `WarmTTFT` | Time to first streamed token after the model is loaded. | Better proxy for Cursor/OpenCode/Hermes interactive feel. |
| `Visible` | Visible-answer token rate for valid rows. | Higher is better; thinking-only rows are not counted as visible-answer speed. |
| `Output` | Counts visible rows, thinking-only rows, and errors. | Visible rows for all capability prompts unless the model intentionally thinks first. |
| `Telemetry` | GPU monitor verdict. | `PASS`; warnings require review. |
| `VRAM` | Peak GPU memory and warning/critical sample counts. | Less than 92% is comfortable; over 97% is high-risk for switching/offload. |
| `Power` | Power draw and power-cap samples. | Software power-cap samples are normal when transient; hardware slowdown is critical. |
| `PCIe` | Current link generation and width. | Lower links are warnings for load/offload/concurrency, not automatic decode invalidation. |

### Result states

| State | Meaning |
|---|---|
| `PASS` | The requested benchmark completed without material warnings. |
| `PASS_WITH_WARNINGS` | The benchmark completed, but sample, output, hardware, residency, or telemetry warnings need review. |
| `UNSUPPORTED` | The model role does not support the requested benchmark, such as an embedding-only model in generation mode. |
| `INCONCLUSIVE` | The run did not produce enough valid evidence for the requested metric. |
| `FAIL` | API, runtime, or validation errors occurred. |

### Sample statuses

| Sample status | Meaning |
|---|---|
| `OK` | The row has enough output for its profile. |
| `SHORT_SAMPLE` | The model stopped too early for a stable throughput or long-context metric. |
| `UNDERFILLED` | The prompt did not fill enough of the intended context window. |
| `UNSUPPORTED` | The row is an intentional preflight block, not a failed API call. |

### When to use it

Use `ollama test` when selecting a local generation model for daily coding, prose, assistant, and ADOS-style runtime work. Use the default profile for operational model selection. Use `--profile perf` when you need long-context and sustained-decode performance rows.

## `ollama bench`

```bash
ollama bench qwen2.5-coder:7b
ollama bench qwen3-embedding:4b
ollama bench qwen3-embedding:4b qwen2.5-coder:7b
ollama bench qwen3.6:27b --profile perf
```

### What it does

`ollama bench` resolves each model, inspects its role through Ollama metadata, and routes it:

```text
generation-capable model -> /api/generate monitored benchmark
embedding-only model     -> /api/embed monitored benchmark
unknown role             -> preflight refusal with evidence
```

Multi-model `bench` uses one aggregate ZIP archive, the same as multi-model `test`.

### How to interpret the results

For generation models, read the same fields as `ollama test`.

For embedding models, read:

| Field | Meaning |
|---|---|
| `Embed` | Number of vectors, vector dimension, rows, pass count, and average embeddings per second. |
| `LongEmb` | Whether a long input reached the intended context-fill target. |
| `endpoint` | Should be `/api/embed`. |
| `vector_dim` | Embedding vector size. This should be stable for a model. |
| `embedding_tps` | Embeddings per second for the row. |
| `prompt_eval_tokens` | Input tokens processed by the embedding endpoint when reported by Ollama. |

### When to use it

Use `ollama bench` when comparing mixed model sets or when you do not want to remember whether a model is generation-capable or embedding-only. It is the safest command for broad local model inventory checks.

## `ollama embed-test`

```bash
ollama embed-test bge-m3:latest
ollama embed-test qwen3-embedding:4b
ollama embed-test bge-m3:latest qwen3-embedding:4b
```

### What it does

`ollama embed-test` forces `/api/embed` mode. It runs short-input, batch, long-context, and RAG-profile embedding probes while collecting monitor telemetry.

### How to interpret the results

Use this command to verify:

```text
endpoint=/api/embed
vector_count > 0
vector_dim is present
embedding_tps is present
errors=0
```

A generation model may or may not expose embedding behavior depending on its Ollama capabilities. An embedding-only model should pass here and should be reported as unsupported by strict generation tests.

### When to use it

Use it for RAG indexing, retrieval pipelines, document chunking tests, and validating embedding model health before wiring the model into a vector store.

## Profiles

### Default capability profile

```bash
ollama test MODEL
```

Use the default profile for daily model selection. It answers three practical questions:

```text
Can the model code?
Can the model write structured prose?
Does the model avoid pretending to browse the internet?
```

### Performance profile

```bash
ollama test MODEL --profile perf
```

Use the performance profile for sustained decode and long-context behavior. It adds rows such as sanity, throughput, sustained generation, and long context. A long-context row is useful only when it has enough context fill and enough generated output.

### Stress and concurrency probes

```bash
ollama test MODEL --stress
ollama test MODEL --run-conc --concurrency 2
ollama test MODEL --run-conc --concurrency 4
```

Use these when evaluating local agent workloads with overlapping requests. Concurrency results are more relevant for MCP servers, multi-agent task runners, and background ADOS workflows than for single-user chat.

## Load modes

| Load mode | Behavior | Use case |
|---|---|---|
| `empty-card` | Attempts to unload all resident Ollama models before the run and records whether the tested model was absent before first request. | Default comparable local benchmark. |
| `observed` | Does not unload; records the current state. | Diagnosing real current workstation behavior. |
| `warm` | Assumes or prepares warm behavior where applicable. | Interactive latency checks after a model is already loaded. |
| `unload-model` | Unloads the tested model before the run. | Model-specific first-request checks. |
| `restart-ollama` | Restarts the service before testing when available. | Stronger service-level load-state isolation. |

`ColdVerified` means the benchmark verified the model-residency precondition for the selected mode. It does not prove operating-system page-cache coldness or physical disk throughput.

## Files produced by a run

A single-model monitored run creates one run directory and, unless disabled, one ZIP archive. A multi-model command creates one aggregate run directory and one aggregate ZIP archive containing each model sub-run.

Important files:

| File | Purpose |
|---|---|
| `terminal-summary.txt` | Compact human-readable summary. |
| `orchestrator-summary.md` | Markdown report with links to component files and interpretation guidance. |
| `test/*/summary.csv` | Sortable per-row metrics. |
| `test/*/summary.md` | Detailed test-only summary. |
| `test/*/capability-analysis.md` | Capability-profile validity notes. |
| `test/*/load-state.txt` | Empty-card, observed, warm, unload, or restart evidence. |
| `test/*/failure-hints.txt` | Classified failure hints and next actions. |
| `test/*/raw/` | Raw Ollama JSON and streaming NDJSON. |
| `test/*/payloads/` | Request payloads for reproducibility. |
| `monitor/*/gpu.csv` | GPU telemetry samples. |
| `monitor/*/report.md` | Hardware monitor summary. |
| `hardware/` | Start/end NVIDIA snapshots. |
| `multi-model-summary.md` | Aggregate report for multi-model commands. |
| `multi-model-index.csv` | Machine-readable index for multi-model commands. |

The archive intentionally keeps raw API evidence and monitor CSV files because they are needed to audit benchmark claims. Scratch timestamp sidecars and duplicate nested ZIPs are not part of the durable output.

## Choosing a model from benchmark data

Use the workload, not one global score.

| Workload | Primary metrics | Preferred traits |
|---|---|---|
| Cursor / IDE loop | warm TTFT, visible token rate, low VRAM pressure | Fast warm response and clean full-GPU residency. |
| OpenCode terminal agent | coding prompt quality, warm TTFT, visible token rate, VRAM headroom | Fast coding responses and enough context headroom for project files. |
| Hermes Agent | warm TTFT, model-switch cost, memory headroom, stable output | Reliable long-running agent behavior and low risk of offload. |
| ADOS workflows | coding/prose/internet-boundary behavior, evidence quality, optional perf and concurrency rows | Transparent outputs, valid capability rows, and reproducible evidence. |
| RAG / embeddings | vector dimension, embedding throughput, batch behavior, long input behavior | Stable `/api/embed` results and predictable vector shape. |

A larger model is not automatically better for local agentic use. A smaller model with fast warm TTFT, low VRAM pressure, and clean full-GPU residency is usually better for tight coding loops. Larger or offloaded models are more appropriate for background analysis when latency is less important.

## Practical interpretation rules

1. Treat the first prompt in empty-card mode as a load-path measurement, not normal interactive latency.
2. Use the second and third prompts for warm interactive latency.
3. Exclude thinking-only rows from visible-answer speed comparisons.
4. Treat CPU/GPU offload as a warning for clean RTX 3090 comparisons.
5. Treat VRAM above 97% as high-risk for model switching, fragmentation, and OOM.
6. Use `--profile perf` before making long-context claims.
7. Use concurrency probes before making multi-agent or MCP service claims.
8. Use `embed-test` before making RAG indexing claims.

## Troubleshooting

| Symptom | Likely meaning | Next action |
|---|---|---|
| `UNSUPPORTED` for `ollama test` | The selected model is embedding-only or cannot generate. | Run `ollama bench MODEL` or `ollama embed-test MODEL`. |
| `Residency: WARN cpu_gpu_offload` | Ollama reports that the model is not fully GPU-resident. | Use a smaller model, lower context, free VRAM, or accept that the result is mixed CPU/GPU. |
| Huge `FirstReqLoad` but low `WarmTTFT` | Model loading is slow, but interaction after load is acceptable. | Keep the model warm or investigate model storage and switching. |
| `SHORT_SAMPLE` | The model stopped too early for a stable metric. | Use prompts that force longer output or inspect whether the task naturally ends early. |
| High VRAM critical count | Model is close to the 24 GB limit. | Avoid model switching, concurrent requests, and larger context windows. |
| Hardware slowdown | NVIDIA reports actual hardware slowdown. | Stop testing and inspect power, thermals, clocks, and system health. |

## Bash aliases

The provided Bash integration defines short aliases:

| Alias | Expands to |
|---|---|
| `os` | `ollama_status` |
| `oq` | `ollama_quick_status` |
| `ost` | `ollama_start` |
| `osp` | `ollama_stop` |
| `om` | `ollama_models` |
| `og` | `ollama_gpu` |
| `ol` | `ollama_logs` |
| `ot` | `ollama_test` |
| `ob` | `ollama_bench` |
| `oet` | `ollama_embed_test` |

## Package boundary

The package contains source scripts, Bash integration, changelog, and quality evidence. Runtime logs, benchmark runs, temporary files, caches, generated archives, nested ZIPs, and machine-specific output belong outside the source package except when deliberately included as QA evidence.
