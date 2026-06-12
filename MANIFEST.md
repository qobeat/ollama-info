# MANIFEST

## Authority order

1. `PACKAGE.json` owns package identity and compaction constraints.
2. `README.md` owns user-facing command behavior and interpretation guidance.
3. `scripts/` owns executable behavior.
4. `SOURCE-OF-TRUTH.json` owns governed concept ownership.
5. `changelog/plan-1.10.txt` owns release plan and requirements mapping.
6. `qa-evidence/evidence-ledger.jsonl` owns observed verification facts.

## Required runtime surfaces

- `scripts/ollama.sh`
- `scripts/ollama-test-RTX3090.sh`
- `scripts/ollama-test-and-monitor-RTX3090.sh`
- `scripts/ollama-embed-test-RTX3090.sh`
- `scripts/ollama-bench-RTX3090.sh`
- `scripts/ollama-common.sh`
- `scripts/ollama-run-generate.py`
- `scripts/ollama-summarize-results.py`

## Package boundary

The source package excludes runtime `run-*` directories, nested ZIP files, Python caches, and generated test debris. Runtime result ZIPs are created outside the source package under the configured temporary directory.
