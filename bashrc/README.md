# Bash startup profile for RTX 3090 + Ollama

This directory contains a reviewed candidate `~/.bashrc` for the WSL2 workstation.

## Review of the uploaded `.bashrc`

Issues found:

1. `OLLAMA_NUM_CTX`, `OLLAMA_NUM_BATCH`, `OLLAMA_LOW_VRAM`, and `OLLAMA_NUM_GPU` were exported from `~/.bashrc`. If Ollama is started by `systemctl`, the service does not inherit these variables from an interactive shell. Put server-side Ollama variables in the `ollama.service` systemd override instead.
2. The startup status function called `ollama list` every time a terminal opened. That can be slow or noisy with a large model store.
3. The status function did not use timeouts. If the API or GPU query hangs, terminal startup can become unpleasant.
4. There was no short command alias for the new v1.0 model-pattern runner.

## What the packaged `.bashrc` changes

- Keeps your `crs` and `uz` aliases.
- Keeps NVM loading and `~/bin` path setup.
- Adds `OLLAMA_URL=http://127.0.0.1:11434` for package scripts.
- Removes Ollama server-tuning exports from the interactive shell.
- Adds fast startup status with one-second API/GPU timeouts.
- Does not run `ollama list` automatically on terminal open.
- Adds commands: `ollama_status`, `ollama_models`, `ollama_gpu`, `ollama_logs`, `ollama_test`.
- Adds aliases: `os`, `om`, `og`, `ol`, `ot`.

## Install

Back up your current profile first:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
```

## Disable startup status without editing the file

```bash
export OLLAMA_BASHRC_STATUS=0
```

Add that line above the startup-status block if you want it permanent.
