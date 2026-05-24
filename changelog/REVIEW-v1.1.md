# REVIEW v1.1

## Goal

Reduce terminal noise and make the RTX 3090 Ollama test runner safer for a systemd-managed Ollama setup.

## User-facing requirements

1. `ollama-test-and-monitor-RTX3090.sh qwen3.6` should still resolve the installed local model, for example `qwen3.6:35b`.
2. Running `ollama-test-and-monitor-RTX3090.sh` with no parameters should show a short screen only:
   - short usage;
   - Ollama status;
   - available local models;
   - copyable command lines to run those models;
   - pointer to `-h` for full options.
3. If the model is not found, the script should list available models and suggested command lines, not the full help screen.
4. Full help should be shown only with `-h` or `--help`.
5. Ollama status should be checked before tests. If the API is not running, no test should start; the script should print how to start Ollama.
6. `ollama-start`, `ollama-stop`, and `ollama-status` should be compatible with the current systemd-managed `ollama.service` setup.
7. The packaged `.bashrc` should remain client-side only: no Ollama server tuning exports if Ollama is run from `systemctl`.

## Changes made

- Added `ollama-common.sh` for shared model-resolution, status, systemd, and model-command helpers.
- Updated the orchestrator and direct RTX test scripts to v1.1 signatures.
- Added compact no-argument screens and compact error screens.
- Removed full-help dumps from no-argument, missing-model, ambiguous-model, unknown-option, and extra-argument paths.
- Added pre-run API gating. The scripts do not auto-start Ollama.
- Updated `ollama-start` to prefer system `ollama.service`, then user `ollama.service`, then a nohup fallback only if no service exists.
- Updated `ollama-stop` to use systemd when available and to use direct process killing only as fallback or with `KILL_ONLY=1`.
- Updated `ollama-status` with `--short`, `--brief`, `--models`, and `--full` modes.
- Updated `bashrc/.bashrc` to use `ollama-status --short`, preserve the short `ot qwen3.6` workflow, and avoid server-side environment exports.

## Non-goals

- No RTX 3090 benchmark results are claimed from the build environment.
- No changes were made to model generation payload semantics except pre-run gating and model selection/error presentation.
