# Bash integration for ollama-info v1.8

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
ollama models          # local models + role-aware suggested bench commands
ollama bench qwen3.6 qwen3-embedding:4b # auto-route one or more models by role
ollama test qwen3.6:35b qwen3.6:27b # default empty-card ADOS capability tests
ollama embed-test bge-m3 qwen3-embedding:4b # embedding benchmark/monitor through /api/embed
ollama logs 200        # journalctl tail
ollama gpu             # nvidia-smi CSV snapshot
```

Normal upstream Ollama commands still pass through. The wrapper only intercepts package helpers including `status`, `models`, `bench`, `test`, and `embed-test`:

```bash
ollama list
ollama ps
ollama pull llama3.2
ollama run llama3.2
```


In v1.8 the bashrc functions delegate to `scripts/ollama.sh`; benchmark routing logic is not duplicated in `.bashrc`.
