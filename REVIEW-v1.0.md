# REVIEW v1.0

## Goal

Make the RTX 3090 Ollama test package easier to run daily while preserving diagnostic value.

## Requirements reviewed

1. Replace long command-line baseline with short model-pattern command.
2. Resolve a local Ollama model from a partial pattern such as `qwen3.6`.
3. With no model argument, list available models and print help.
4. With no matching or ambiguous model pattern, list available/matching models and print help.
5. Preserve existing non-default tuning flags for advanced runs.
6. Review and package the uploaded `.bashrc` for a systemd-managed Ollama service.

## Findings

- The previous default `MODEL=qwen3:8b` was convenient but dangerous for diagnostics because a no-argument run could test the wrong model.
- The user's common workflow needs `ollama-test-and-monitor-RTX3090.sh qwen3.6` to resolve to the installed tag, for example `qwen3.6:35b`.
- The uploaded `.bashrc` put Ollama server variables in the interactive shell. With `systemctl` managing Ollama, those variables do not tune the service.
- The uploaded `.bashrc` ran `ollama list` on every terminal open, which can add avoidable latency.

## Implemented design

- Added a local model resolver to both RTX test scripts.
- Resolution order: exact full tag, exact base tag before `:`, unique case-insensitive substring.
- Missing and ambiguous patterns stop before running monitor/test workload.
- Added `bashrc/.bashrc` with fast one-second startup checks and full-status commands for manual use.

## Related helper review

- `ollama-start` now prefers `systemctl start ollama` when `ollama.service` exists.
- `ollama-stop` now prefers `systemctl stop ollama` and keeps direct process kill as `KILL_ONLY=1` fallback.
- `ollama-status` now shows systemd service state before API/model/GPU sections.
