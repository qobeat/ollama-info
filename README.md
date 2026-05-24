# ollama-info v1.4

Production-oriented RTX 3090 + WSL2 + Ollama diagnostics package.

`ollama-info` provides a small shell-tooling layer around Ollama, NVIDIA telemetry, and systemd so a local workstation can answer three operational questions quickly:

1. **Is Ollama running correctly?**
2. **Is the requested model actually available and loadable?**
3. **Is the RTX 3090 healthy and performing normally under a controlled Ollama workload?**

The primary command is intentionally short:

```bash
ollama test qwen3.6
```

That command resolves the local model matching `qwen3.6`, runs the safe RTX 3090 baseline, monitors GPU/Ollama telemetry in parallel, writes raw evidence to a timestamped run directory, and creates a zip archive for sharing/debugging.

---

## Current status

This is the first production-style README for the package. The scripts have evolved through multiple diagnostic iterations and are now organized as follows:

```text
ollama-info/
  README.md
  PACKAGE-MANIFEST.txt
  bashrc/
    .bashrc
    README.md
  scripts/
    ollama-common.sh
    ollama-status
    ollama-start
    ollama-stop
    ollama-test-and-monitor-RTX3090.sh
    ollama-test-RTX3090.sh
    ollama-monitor.sh
    ollama-download.sh
    ollama-gen
    ollama-perf
    ollama-perf-table
    legacy/
  changelog/
    CHANGELOG.md
    REVIEW-*.md
    VERIFY-*.md
    REFLECTION-*.md
```

### Production readiness by script

| Script | Status | Purpose |
|---|---:|---|
| `scripts/ollama-test-and-monitor-RTX3090.sh` | Primary / production | Orchestrates test + monitor + NVIDIA boundary snapshots + archive. Use this for normal benchmark runs. |
| `scripts/ollama-test-RTX3090.sh` | Production engine | Runs deterministic Ollama API test requests, captures raw JSON/payloads/CSV/summary, classifies failures. Usually invoked by the orchestrator. |
| `scripts/ollama-monitor.sh` | Production monitor | Samples GPU, PCIe, power, VRAM, clocks, throttling, Ollama process/model state, and writes CSV/report artifacts. |
| `scripts/ollama-status` | Production helper | Reports systemd service state, API status, GPU quick state, models, logs, disk usage, and loaded runners. |
| `scripts/ollama-start` | Production helper | Starts system `ollama.service` with sudo when needed; falls back only when no service exists. |
| `scripts/ollama-stop` | Production helper | Stops system `ollama.service` with sudo when needed; has optional direct process-kill fallback. |
| `scripts/ollama-download.sh` | Production utility | Downloads GGUF models from Hugging Face or local source, optionally through `aria2c`, creates an Ollama Modelfile/model. |
| `scripts/ollama-common.sh` | Internal shared library | Shared model resolution, status, systemd, API, and command-printing functions. Source only; do not run directly. |
| `scripts/ollama-gen` | Utility | General Ollama generation helper retained for convenience. |
| `scripts/ollama-perf` / `scripts/ollama-perf-table` | Legacy-compatible utilities | Older performance helpers retained for ad-hoc comparison and backwards compatibility. |
| `scripts/legacy/*` | Archived | Historical Python calculators retained for reference. New workflows should prefer the shell scripts above. |

---

## Quick start

From the package directory:

```bash
cd ~/dev/ollama-info
chmod +x scripts/ollama-*
```

