# Quality evidence summary v1.7.1

## Scope

Targeted maintenance release produced after reviewing user-provided v1.7 console output and result archives.

## Fixed serious issues

1. Corrected observed load-state semantics: observed mode no longer claims verified cold merely from tested-model absence.
2. Added detection of other resident models before a run and classification as `model_switch_observed`.
3. Added post-run Ollama residency/offload classification from `ollama ps`.
4. Removed misleading `single GPU` label from orchestrator throughput when full-GPU residency is not established.
5. Split TTFT reporting into FirstTTFT, WarmTTFT, and TTFTall.
6. Added monitor report section for Ollama residency/offload state.

## Verification status

- PASS: shell syntax validation.
- PASS: deterministic direct-test load-state/offload verification.
- PASS: deterministic orchestrator/offload-report verification.
- PASS: archive hygiene validation.

## Evidence caveat

The qwen3.6:27b and qwen3.6:35b performance numbers in the final user-facing analysis are from the user-provided real test archives. The v1.7.1 code changes were verified with deterministic shims because this environment cannot run the user's RTX 3090/Ollama stack.
