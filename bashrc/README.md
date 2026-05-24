# Bash integration

This `.bashrc` is intended for WSL2 with Ollama managed by systemd.

It prepends:

```bash
$HOME/dev/ollama-info/scripts
$HOME/dev/ollama-info
$HOME/bin
```

It adds shell-only helpers:

```bash
ollama status
ollama start
ollama stop
ollama models
ollama logs
ollama gpu
ollama test qwen3.6
```

Normal upstream commands still pass through:

```bash
ollama list
ollama pull ...
ollama run ...
ollama ps
```

Server-side Ollama configuration belongs in `ollama.service` overrides, not in `.bashrc`.
