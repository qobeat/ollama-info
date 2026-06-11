# ollama-info v1.7 quality evidence summary

This directory contains the ADOS apply/verify evidence used for the v1.7 package.

Files:

```text
ados-apply-verify-schema.json   schema copied from the uploaded ADOS v5.2.0 package
evidence-ledger.jsonl           single normative ADOS evidence ledger
verification-output-v1.7.txt    raw command-output summary from final sandbox verification
```

Verification covered:

- Bash syntax checks for all package shell files.
- `ollama bench --route-only` generation and embedding routing.
- strict embedding-only generation refusal with `UNSUPPORTED`, exit code 2, API rows 0, and tag-preserving next action.
- streaming generation with TTFT fields and `FirstReqLoad` summary.
- embedding benchmark with four `/api/embed` rows.
- package hygiene precheck for legacy/generated/cache artifacts.
- evidence-ledger schema validation.
- final archive hygiene and checksum production.

Limit: sandbox verification validates behavior and packaging, not live RTX 3090 performance.
