# Two-model performance and ADOS alignment analysis v1.7.1

## Inputs reviewed

- `ollama-test-RTX3090-20260611-132715.zip`: qwen3.6:27b direct generation test.
- `ollama-test-and-monitor-RTX3090-20260611-133048.zip`: qwen3.6:35b bench/test+monitor run.
- `Pasted text.txt`: console output.
- `Pasted markdown.md`: v1.7 plan and ADOS-oriented acceptance criteria.

## qwen3.6:27b

- Result: PASS_WITH_WARNINGS.
- Sustained row: 1024 eval tokens, 17.80 visible tok/s, TTFT answer 458.749 ms, PASS/OK.
- Throughput row: 207 eval tokens, 17.24 tok/s, TTFT answer 491.015 ms, INCONCLUSIVE/SHORT_SAMPLE.
- Long-context row: 6474 prompt tokens at ctx 8192, 79.0% context fill, 294 eval tokens, 16.59 visible tok/s, TTFT answer 28447.569 ms, PASS/OK.
- Load-state caveat: v1.7 reported `ColdVerified=1` in observed mode; v1.7.1 no longer claims verified cold in observed mode.
- Residency: archive shows qwen3.6:27b after-run processor as 100% GPU, so this remains a clean full-GPU-resident single-request generation result.

## qwen3.6:35b

- Result: PASS_WITH_WARNINGS.
- Sustained row: 1024 eval tokens, 21.27 visible tok/s, TTFT answer 601.415 ms, PASS/OK.
- Throughput row: 196 eval tokens, 21.35 tok/s, TTFT answer 604.657 ms, INCONCLUSIVE/SHORT_SAMPLE.
- Long-context row: 6474 prompt tokens at ctx 8192, 79.0% context fill, 176 eval tokens, 21.41 visible tok/s, TTFT answer 25212.810 ms, INCONCLUSIVE/SHORT_SAMPLE.
- First request/load: 261.24s observed FirstReqLoad with 261959 ms first TTFT; not verified cold.
- Hardware: monitor summary showed max VRAM 24164 / 24576 MiB (98.3%), core max 48C, hw_slowdown=0, and PCIe Gen3 x16.
- Serious caveat: nested archive shows qwen3.6:27b resident before the qwen3.6:35b run, and qwen3.6:35b after-run processor as 15%/85% CPU/GPU. v1.7.1 classifies this as model-switch observed plus CPU/GPU offload; not clean full-GPU-resident execution.

## ADOS alignment

### Good alignment

- Uses explicit artifacts: package zip, quality evidence, verification output, changelog, atomic requirements, review, verify, reflection.
- Benchmark now records structured result states and sample validity (`OK`, `SHORT_SAMPLE`, `UNDERFILLED`, `UNSUPPORTED`).
- v1.7.1 closes evidence-semantic gaps exposed by real results: load state, offload/residency, and TTFT aggregation.

### Partial alignment

- The attached real runs are generation-only and concurrency=1.
- No embedding result archive was attached for qwen3-embedding:4b or bge-m3.
- No concurrency p50/p95/p99 evidence was attached for MCP/agentic behavior.
- No JSON/tool-call validity profile was attached.
- No phase-tagged telemetry was attached for load vs prompt-eval vs decode vs idle.

### Practical interpretation

The attached runs align well with ADOS apply/verify artifact governance and single-request benchmark verification. They only partially align with ADOS workload usage for Cursor/MCP/RAG/agentic flows because those require concurrency, tail latency, embedding throughput, and tool/JSON correctness profiles.
