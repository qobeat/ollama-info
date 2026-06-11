# REVIEW v1.8

## Review of new test results

### qwen3.6:27b direct v1.7.1 run, 20260611-141433

The run reported `PASS_WITH_WARNINGS`, full GPU residency, `Warm visible-answer 31.87 tok/s`, `FirstReqLoad 203.28s`, `FirstTTFT 203862.0 ms`, `WarmTTFT 388.1 ms`, and a valid long-context row with `6474 / 8192` prompt tokens and `30.33 tok/s`. This is the cleanest of the three new results for full-GPU generation behavior, but the first-request path is large and still only an observed residency condition unless a load mode clears resident models.

### qwen3.6:35b direct v1.7.1 run, 20260611-141928

The run reported `PASS_WITH_WARNINGS`, `Warm visible-answer 22.65 tok/s`, `FirstReqLoad 251.35s`, `LoadState=model_switch_observed`, `ColdVerified=0`, and `Residency: WARN cpu_gpu_offload (15%/85% CPU/GPU)`. The long-context row was `SHORT_SAMPLE`. This result is not directly comparable with a clean full-GPU-resident result because the prior qwen3.6:27b run was still resident and the tested model was partly offloaded.

### qwen3.6:35b monitored v1.7.1 run, 20260611-142622

The monitored run reported the model was resident before the test: `load_state=warm_or_resident_before`, `resident_before=present`, `resident_models_before=qwen3.6:35b`. It produced `single-request 21.83 tok/s`, `FirstReqLoad 15.49s`, `WarmTTFT 530ms`, CPU/GPU offload warning, VRAM max `23748 / 24576 MiB (96.6%)`, power-cap info samples, and no hardware slowdown. This is useful warm/resident telemetry, not an empty-card benchmark.

## Issues requiring v1.8 changes

1. Default `load_mode=observed` lets current residency influence default results.
2. The default workload remains performance-synthetic and does not directly test ADOS-style coding, essay, or internet-access-boundary behavior.
3. Multi-model command execution requires explicit support for fair sequential comparisons.
4. Bashrc and wrapper scripts duplicate routing/command behavior.
5. Working-directory-dependent script invocation created user friction.

## v1.8 repair decision

The repair path is in-frame and reversible: refactor wrappers, add empty-card mode, add ADOS profile, preserve legacy performance profile, and update evidence. No irreversible package finalization occurs before verification.
