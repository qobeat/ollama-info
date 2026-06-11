# REVIEW v1.7

## Scope reviewed

v1.7 was produced from the v1.6 package and applied the copied v1.7 development plan plus the explicit cleanup requirement. The review focused on:

- role-aware generation vs embedding routing;
- strict generation refusal for embedding-only models;
- `/api/embed` embedding benchmark coverage;
- streaming TTFT and visible-answer accounting;
- `FirstReqLoad` and load-state semantics;
- dynamic model metadata extraction;
- calibrated RTX 3090 telemetry warnings;
- package cleanup and evidence hygiene;
- ADOS apply/verify ledger production.

## Implementation review

### Role-aware behavior

`ollama-common.sh` now classifies model role from `/api/show` capabilities and writes architecture-agnostic slim metadata. `ollama-bench-RTX3090.sh` uses that role to route models to generation or embedding mode. `ollama test MODEL` remains strict generation mode and refuses embedding-only models as `UNSUPPORTED`.

### Embedding benchmark

Embedding mode uses Ollama `/api/embed`. The suite now includes:

1. `01_embed_sanity`
2. `02_embed_batch`
3. `03_embed_longctx`
4. `04_embed_rag_profile`

The summary schema records endpoint, vector count, vector dimension, prompt token count, embedding token throughput, and embeddings/sec.

### Generation latency and sample quality

Generation mode streams by default. It records first JSON chunk, first thinking chunk, first answer chunk, time to 100 tokens, and estimated time to 500 tokens. Throughput reporting separates raw decode speed from visible-answer speed and flags thinking-only rows.

The benchmark now marks invalid comparison rows as `SHORT_SAMPLE` or `UNDERFILLED` instead of silently treating them as clean throughput evidence.

### Load-state semantics

The summary now reports `FirstReqLoad` instead of `Cold`. `load-state.txt` records whether the model was resident before the first request and whether cold verification was actually established. Supported modes are `observed`, `warm`, `unload-model`, and `restart-ollama`.

### Hardware warning calibration

Monitor and orchestrator summaries now treat software power-limit samples as power-cap behavior. Hardware slowdown remains critical. Memory junction temperature unavailable is reported as unknown. VRAM thresholds distinguish warning and critical occupancy risk. PCIe Gen3 x8 is reported as a load/offload/concurrency warning rather than as proof that resident decode is invalid.

### Cleanup

The package no longer ships `scripts/legacy/` or obsolete generated artifacts. `ollama-perf-table` no longer depends on deleted legacy Python calculators.

## Limitations

Verification in this environment used fake Ollama and fake NVIDIA command shims. This validates shell behavior, CSV shape, routing semantics, classification, evidence, and package hygiene. It does not validate real RTX 3090 throughput, real VRAM pressure, real thermal behavior, or real Ollama model quality.
