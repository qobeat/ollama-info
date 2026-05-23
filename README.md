# ollama-monitor.sh

WSL2 NVIDIA/Ollama telemetry collector and Markdown report generator.

## Install

```bash
mkdir -p ~/bin
cp ollama-monitor.sh ~/bin/ollama-monitor.sh
chmod +x ~/bin/ollama-monitor.sh
```

## Run

```bash
ollama-monitor.sh --interval 1 --profile deep
```

Stop with Ctrl+C. The report is written under `~/log/ollama-monitor/run-*/report.md`.

## Built-in benchmark

```bash
ollama-monitor.sh --interval 1 --duration 180 --model-test qwen3:8b --num-predict 512
```

## Self-test

```bash
ollama-monitor.sh --self-test
```
