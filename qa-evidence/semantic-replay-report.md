# Semantic replay report v1.13

v1.13 was replayed against uploaded v1.12 result folders to verify semantic changes without rerunning Ollama.

Expected semantic changes were observed:

- v1.12 `FAIL`/skipped context presentation became `NOT_RUN_SKIPPED` when no 65K runtime row existed.
- `Runtime >= required attempted` is `NO` for skipped-only rows.
- Hermes/main-chat remains unconfirmed.
- Existing ambiguous internet-boundary rows prevent decision-grade recommendations.
- Aggregate recommendations do not select winners when decision-grade gates fail.
- Aggregate next steps show an implemented vision command with required `--image`.
