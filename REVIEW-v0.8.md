# REVIEW-v0.8

## Review summary

v0.8 adds `ollama-download.sh` as the package's large-model acquisition path for WSL2/Ollama users with unstable connections.

## Positive findings

- The script is idempotent for repeated runs against the same destination.
- `aria2` mode preserves partial download state and supports reconnect/resume semantics.
- `hf` mode is retained for authenticated Hugging Face workflows.
- `curl` fallback exists when neither `hf` nor `aria2c` is available.
- Authentication tokens are not placed in process argv for aria2/curl mode.
- Generated Modelfile uses an absolute GGUF path.
- The script logs metadata, download output, SHA256, warnings, and a final summary under `~/log/ollama-download/run-*`.

## Risk notes

- Hugging Face repository layout and gated access behavior are controlled by Hugging Face and the model publisher.
- Resume correctness ultimately depends on server-side HTTP Range support and the downloader's state files.
- Very large downloads require enough WSL2 ext4 disk space for both the local GGUF and Ollama's imported model storage.
- A failed checksum should be treated as authoritative; rerun with `--force` only when intentionally discarding the existing partial/full file.
