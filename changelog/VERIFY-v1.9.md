# VERIFY v1.9

Verification surfaces are recorded in `qa-evidence/verification-output.txt`.

## Required checks

| Check | Status |
|---|---|
| Bash syntax checks for package scripts and Bash integration | PASS |
| Multi-model route-only test command | PASS |
| Multi-model role-aware bench route-only command | PASS |
| Deterministic fake aggregate multi-model run creates one ZIP | PASS |
| Aggregate ZIP contains both model sub-runs | PASS |
| README contains no release-version wording | PASS |
| README explains command behavior and result interpretation | PASS |
| ADOS capability summary logic includes coding, essay, and internet-access visible rows | PASS |
| Thinking-only rows remain excluded from visible-answer speed | PASS |
| Streaming sidecar cleanup code present | PASS |
| Package hygiene excludes nested ZIPs, run directories, caches, pyc files, and .DS_Store | PASS |
| Evidence ledger parses as JSONL | PASS |
| Extracted release archive validates for required files and hygiene | PASS |

## Limitations

Sandbox verification uses fake Ollama/NVIDIA shims for command behavior. It validates routing, archive topology, script syntax, README/package hygiene, and evidence shape. It does not claim live RTX 3090 throughput or model-quality scoring.
