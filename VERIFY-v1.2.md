# Verify v1.2

Validation performed in the package workspace.

## Static checks

```text
bash -n ollama-common.sh
bash -n ollama-start
bash -n ollama-stop
bash -n ollama-status
bash -n ollama-download.sh
bash -n ollama-test-RTX3090.sh
bash -n ollama-test-and-monitor-RTX3090.sh
bash -n ollama-monitor.sh
bash -n bashrc/.bashrc
```

All syntax checks passed.

## Systemd/sudo behavior checks

Used fake `systemctl`, `sudo`, `curl`, and `nvidia-smi` commands to simulate the observed WSL service layout.

Verified:

```text
ollama-status --brief detects system ollama.service with load=loaded.
service detection still works when `systemctl show` reports not-found but `systemctl status` shows a loaded service.
common detector succeeds when only `systemctl status ollama` exposes the loaded unit.
ollama-start calls sudo systemctl start ollama.service for a non-root caller.
ollama-stop calls sudo systemctl stop ollama.service for a non-root caller.
ollama-start reports API RUNNING after the fake service starts.
packaged .bashrc defines `ollama status` wrapper and passes ordinary CLI calls through.
```

## Downloader checks

Verified dry-run source inference:

```bash
ollama-download.sh --method aria2 --dry-run \
  'https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf?download=true'
```

Expected inferred fields were produced:

```text
repo:        unsloth/Qwen3.6-35B-A3B-GGUF
file:        Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
model:       qwen3.6-35b-a3b-ud-q4km
params:      num_ctx=8192
method:      aria2
```

Verified shorthand source inference:

```bash
ollama-download.sh --method aria2 --dry-run \
  'unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf'
```

Verified a fake `aria2c` transfer path:

```text
fake aria2c created a GGUF file
ollama create was called with qwen3.6-35b-a3b-ud-q4km
generated Modelfile contained PARAMETER num_ctx 8192
summary and SHA256 output were created
```

## Limits

A real RTX 3090 benchmark and a real multi-GB Hugging Face download were not run in this environment. The validation used syntax checks and deterministic fake command shims for systemd, sudo, aria2, curl, and ollama.


## Additional bashrc checks

Verified with a sourced packaged `.bashrc` and fake command shims:

```text
ollama status dispatches to ollama_status instead of the upstream CLI error path.
ollama start dispatches to sudo-aware ollama_start.
normal commands such as ollama list still pass through to the real Ollama CLI.
.bashrc fallback service detection succeeds when systemctl status reports Loaded: loaded.
```
