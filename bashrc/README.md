# Bash integration for ollama-info

The Bash integration exposes `ollama-info` helper commands in an interactive shell while preserving native Ollama CLI passthrough behavior.

## Installation

Review the file before installing it:

```bash
less bashrc/.bashrc
```

Install it when acceptable:

```bash
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
```

## Wrapper behavior

The integration places common project paths on `PATH`, sets a default local `OLLAMA_URL`, and defines `ollama()` as a shell function when `OLLAMA_BASHRC_WRAP_CLI=1`.

Known commands are routed to `scripts/ollama.sh`:

```bash
ollama status
ollama models
ollama test MODEL
ollama bench MODEL
ollama embed-test MODEL
```

Unknown commands are passed through to the native Ollama CLI. This keeps normal Ollama commands available:

```bash
ollama run MODEL
ollama pull MODEL
ollama ps
```

## Helper aliases

| Alias | Function |
|---|---|
| `os` | status |
| `oq` | brief status |
| `ost` | start service |
| `osp` | stop service |
| `om` | list models |
| `og` | GPU telemetry |
| `ol` | logs |
| `ot` | generation test |
| `ob` | role-aware benchmark |
| `oet` | embedding test |

## Configuration flags

| Variable | Default | Meaning |
|---|---:|---|
| `OLLAMA_BASHRC_WRAP_CLI` | `1` | Wrap `ollama` with `ollama-info` while preserving native passthrough. |
| `OLLAMA_BASHRC_STATUS` | `1` | Print brief status once per interactive shell. |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Local Ollama API URL. |

Server tuning belongs in your Ollama service configuration, not in `.bashrc`.
