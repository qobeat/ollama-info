# MANIFEST

## Authority order

1. `PACKAGE.json` owns package identity and compaction constraints.
2. `requirements.md` owns durable goal, objective, and release requirement obligations.
3. `README.md` owns user-facing command behavior and interpretation guidance.
4. `scripts/` owns executable behavior.
5. `SOURCE-OF-TRUTH.json` owns governed concept ownership.
6. `changelog/plan-1.11.txt` owns implementation plan and atomic work mapping.
7. `qa-evidence/evidence-ledger.jsonl` owns observed verification facts.

## Required runtime surfaces

- `scripts/ollama.sh`
- `scripts/ollama-test-RTX3090.sh`
- `scripts/ollama-test-and-monitor-RTX3090.sh`
- `scripts/ollama-embed-test-RTX3090.sh`
- `scripts/ollama-bench-RTX3090.sh`
- `scripts/ollama-common.sh`
- `scripts/ollama-run-generate.py`
- `scripts/ollama-summarize-results.py`

## Required documentation and governance surfaces

- `README.md`
- `requirements.md`
- `PACKAGE.json`
- `SOURCE-OF-TRUTH.json`
- `schema.json`
- `qa-evidence/evidence-ledger.jsonl`

## Package boundary

The source package excludes runtime `run-*` directories, nested ZIP files, Python caches, `.pyc` files, `.DS_Store`, and unrelated generated artifacts. Runtime result ZIPs are created outside the source package under the configured temporary directory.
