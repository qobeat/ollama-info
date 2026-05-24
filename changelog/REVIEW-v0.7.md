# REVIEW-v0.7

## Scope

Deep review of `ollama-info v0.6` with the goal of improving RTX 3090 health/performance monitoring, preserving precise troubleshooting evidence, and removing misleading or duplicated metrics.

## Key v0.6 findings

1. The long-context test was not a true long-context test. It set `num_ctx=8192` but used a short prompt, so `prompt_eval_count` did not prove actual long-context load.
2. The terminal headline mixed cold sanity, warm single request, long-context, and per-request concurrency rows into one average. This overstated or blurred the useful performance signal.
3. Concurrency results were per-request token/sec values only. They did not report aggregate system throughput across the parallel group.
4. The `if ! timeout ...; then rc=$?` Bash pattern lost the real curl/timeout exit code.
5. Parallel requests appended to `summary.csv` without an explicit lock. Usually it worked, but it was not robust enough for a diagnostic tool.
6. Monitor evidence was good but incomplete: no `nvidia-smi -q` snapshots, no `dmesg` GPU/error scan, and limited severity interpretation.
7. Busy-low-clock observations were too easy to overinterpret. They should remain observations unless paired with throttling or poor performance.
8. PCIe width below max was detected but not clearly elevated as a check condition.
9. RTX 3090 memory junction temperature can be unavailable in WSL2; this should be recorded as a coverage limitation.
10. There was no optional soak path for longer thermal/performance stability checks.
11. There was no optional larger-model VRAM pressure path.
12. Python helpers were mixed into top-level install guidance even though the main RTX3090 workflow does not require Python.
13. README was useful but not yet a first-class project document.

## v0.7 remediation summary

- Added deterministic long-prompt generation and context-fill metrics.
- Added classified summary categories: sanity, throughput, sustained, longctx, concurrency, cpu_reference, soak, and vram_pressure.
- Added warm single-request performance as the default headline.
- Added aggregate concurrency CSV.
- Fixed curl/timeout return-code capture.
- Added lock-protected CSV appends.
- Added optional soak and VRAM pressure probes.
- Added `nvidia-smi -q` snapshots and GPU-related `dmesg` scan.
- Added monitor verdicts and concise check/observation lines.
- Moved legacy Python helpers to `tools/legacy/`.
- Rewrote README.
