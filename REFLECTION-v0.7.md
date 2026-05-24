# REFLECTION-v0.7

## Requirement completion status

| Requirement | Status | Evidence |
|---|---:|---|
| R01 — Atomic plan and verification trace | PASS | `plan.txt` exists and contains one section per requirement. |
| R02 — Version, metadata, manifest, changelog consistency | PASS | Primary scripts report v0.7.0; changelog and manifest updated. |
| R03 — True long-context test | PASS | `--long-prompt-words`; payload `04_longctx_gpu.json`; `prompt_eval_tokens` and `context_fill_pct` in CSV. |
| R04 — Correct performance classification | PASS | Summary separates `Warm`, `Cold`, `LongCtx`, `Conc`; old mixed GPU average removed. |
| R05 — Concurrency aggregate throughput | PASS | `concurrency-aggregate.csv` created and shown in terminal summary. |
| R06 — Correct curl/timeout return-code capture | PASS | Fake failing curl records `curl_failed_rc_28`; script exits 1 when request errors exist. |
| R07 — Safe concurrent CSV append | PASS | Directory-lock append helper added; fake concurrency run produced complete CSV rows. |
| R08 — Optional soak and VRAM-pressure probes | PASS | `--soak-minutes`, `--run-vram-pressure`, `--vram-model`, `--vram-ctx`, `--vram-num-predict`; off by default. |
| R09 — More precise monitor evidence | PASS | Added `nvidia-smi -q` start/end, `dmesg-gpu-errors.txt`, enhanced monitor verdicts. |
| R10 — ASCII summaries under 50 lines | PASS | Monitor self-test summary: 15 lines; fake orchestrator summary: 31 lines; no ESC bytes. |
| R11 — Bash-only core workflow; Python legacy isolation | PASS | Core scripts do not call Python; helpers moved to `tools/legacy/`. |
| R12 — First-class README | PASS | README rewritten with purpose, install, commands, outputs, interpretation, troubleshooting, retention, safety, validation. |
| R13 — Post-change review, validation, package v0.7 | PASS | `VERIFY-v0.7.md` records tests; final package produced. |

## Iteration fixes made during review

1. Added non-zero exit from `ollama-test-RTX3090.sh` when any request row contains an error.
2. Added `Test: PASS/PASS_WITH_WARNINGS/FAIL` to the orchestrator terminal summary.
3. Fixed `--profile brief` snapshot cadence handling in `ollama-monitor.sh`.
4. Verified archive creation with fake Ollama and fake `nvidia-smi`.

## Requirements not implemented properly

None identified after the final validation pass.

## Remaining limitations

These are outside the package's WSL2/Bash scope:

- Windows Event Viewer collection.
- Guaranteed RTX 3090 GDDR6X memory junction temperature when `nvidia-smi` reports `N/A`.
- Certification-level GPU validation without running optional soak/larger-model probes on real hardware.