Optional but recommended shell integration:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
hash -r
```

Check the setup:

```bash
ollama status
ollama models
```

Run the normal RTX 3090 baseline:

```bash
ollama test qwen3.6
```

Run without the `.bashrc` wrapper:

```bash
./scripts/ollama-test-and-monitor-RTX3090.sh qwen3.6
```

---

## Requirements

Core runtime:

```text
Bash 4+
curl
jq
awk / sed / grep
zip / unzip
Ollama CLI and reachable Ollama API
NVIDIA driver exposed to WSL2 with nvidia-smi available
systemd, for the recommended Ollama service setup
```

Optional utilities:

```text
aria2c      faster/resumable GGUF downloads
journalctl  richer service-log capture
timeout     safer command time limits
```

Full help is intentionally not printed during normal discovery/error cases. Use `-h` or `--help` explicitly:

```bash
ollama-test-and-monitor-RTX3090.sh -h
ollama-test-RTX3090.sh -h
ollama-download.sh -h
ollama-status --help
```

---

## Why `ollama test qwen3.6` no longer needs extra flags

Earlier recommendations used:

```bash
ollama test qwen3.6 --no-conc --concurrency 1
```

That was a conservative first-run command after a prior model-load failure and while concurrency was still enabled by default.

In v1.4, the default baseline is already the safe mode:

```text
RUN_CONC=0
CONCURRENCY=1
```

So the normal command is now:

```bash
ollama test qwen3.6
```

Use concurrency only when you explicitly want a stress probe:

```bash
ollama test qwen3.6 --run-conc --concurrency 2
```

Or the shorthand:

```bash
ollama test qwen3.6 --stress
```

For a 24 GB RTX 3090 running a large Qwen-class model, this default matters. The previous successful `qwen3.6:27b` run reached very high VRAM occupancy. Concurrency should therefore be an explicit stress test, not the baseline path.

---

## Command behavior

### No parameters

```bash
ollama-test-and-monitor-RTX3090.sh
```

Shows a compact operational screen:

```text
short usage
Ollama status
available local models
command line for each model
pointer to -h / --help
```

It does not print the full help.

### Model pattern resolution

```bash
ollama-test-and-monitor-RTX3090.sh qwen3.6
```

The script queries local Ollama tags from `/api/tags` and resolves the model pattern in this order:

1. exact full model name, for example `qwen3.6:27b`;
2. exact base name before `:`, for example `qwen3.6`;
3. unique case-insensitive substring match.

If the model is missing, it lists available local models and suggested commands. It does not dump full help.

If the pattern is ambiguous, it lists only the matching models and exact commands.

### Ollama status gating

Before any test run, the orchestrator checks:

```text
systemd service state
Ollama API reachability
GPU quick state through nvidia-smi
```

If the API is not reachable, tests are not run. The script prints the appropriate start/check/log commands, preferring systemd when `ollama.service` exists:

```bash
sudo systemctl start ollama
systemctl status ollama --no-pager
journalctl -u ollama -n 120 --no-pager
```

---

## Bash integration

`bashrc/.bashrc` adds `~/dev/ollama-info/scripts` to `PATH` and wraps a few convenience subcommands while preserving normal Ollama CLI behavior.

Package helper commands:

```bash
ollama status          # package status helper
ollama start           # sudo-aware systemctl start ollama.service
ollama stop            # sudo-aware systemctl stop ollama.service
ollama models          # local models + `ollama test <model>` commands
ollama test qwen3.6    # primary benchmark workflow
ollama logs 200        # journalctl tail
ollama gpu             # nvidia-smi CSV snapshot
```

Normal upstream Ollama commands still pass through:

```bash
ollama list
ollama ps
ollama pull llama3.2
ollama run llama3.2
ollama serve
```

Important: upstream Ollama does not provide a native `ollama status` subcommand in your installed CLI. This package adds `ollama status` as a Bash wrapper convenience.

If the wrapper still shows an old script version, refresh the shell command cache and inspect path order:

```bash
hash -r
type -a ollama-test-and-monitor-RTX3090.sh
type -a ollama-status
type ollama
```

---

## Systemd and Ollama service model

This package assumes the preferred production setup is systemd-managed Ollama:

```bash
sudo systemctl start ollama
sudo systemctl stop ollama
systemctl status ollama --no-pager
journalctl -u ollama -n 120 --no-pager
```

`ollama-start` and `ollama-stop` are sudo-aware. When a non-root user needs to start/stop the system service, they call `sudo -v` and then run the systemctl command so the normal password prompt appears.

Server-side Ollama environment variables should live in a systemd override, not `.bashrc`, because a system service does not inherit interactive shell variables.

Example override path:

```bash
sudo systemctl edit ollama
```

Typical conservative service settings for a single RTX 3090 baseline:

```ini
[Service]
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_FLASH_ATTENTION=1"
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## Test architecture

