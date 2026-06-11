# Quality Evidence Summary v1.8

## Verification performed

```text
PASS shell syntax checks for package scripts and bashrc
PASS route-only multi-model `ollama.sh test`
PASS route-only multi-model `ollama.sh bench` with role-aware generation/embedding routing
PASS default ADOS fake run uses profile=ados and load_mode=empty-card
PASS fake empty-card run records empty_card_requested=1 and empty_card_verified=1
PASS default ADOS fake run emits three prompts: coding, essay, internet-access
PASS capability-analysis.md is generated for ADOS profile
PASS --profile perf preserves v1.7-style four-row performance profile
PASS bashrc delegates to ollama.sh
PASS ollama-bench-RTX3090.sh is a wrapper shim
PASS package hygiene checks
PASS evidence ledger JSONL parse
PASS extracted package validation
```

## Important limitation

The verification harness is deterministic and fake. It validates command behavior, routing, file production, evidence shape, and package hygiene. It does not claim live RTX 3090 throughput.
