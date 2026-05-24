# VERIFY v1.1

## Static checks

```text
bash -n ollama-common.sh
bash -n ollama-start
bash -n ollama-stop
bash -n ollama-status
bash -n ollama-test-RTX3090.sh
bash -n ollama-test-and-monitor-RTX3090.sh
bash -n ollama-monitor.sh
bash -n ollama-download.sh
bash -n bashrc/.bashrc
```

Result: PASS.

## Behavioral checks with fake Ollama server

A local fake Ollama server exposed:

- `/api/version`
- `/api/tags`
- `/api/ps`
- `/api/show`
- `/api/generate`

Local fake models:

```text
gemma3:1b
qwen2.5-coder:7b
qwen3.6:35b
```

### No-argument screen

Command:

```bash
BASE_URL=http://127.0.0.1:18082 ./ollama-test-and-monitor-RTX3090.sh
```

Result: PASS.

Observed:

- exit code `2`;
- 16 output lines;
- short usage only;
- Ollama status shown;
- model run commands shown;
- no `Core options` full-help block.

### Missing model

Command:

```bash
BASE_URL=http://127.0.0.1:18082 ./ollama-test-and-monitor-RTX3090.sh missing-model
```

Result: PASS.

Observed:

- exit code `4`;
- available models shown with command lines;
- no full-help block;
- no monitor/test workload started.

### Ambiguous model

Command:

```bash
BASE_URL=http://127.0.0.1:18082 ./ollama-test-and-monitor-RTX3090.sh qwen
```

Result: PASS.

Observed:

- exit code `5`;
- matching models shown with exact command lines;
- no full-help block;
- no monitor/test workload started.

### Ollama API down

Command:

```bash
BASE_URL=http://127.0.0.1:18999 ./ollama-test-and-monitor-RTX3090.sh qwen3.6
```

Result: PASS.

Observed:

- exit code `3`;
- compact status says API is not running;
- test not started;
- start/check hint printed.

### Direct RTX test model resolution

Command:

```bash
BASE_URL=http://127.0.0.1:18081 ./ollama-test-RTX3090.sh qwen3.6 --no-conc --no-zip --no-terminal-summary --no-wsl-diagnostics --num-predict 1 --long-num-predict 1 --long-prompt-words 64 --timeout-sec 5
```

Result: PASS.

Observed:

- `qwen3.6` resolved to `qwen3.6:35b`;
- fake `/api/generate` calls completed;
- summary and CSV were produced.

### Helper commands

Commands:

```bash
BASE_URL=http://127.0.0.1:18083 ./ollama-status --short
BASE_URL=http://127.0.0.1:18083 ./ollama-status --models
```

Result: PASS.

Observed:

- compact service/API/GPU status printed;
- local model commands printed.

## Archive check

```text
zip -qr /mnt/data/ollama-info-v1.1.zip ollama-info
unzip -t /mnt/data/ollama-info-v1.1.zip
```

Result: PASS.