### High-level flow

```text
user command
  -> bash wrapper, optional
  -> ollama-test-and-monitor-RTX3090.sh
      -> preflight status/model/API checks
      -> start ollama-monitor.sh in background
      -> capture start nvidia-smi snapshots
      -> run ollama-test-RTX3090.sh
      -> stop monitor
      -> capture end nvidia-smi snapshots
      -> build orchestrator summary
      -> zip full run directory
```

### Default baseline tests

The default v1.4 baseline runs four GPU API tests:

| Test | Purpose |
|---|---|
| `01_sanity_gpu` | Confirms the model loads and generates visible output. |
| `02_throughput_gpu` | Measures normal short-context generation throughput. |
| `03_sustained_gpu` | Measures longer generation stability and throughput. |
| `04_longctx_gpu` | Measures long-context prompt ingestion and generation. |

Default parameters:

```text
num_ctx=4096
long_ctx=8192
num_predict=512
long_num_predict=1024
long_prompt_words=3200
think=false
run_conc=0
concurrency=1
monitor_profile=deep
interval=1s
```

Optional probes:

```bash
ollama test qwen3.6 --run-conc --concurrency 2
ollama test qwen3.6 --stress
ollama test qwen3.6 --soak-minutes 10
ollama test qwen3.6 --run-vram-pressure --vram-model larger-model:tag
```

### Why concurrency is no longer default

Large Qwen-class models can occupy most of the 24 GB VRAM on an RTX 3090 at 8K context. Running a concurrency probe by default can turn a clean health baseline into a VRAM-pressure test. v1.4 separates those modes:

```text
baseline = single request, stable health/performance signal
stress   = concurrency / soak / VRAM pressure probes explicitly requested
```

---

## Monitoring and collected evidence

Each orchestrated run writes artifacts under:

```text
~/log/ollama-test-and-monitor-RTX3090/run-YYYYMMDD-HHMMSS/
```

Key files:

```text
orchestrator-summary.md
terminal-summary.txt
errors.log
hardware/
  nvidia-smi-start.txt
  nvidia-smi-end.txt
  nvidia-smi-q-start.txt
  nvidia-smi-q-end.txt
  nvidia-smi-query-start.csv
  nvidia-smi-query-end.csv
  nvidia-compute-apps-start.csv
  nvidia-compute-apps-end.csv
monitor/
  run-*-monitor/report.md
  run-*-monitor/samples.csv
test/
  run-*-test/summary.md
  run-*-test/summary.csv
  run-*-test/failure-hints.txt
  run-*-test/raw/*.json
  run-*-test/raw/*.stderr
  run-*-test/payloads/*.json
  run-*-test/ollama-server-log-tail.txt
```

A zip archive is also written under:

```text
~/tmp/ollama-test-and-monitor-RTX3090-YYYYMMDD-HHMMSS.zip
```

### Timestamped logs

Operational console lines from the orchestrator, test runner, and monitor begin with ISO timestamps. This makes copied terminal output suitable for later incident review.

### NVIDIA boundary snapshots

The orchestrator captures `nvidia-smi` at both the beginning and end of each full run. These snapshots complement the continuous monitor CSV by preserving readable boundary evidence:

```text
driver/CUDA version reported by nvidia-smi
GPU name
PCIe link state
power draw/limit
temperature
clocks
P-state
VRAM used/free/total
active compute processes
```

---

## Reading results

A successful baseline should show:

```text
Test    : PASS
Output  : visible rows N/N; thinking-only 0; errors 0
LongCtx : ... OK
Health  : PASS or PASS_WITH_CHECKS
```

`PASS_WITH_CHECKS` does not necessarily mean the model test failed. It means the hardware monitor observed something worth reviewing, such as high VRAM occupancy, power-limit behavior, PCIe width, or unavailable memory temperature telemetry.

