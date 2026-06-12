# Bash integration for ollama-info v1.13

`bashrc/.bashrc` is an optional WSL2/Linux Bash snippet. It keeps Ollama server settings in systemd and only adds client-side wrappers.

## Install without overwriting your existing shell setup

From the `ollama-info` project root:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cat bashrc/.bashrc >> ~/.bashrc
source ~/.bashrc
hash -r
```

Set a non-default project location before sourcing, if needed:

```bash
export OLLAMA_INFO_HOME="$HOME/dev/ollama-info"
```

## Wrapper behavior

The `ollama()` wrapper intercepts only package subcommands:

```bash
ollama status
ollama models
ollama test qwen3:8b
ollama test --full qwen3:8b --min-context 65536
ollama context-test qwen3:8b --min-context 65536
ollama vision-test qwen2.5vl:7b --image /path/to/test-image.png
ollama embed-test bge-m3
ollama bench qwen3:8b bge-m3
ollama preload qwen3:8b --ctx 4096 --keep-alive 24h
```

Native Ollama commands pass through unchanged:

```bash
ollama list
ollama ps
ollama pull llama3.1:8b
ollama run llama3.1:8b
```

Disable the wrapper and keep only helper functions:

```bash
export OLLAMA_INFO_WRAP_CLI=0
```

Helper functions are also available: `ollama_test`, `ollama_context_test`, `ollama_vision_test`, `ollama_embed_test`, and their short aliases `ot`, `oct`, `ovt`, `oet`.
