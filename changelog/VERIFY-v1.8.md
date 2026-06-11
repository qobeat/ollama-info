# VERIFY v1.8

Verification scope:

- shell syntax checks for all shell scripts and bashrc
- deterministic fake Ollama/NVIDIA route-only checks
- deterministic fake empty-card run check
- ADOS prompt payload inspection
- performance profile compatibility check
- package hygiene check
- evidence ledger JSONL parse
- extracted archive validation

Required checks:

```text
PASS bash -n for scripts and bashrc
PASS ollama.sh test multi-model --route-only
PASS ollama.sh bench multi-model --route-only with role routing
PASS default test plan uses profile=ados and load_mode=empty-card
PASS empty-card mode records empty_card_requested=1 and empty_card_verified=1 under fake harness
PASS default ADOS run emits 01_coding_first_prompt, 02_essay_second_prompt, 03_internet_access_third_prompt
PASS capability-analysis.md is produced for ADOS profile
PASS --profile perf preserves 01_sanity_gpu, 02_throughput_gpu, 03_sustained_gpu, 04_longctx_gpu
PASS bashrc delegates to ollama.sh
PASS ollama-bench-RTX3090.sh is a shim
PASS package archive excludes generated run artifacts, caches, nested zips, and pyc files
```