Common result interpretation:

| Signal | Meaning |
|---|---|
| `Test: PASS` | Ollama API requests completed and generated output. |
| `Error: class=model_load_error` | Ollama API returned a load failure. Inspect model blob/store and server logs. |
| `Health: PASS_WITH_CHECKS` | GPU ran but one or more monitor thresholds deserve attention. |
| `VRAM high` | Model/context approached RTX 3090 memory capacity. Treat concurrency as stress-only. |
| `PCIe width x8 / max x16` | Often expected in some motherboard slot configurations, but worth checking when GPU is busy. |
| `sw_power > 0` | GPU hit software power limit; common under heavy load, usually not a test failure by itself. |

---

## Downloader

The downloader now supports one source argument. Keep `--method aria2` only when you explicitly want aria2:

```bash
./scripts/ollama-download.sh --method aria2 \
  'unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf'
```

Equivalent Hugging Face URL form:

```bash
./scripts/ollama-download.sh --method aria2 \
  'https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf?download=true'
```

The script infers:

```text
repo
file
local GGUF path
Ollama model name
Modelfile
num_ctx=8192 by default
```

Override only when needed:

```bash
./scripts/ollama-download.sh --method aria2 \
  'unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf' \
  --name qwen3.6:35b \
  --num-ctx 8192
```

---

## Troubleshooting

### `ollama status` says service not found, but `systemctl status ollama` works

This usually means the shell is still using an older package helper.

Run:

```bash
hash -r
type -a ollama-status
type -a ollama-test-and-monitor-RTX3090.sh
source ~/.bashrc
ollama status
```

If needed, reinstall the packaged `.bashrc` and verify `~/dev/ollama-info/scripts` appears before older paths in `PATH`.

### `ollama status` returns `unknown command "status"`

That is the upstream Ollama CLI, not this package wrapper. Install/source `bashrc/.bashrc`, or call the helper directly:

```bash
./scripts/ollama-status --full
```

### Ollama API is not reachable

Start the system service:

```bash
sudo systemctl start ollama
systemctl status ollama --no-pager
curl -fsS http://127.0.0.1:11434/api/version && echo
```

### Model pattern is not found

List local models and use one of the suggested commands:

```bash
ollama models
ollama test qwen3.6:27b
```

### The model fails to load with HTTP 500

The test runner preserves the response body and classifies likely load failures. Inspect:

```text
test/run-*-test/failure-hints.txt
test/run-*-test/raw/*.json
test/run-*-test/raw/*.stderr
test/run-*-test/ollama-server-log-tail.txt
```

Typical next actions:

```bash
ollama show MODEL
ollama rm MODEL
ollama pull MODEL
```

For custom GGUF imports, recreate the model from the Modelfile.

---

## Version highlights

| Version | Main change |
|---|---|
| v1.4 | Production README, safe default baseline, `--stress` shorthand, model command UX cleanup. |
| v1.3 | Timestamped operational logs, fixed false API-error classification, NVIDIA start/end snapshots, `scripts/` + `changelog/` layout. |
| v1.2 | Sudo-aware systemd start/stop helpers, improved `.bashrc`, simplified one-argument downloader. |
| v1.1 | Short no-arg screen, status-gated tests, compact missing-model behavior. |
| v1.0 | Short model-pattern command and automatic local model resolution. |
| v0.9 | Model-load failure triage and richer WSL/Ollama/server evidence capture. |

Full notes are in `changelog/`.

---

## Design principles

1. **Do not hide raw evidence.** Summaries are generated from saved raw responses, CSVs, and logs.
2. **Do not run destructive/stress probes by default.** Concurrency, soak, CPU comparison, and VRAM pressure are explicit.
3. **Prefer systemd for Ollama lifecycle.** Shell variables are client-side only; service variables belong in systemd overrides.
4. **Make failure modes actionable.** Missing model, ambiguous model, API down, and model-load errors each produce targeted next commands.
5. **Keep the default command short.** Normal operation should be `ollama test qwen3.6`.
