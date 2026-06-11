# REVIEW v1.7.1

## Reviewed artifacts

- `ollama-test-RTX3090-20260611-132715.zip`: direct `qwen3.6:27b` generation benchmark.
- `ollama-test-and-monitor-RTX3090-20260611-133048.zip`: `ollama bench qwen3.6:35b` generation benchmark with monitor.
- `Pasted text.txt`: console output for both runs.
- `Pasted markdown.md`: v1.7 plan and acceptance criteria.

## Serious defects found

### 1. Incorrect full-GPU implication for qwen3.6:35b

The qwen3.6:35b archive contains:

```text
ollama-ps-after.txt:
qwen3.6:35b ... 15%/85% CPU/GPU ...
```

The v1.7 terminal summary reported:

```text
Visible : single GPU 21.27 tok/s avg ...
```

This is materially misleading. A mixed CPU/GPU Ollama placement is not a clean full-GPU resident decode benchmark.

### 2. Incorrect cold/load-state evidence for model-switch run

The qwen3.6:35b archive contains:

```text
ollama-ps-before.txt:
qwen3.6:27b ... 100% GPU ...
```

The nested load-state file nevertheless said:

```text
model_resident_before=absent
cold_verified=1
```

That is insufficient because the run had to replace or evict an already-resident model. FirstReqLoad for qwen3.6:35b must be interpreted as observed first request during a model switch/offload path, not verified cold load.

### 3. TTFT aggregation obscured warm latency

The existing `TTFTany avg` mixed first-load, warm short prompts, and long-context rows. This was numerically correct as an all-row average, but not operationally helpful for Cursor/MCP/ADOS usage. v1.7.1 now reports FirstTTFT, WarmTTFT, and TTFTall separately.

## Risk assessment

- qwen3.6:27b result remains usable as a single-request, full-GPU-resident generation benchmark because `ollama-ps-after.txt` shows `100% GPU`.
- qwen3.6:35b result remains useful as a warning-bearing measurement, but its throughput should not be compared as a clean full-GPU benchmark because of mixed CPU/GPU residency and near-total VRAM pressure.
