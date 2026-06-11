# Review of supplied RTX 3090 test results

## Source set

Reviewed supplied console output plus these monitored result archives:

```text
ollama-test-and-monitor-RTX3090-20260611-174025.zip  qwen3.6:35b
ollama-test-and-monitor-RTX3090-20260611-174503.zip  qwen3.6:27b
ollama-test-and-monitor-RTX3090-20260611-174936.zip  gpt-oss:20b
ollama-test-and-monitor-RTX3090-20260611-175218.zip  qwen3:8b
ollama-test-and-monitor-RTX3090-20260611-175335.zip  qwen2.5-coder:7b
ollama-test-and-monitor-RTX3090-20260611-175432.zip  gemma4:31b
```

## Cross-run findings

1. Empty-card behavior executed before each model run and recorded resident model state.
2. The default ADOS profile produced three capability rows per model: coding, essay, and internet-access boundary behavior.
3. The summary logic was too performance-profile-specific and did not count ADOS capability rows as valid visible-answer throughput.
4. One multi-model command produced multiple ZIP archives, so archive aggregation needed repair.
5. Large models at or near the 24 GB RTX 3090 limit produced high VRAM warnings and, for some models, CPU/GPU offload.
6. First-request load times are large for every model because empty-card mode measures the first request after unload; warm TTFT is the better interactive latency metric.

## Metrics extracted from supplied runs

| Model | Residency | FirstReqLoad | Warm TTFT / answer behavior | Visible speed evidence | VRAM | Telemetry | Interpretation |
|---|---|---:|---|---|---|---|---|
| `qwen2.5-coder:7b` | full GPU | 35.41s | 188ms essay, 202ms internet | 130.27 coding, 83.44 essay, 69.20 internet tok/s | 7018/24576 MiB, 28.6% | PASS | Best local coding-loop candidate. |
| `qwen3:8b` | full GPU | 55.08s | 213ms essay, 203ms internet | about 60 tok/s on all rows | 13998/24576 MiB, 57.0% | PASS | Best balanced general local agent candidate. |
| `gpt-oss:20b` | full GPU | 129.36s | answer TTFT 4796ms essay, 2519ms internet; coding was thinking-only | 71.47 essay, 72.69 internet tok/s | 23856/24576 MiB, 97.1% | PASS_WITH_WARNINGS | Fast visible rows but high VRAM and output-shape warning. |
| `qwen3.6:27b` | full GPU | 185.50s | 454ms essay, 525ms internet | about 17.4-17.7 tok/s | 24104/24576 MiB, 98.1% | PASS_WITH_WARNINGS | Background-only due high VRAM and lower speed. |
| `qwen3.6:35b` | CPU/GPU offload | 221.33s | 526ms essay, 549ms internet | about 23.4-25.6 tok/s | 24106/24576 MiB, 98.1% | PASS_WITH_WARNINGS | Not a clean full-GPU benchmark. |
| `gemma4:31b` | CPU/GPU offload | 194.13s | 576ms essay, 616ms internet | about 11.7-12.2 tok/s | 22371/24576 MiB, 91.0% | PASS | Slow and offloaded; not preferred. |

## Workload recommendations from current evidence

| Workload | Recommended model | Reason |
|---|---|---|
| OpenCode | `qwen2.5-coder:7b` | It has the best coding-loop speed, fastest warm TTFT, low VRAM pressure, and clean full-GPU residency. |
| Cursor | `qwen2.5-coder:7b` | Cursor-like IDE loops need low warm latency and fast visible answer output; this model is the strongest measured candidate. |
| Hermes Agent | `qwen3:8b` | Hermes-style long-running agent workflows benefit from stable visible output, moderate VRAM use, full-GPU residency, and low warm TTFT. |
| ADOS | `qwen3:8b` as default; `qwen2.5-coder:7b` for code-heavy apply steps | ADOS needs coding, prose, and internet-boundary behavior with reproducible output; `qwen3:8b` is the best balanced general candidate while `qwen2.5-coder:7b` is better for implementation-heavy tasks. |

## Caution

These recommendations are based on operational benchmark signals, not a human semantic quality grade. The supplied runs do not include full concurrency, long-context perf profile, embedding/RAG, or JSON/tool-call reliability probes for every model.
