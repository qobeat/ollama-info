# ADOS compliance matrix

| ADOS concern | v1.11 surface | Result |
|---|---|---|
| Goal/Objectives formation | `requirements.md`, `README.md` | PASS |
| Source-of-truth discipline | `SOURCE-OF-TRUTH.json`, `MANIFEST.md` | PASS |
| Specification before mutation | `changelog/plan-1.11.txt`, `requirements.md` | PASS |
| Evidence ledger | `qa-evidence/evidence-ledger.jsonl` | PASS |
| Schema/data discipline | `schema.json`, JSON parse checks | PASS |
| Compaction/package boundary | package hygiene checks | PASS |
| Semantic replay | fake success/failure/aggregate harnesses | PASS |
| Bounded repair | root-cause repair records and repeat verification | PASS |
| Self-evaluation | `qa-evidence/self-evaluation.md` | PASS with limitation note |
| Finalization | package and evidence ZIPs plus SHA256 files | PASS |

Limitation: live RTX 3090 model selection still requires rerunning v1.11 on the host because sandbox verification uses fake Ollama endpoints.
