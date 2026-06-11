# REFLECTION v1.7

## Final status

v1.7 is complete and packaged.

The implementation used v1.6 as the base, applied the pasted v1.7 benchmark plan, added cleanup of unused/generated/legacy files, and produced ADOS apply/verify quality evidence.

## Completed requirement groups

- Role-aware `ollama bench` auto-router.
- Strict `ollama test` generation-only behavior.
- `UNSUPPORTED` result state for embedding-only generation attempts.
- First-class `/api/embed` benchmark with sanity, batch, long-context, and RAG-profile rows.
- Streaming TTFT metrics and visible-answer throughput fields.
- `FirstReqLoad` load-state terminology and load-state evidence.
- Sample validity states for short/underfilled rows.
- Dynamic non-llama metadata extraction.
- Calibrated RTX 3090 hardware warnings.
- Cleanup of legacy/generated package debris.
- Schema-validated ADOS evidence ledger.
- v1.7 package archive and checksum.

## Known boundaries

- The sandbox cannot validate real RTX 3090 throughput, real PCIe behavior, real memory junction telemetry, or real Ollama model quality.
- The verification harness used fake Ollama/NVIDIA shims for deterministic behavioral checks.
- Downstream acceptance should include real runs on the target WSL2 + RTX 3090 host:
  - `ollama bench gpt-oss:20b`
  - `ollama bench qwen3-embedding:4b`
  - `ollama test qwen3.6:27b --profile agentic` when future profile aliases are expanded further.

## Packaging reflection

The release archive contains source, documentation, manifest, and quality evidence. Generated run outputs from verification remain outside the package tree except for the concise verification output copied into `qa-evidence/`.
