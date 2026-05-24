# Bash integration for ollama-info

`bashrc/.bashrc` is an optional WSL2-oriented interactive Bash configuration.
It assumes Ollama is managed by `systemd` and keeps server-side Ollama settings out of the shell.

Install:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
hash -r
```

Provided convenience commands:

```bash
ollama status          # package status helper, not upstream Ollama CLI
ollama start           # sudo-aware systemctl start ollama.service
ollama stop            # sudo-aware systemctl stop ollama.service
ollama models          # local models + `ollama test <model>` commands
ollama test qwen3.6    # benchmark/monitor with safe defaults
ollama logs 200        # journalctl tail
ollama gpu             # nvidia-smi CSV snapshot
```

Normal upstream Ollama commands still pass through:

```bash
ollama list
ollama ps
ollama pull llama3.2
ollama run llama3.2
```
