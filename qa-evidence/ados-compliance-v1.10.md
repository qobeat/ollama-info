# ADOS compliance mapping v1.10

Applicable ADOS requirements were mapped to concrete surfaces in this package.

| ADOS area | Package implementation |
|---|---|
| Project Shape / identity | `PACKAGE.json`, `MANIFEST.md`, `qa-evidence/request-record-v1.10.md` |
| Goal and Objectives formation | `changelog/plan-1.10.txt`, `qa-evidence/request-record-v1.10.md` |
| Specification first | plan and atomic requirements are materialized before verification evidence |
| Source-of-truth discipline | `SOURCE-OF-TRUTH.json` maps governed concepts to owners |
| Evidence ledger | `qa-evidence/evidence-ledger.jsonl` is the logical evidence ledger |
| Compaction | package hygiene excludes run directories, nested ZIPs, caches, and pyc files |
| Schema-backed data | `schema.json` validates evidence rows at minimum shape level |
| Semantic replay / behavioral verification | fake Ollama/NVIDIA harness exercises command routing and generated artifacts |
| Self-evaluation | `qa-evidence/self-evaluation-v1.10.md` records axis-level scoring |
| Reflection/finalization | `changelog/REFLECTION-v1.10.md`, `qa-evidence/QUALITY-EVIDENCE-SUMMARY-v1.10.md` |

The package is not a full implementation of the attached ADOS profile itself. It applies the profile requirements that are relevant to this local diagnostic package: bounded goal, objectives, evidence materialization, compaction, testability, replay, self-evaluation, and finalization evidence.
