# Review v1.2

## User-reported failures addressed

1. `ollama-start` reported `ollama.service not found` even though `systemctl status ollama` showed a loaded system service.
2. Direct `systemctl start ollama` failed for a non-root shell with `Interactive authentication required`.
3. `ollama-download.sh` required too many arguments for a common Hugging Face GGUF import.
4. The user wanted the `ollama-s*` helpers to stay compatible with a systemd-managed Ollama service.

## Root causes

- v1.1 service detection required PID 1 to be named `systemd` and used `systemctl list-unit-files`. The observed WSL setup can run `systemctl status ollama` successfully, so detection should trust `systemctl show/cat/status` instead of PID-name heuristics.
- `ollama-start` / `ollama-stop` called privileged system service actions without sudo handling.
- The downloader had a robust backend but no high-level one-source interface.

## v1.2 changes

- Added sudo-aware `ollama_systemctl_privileged` helper in `ollama-common.sh`.
- Reworked system service detection to use `systemctl show -p LoadState --value ollama.service`, with `systemctl cat`, `list-unit-files`, `list-units`, and parsed `status` fallbacks.
- Updated `ollama-start` and `ollama-stop` to call `sudo systemctl start|stop ollama.service` when non-root.
- Updated `ollama-status --brief` to show `load=... active=... enabled=...` for the system service.
- Updated packaged `.bashrc` fallback helpers for sudo-aware systemd start/stop and robust service detection.
- Added an optional `.bashrc` CLI wrapper so `ollama status` reaches the package helper instead of the upstream CLI error path.
- Reworked `ollama-download.sh` to support one positional source argument:
  - Hugging Face file URL;
  - `ORG/REPO/model.gguf` shorthand;
  - local GGUF path.
- Added automatic inference of local model name and default `PARAMETER num_ctx 8192` in one-argument downloader mode.
- Added completed-file skip logic for resumed downloads.

## Compatibility notes

The explicit downloader form still works:

```bash
ollama-download.sh --repo REPO_ID --file MODEL.gguf --name local-model
```

The simplified form is now preferred:

```bash
ollama-download.sh --method aria2 'ORG/REPO-GGUF/MODEL.gguf'
```


## Additional .bashrc correction

The user also observed that `ollama status` called the upstream Ollama CLI and failed with `unknown command "status"`. v1.2 adds an interactive shell wrapper that maps `ollama status` to package status helpers while preserving normal pass-through behavior for standard Ollama commands.
