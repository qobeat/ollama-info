# REVIEW v1.9

## Source review

The supplied multi-model console output and six monitored archives show that the default empty-card behavior executed as intended: each model run attempted to unload the previously resident model before starting. The result set is useful for interactive local model selection because it contains first-request load behavior, warm TTFT, visible-answer throughput, residency/offload classification, VRAM pressure, and basic capability-prompt output status.

## Serious issues found

1. **Multi-model output fragmentation.** The user invoked one multi-model command, but the runtime produced one ZIP per model. This made comparison and ADOS evidence handling noisier than necessary.
2. **Wrong visible-throughput summary for ADOS profile.** The summaries printed `Visible : no valid visible-answer throughput rows` because the summary logic only considered performance-profile categories such as `throughput` and `sustained`; the default ADOS profile uses `coding`, `essay`, and `internet_access` categories.
3. **Duplicate output surfaces.** Streaming timestamp sidecars duplicated stream-metrics JSON. Nested test terminal summaries duplicated orchestrator output when monitored runs explicitly requested no test terminal summary. Orchestrator Markdown also embedded the compact terminal summary instead of referencing it.
4. **README not authoritative enough.** The README was release-specific and did not fully explain every command, result field, interpretation rule, and use case.
5. **Package evidence duplication.** Version-specific QA evidence copies accumulated beside the current logical evidence ledger.

## Model-performance review

| Model | Clean residency | FirstReqLoad | Warm TTFT basis | Visible speed | VRAM pressure | Operational interpretation |
|---|---:|---:|---:|---:|---:|---|
| `qwen2.5-coder:7b` | yes | 35.41s | 188-202ms on warm prompts | 69-130 tok/s | 28.6% | Best coding-loop candidate in this result set. |
| `qwen3:8b` | yes | 55.08s | 203-213ms on warm prompts | about 60 tok/s | 57.0% | Best balanced general local agent candidate. |
| `gpt-oss:20b` | yes | 129.36s | answer TTFT 2.5-4.8s on visible rows | about 71-73 visible tok/s on visible rows | 97.1% | Strong decode but high VRAM and one thinking-only coding row. |
| `qwen3.6:27b` | yes | 185.50s | 454-525ms on warm prompts | about 17.4 tok/s | 98.1% | Background-only candidate; high switching risk. |
| `qwen3.6:35b` | no; CPU/GPU offload | 221.33s | 526-549ms on warm prompts | about 23-26 tok/s | 98.1% | Not a clean full-GPU RTX 3090 benchmark. |
| `gemma4:31b` | no; CPU/GPU offload | 194.13s | 576-616ms on warm prompts | about 12 tok/s | 91.0% | Not recommended for tight local workflows from these runs. |

## Repair decisions

- Implement aggregate multi-model output in the wrapper rather than duplicating orchestration logic in the direct test scripts.
- Keep `ollama-test-RTX3090.sh` as the execution engine and `ollama-test-and-monitor-RTX3090.sh` as the telemetry orchestrator.
- Keep `ollama-bench-RTX3090.sh` as a compatibility shim to the canonical wrapper.
- Count ADOS capability categories as valid visible-answer rows while excluding thinking-only rows from visible speed.
- Preserve raw JSON and monitor CSV evidence, but remove scratch sidecars and duplicate summaries.
