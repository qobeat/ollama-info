# ollama-info v1.1

WSL2 + Ollama + NVIDIA RTX 3090 health, performance, and resumable GGUF download toolkit.

`ollama-info` is a Bash-first diagnostic package for a Windows 11 + WSL2 workstation running local LLMs through Ollama on an RTX 3090 24 GB GPU. It runs controlled Ollama API tests, captures NVIDIA telemetry in parallel, preserves raw evidence for later troubleshooting, produces compact terminal summaries that are safe to paste into a standard ASCII terminal or chat, and includes a resumable GGUF downloader/importer for unstable WSL2 network connections.

The primary RTX validation workflow is:

```text
start monitor -> run Ollama RTX3090 tests -> stop monitor -> summarize -> zip one complete run directory in ~/tmp
```

## Contents

- [What changed in v1.1](#what-changed-in-v11)
- [What changed in v1.0](#what-changed-in-v10)
- [RTX 3090 + WSL2 setup recommendations](#rtx-3090--wsl2-setup-recommendations)
- [What this package can and cannot prove](#what-this-package-can-and-cannot-prove)
- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Resumable GGUF download and Ollama import](#resumable-gguf-download-and-ollama-import)
- [Command reference](#command-reference)
- [Output structure](#output-structure)
- [How to interpret results](#how-to-interpret-results)
- [Troubleshooting findings](#troubleshooting-findings)
- [Retention guidance](#retention-guidance)
- [Legacy tools and Python](#legacy-tools-and-python)
- [Safety](#safety)
- [Validation and development notes](#validation-and-development-notes)

## What changed in v1.1

v1.1 reduces terminal noise and makes the runner safer for a systemd-managed Ollama setup.

New in v1.1:

- Running `ollama-test-and-monitor-RTX3090.sh` with no parameters now shows a compact screen only: short usage, Ollama service/API/GPU status, and local model run commands.
- Full help is shown only with `-h` or `--help`.
- If a requested model pattern is not found, the script lists available local models and copyable command lines instead of printing the full help screen.
- If a requested model pattern is ambiguous, the script lists matching model names with exact command lines.
- The orchestrator and direct RTX test always check Ollama API status before testing. They do not auto-start Ollama; if the API is down, they stop and print the relevant `systemctl start ollama` command.
- Added shared `ollama-common.sh` helpers for model resolution, compact status, systemd detection, and model command printing.
- Updated `ollama-start`, `ollama-stop`, and `ollama-status` for the current setup where Ollama runs from `ollama.service`.
- `ollama-status --brief` / `--short` gives compact service/API/GPU status; `ollama-status --models` lists local models with benchmark commands.
- Updated the packaged `.bashrc` to use `ollama-status --short`, systemd-compatible start/stop helpers, and no server-side Ollama tuning exports.

### Default/no-argument behavior

```bash
ollama-test-and-monitor-RTX3090.sh
```

prints a compact launcher like:

```text
Usage: ollama-test-and-monitor-RTX3090.sh <model-pattern> [options]
Ollama status: ...
Available local Ollama models:
  - qwen3.6:35b  ->  ollama-test-and-monitor-RTX3090.sh qwen3.6:35b
Use -h for full options.
```

### Ollama-down behavior

If the API is not reachable, tests are not started. The script prints the start command for the detected setup, for example:

```bash
systemctl start ollama
systemctl status ollama --no-pager
```

If permission is denied on the system service, use:

```bash
sudo systemctl start ollama
```

## What changed in v1.0

v1.0 makes the RTX 3090 test runner usable as a short daily command and adds a reviewed WSL2 Bash startup profile.

New in v1.0:

- `ollama-test-and-monitor-RTX3090.sh qwen3.6` now resolves `qwen3.6` against locally available Ollama model names, for example `qwen3.6:35b`.
- The same model-pattern selector was added to `ollama-test-RTX3090.sh` for direct test runs.
- With no model argument, the scripts list available local models and print the help screen instead of silently using an old default model.
- If a pattern is missing or ambiguous, the scripts show the matching/available models and stop before launching the monitor or test workload.
- The default RTX 3090 baseline remains: deep monitor profile, 1 second interval, 4096 standard context, 8192 long context, 512 standard generation tokens, 1024 sustained generation tokens, 3200-word long prompt, concurrency probe enabled at 2, CPU probe disabled, VRAM-pressure probe disabled, and `think=false`.
- Added `bashrc/.bashrc`, a reviewed candidate profile for WSL2 where Ollama is managed by systemd.
- Added `bashrc/README.md` with the review of the uploaded `.bashrc` and install instructions.
- Updated `ollama-start`, `ollama-stop`, and `ollama-status` to prefer systemd-managed `ollama.service` when available, with nohup/pkill fallback only when systemd service is absent.

### New short command

```bash
ollama-test-and-monitor-RTX3090.sh qwen3.6
```

Resolution rules:

1. Exact full local model name, such as `qwen3.6:35b`.
2. Exact base name before `:`, such as `qwen3.6` matching `qwen3.6:35b`.
3. Unique case-insensitive substring match.
4. If no match or multiple matches exist, list matching/available model run commands. Full help is shown only with `-h`.

Examples:

```bash
# Recommended baseline after a large model pull/rebuild
ollama-test-and-monitor-RTX3090.sh qwen3.6

# Conservative diagnostic run without concurrency
ollama-test-and-monitor-RTX3090.sh qwen3.6 --no-conc

# Explicit exact model still works
ollama-test-and-monitor-RTX3090.sh --model qwen3.6:35b --long-ctx 8192
```

### Systemd-managed Ollama helpers

For your intended setup, Ollama should be configured in `ollama.service`, not tuned through `~/.bashrc`. v1.1 keeps the helpers aligned with that setup:

```bash
ollama-start          # prefers systemctl start ollama; prints short status
ollama-status          # compact systemd/API/GPU status
ollama-status --brief  # same compact status, explicit
ollama-status --models # local model names with benchmark commands
ollama-status --full   # full diagnostic status
ollama-stop           # prefers systemctl stop ollama; set KILL_ONLY=1 for direct pkill fallback
```

The packaged Bash profile exposes `ollama_test qwen3.6` / alias `ot qwen3.6` for the short benchmark command.

## What changed in v0.9

v0.9 is a failure-aware RTX 3090/Ollama test release. It was driven by a real failed run where every `/api/generate` request returned HTTP 500 and the terminal summary hid the useful API error body.

New in v0.9:

- Upgraded `ollama-test-RTX3090.sh`, `ollama-monitor.sh`, and `ollama-test-and-monitor-RTX3090.sh` to v0.9 signatures.
- Preserved HTTP status and Ollama API error bodies instead of reducing HTTP 500 to `curl_failed_rc_22`.
- Added `http_code`, `error_class`, and `error_body` columns to `summary.csv`.
- Added `failure-hints.txt`, including referenced model blob path, likely cause, next action, model size GiB, and pre-run free VRAM when available.
- Added preflight evidence: `/api/version`, `/api/tags`, `/api/show`, `ollama show`, `ollama list`, WSL diagnostics, and Ollama server log tail.
- Added `--server-log-lines`, `--wsl-diagnostics`, and `--no-wsl-diagnostics` options.
- Made terminal summaries explicitly mark inference health as `INCONCLUSIVE` when no valid tokens were produced.
- Made `ollama-monitor.sh` report whether a loaded Ollama model was actually observed; monitor-only `Health: PASS` is no longer easy to misread as a completed inference benchmark.
- Kept the v0.8 resumable GGUF download/import path unchanged.

Historical v0.8 additions retained in this package:

- `ollama-download.sh`: resumable GGUF download utility with `hf`, `aria2`, and `curl` methods.
- Automatic retry loops around failed transfer attempts; `--max-tries 0` means retry until success or user interruption.
- Explicit aria2 resume support using `--continue=true` and persistent `.aria2` state.
- Direct Hugging Face repo/file support: `--repo`, `--file`, and `--revision`.
- Private/gated Hugging Face support through `hf auth login`, `HF_TOKEN`, or `HUGGING_FACE_HUB_TOKEN`.
- Local GGUF verification, optional `--sha256`, generated `Modelfile`, and `ollama create` import.

## What this package can and cannot prove

### It can prove

- Ollama API reachability.
- Whether the tested model runs and returns valid JSON.
- Whether the tested model produces visible response text or only `thinking` output.
- Whether the model appears loaded on GPU via `ollama ps` / `/api/ps` snapshots.
- Warm single-request generation throughput.
- Prompt-evaluation and generation token rates from Ollama API durations.
- RTX 3090 telemetry during the run: utilization, VRAM, temperature, power, clocks, PCIe link width/gen, throttle flags when exposed by `nvidia-smi`.
- Evidence useful for later troubleshooting: raw payloads, raw responses, GPU CSV, process snapshots, `nvidia-smi -q`, and `dmesg` GPU/error scan.

### It cannot fully prove by default

- Full 24 GB VRAM stability. `qwen3:8b` uses only a fraction of RTX 3090 VRAM.
- 30+ minute thermal stability unless you run `--soak-minutes`.
- Larger-model behavior unless you run a larger model with `--run-vram-pressure --vram-model ...`.
- Windows-side driver or Event Viewer errors. The package runs inside WSL2 and captures Linux/WSL-visible signals.
- Memory junction temperature if WSL2 `nvidia-smi` reports it as `N/A`.

## Requirements

Main RTX3090 workflow dependencies:

```bash
sudo apt update
sudo apt install -y bash curl jq zip procps coreutils gawk grep sed findutils
```

Recommended resumable downloader dependencies:

```bash
sudo apt update
sudo apt install -y aria2 curl python3 python3-pip coreutils
python3 -m pip install --user -U huggingface_hub
```

Notes:

- `aria2` gives the clearest resume semantics for very large public GGUF files.
- `hf` / `huggingface-cli` is recommended for gated/private Hugging Face repos after `hf auth login`.
- `curl` is a fallback path and still uses `--continue-at -` plus external retry loops.

Also required on the host:

```bash
ollama --version
nvidia-smi
```

On WSL2, `nvidia-smi` is exposed by the Windows NVIDIA driver. The scripts do not install or modify GPU drivers.


## RTX 3090 + WSL2 setup recommendations

For reproducible 24 GB RTX 3090 benchmarking, keep the software path simple and avoid changing multiple variables at once.

### Windows / NVIDIA / WSL

- Install the current Windows NVIDIA production driver. Do not install a Linux display driver inside WSL.
- Update WSL from Windows PowerShell:

```powershell
wsl.exe --update
wsl.exe --shutdown
```

- Put distro-specific settings in `/etc/wsl.conf`:

```ini
[boot]
systemd=true

[gpu]
enabled=true
```

- Put VM-wide WSL2 settings in `%UserProfile%\.wslconfig`. Example starting point for a 64 GB RAM workstation:

```ini
[wsl2]
memory=48GB
processors=10
swap=32GB
localhostForwarding=true
# For headless benchmarking only; leave enabled if you need Linux GUI apps.
guiApplications=false

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Apply `.wslconfig` changes with:

```powershell
wsl.exe --shutdown
```

Do not blindly copy the memory/CPU numbers. Leave enough RAM and CPU capacity for Windows, browser sessions, and the NVIDIA driver stack.

### Ollama service settings for edge-of-VRAM models

For a large Q4 35B/36B model on a 24 GB RTX 3090, start with conservative concurrency. Use `systemctl edit ollama.service` on Linux/WSL systemd installs:

```ini
[Service]
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
# Test these one at a time; keep notes on speed and memory behavior.
Environment="OLLAMA_FLASH_ATTENTION=1"
# Optional memory-saving KV cache experiment.
# Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

Apply changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Then validate one request at a time before testing concurrency 2. A 35B Q4 model, 8K context, and two parallel requests can be close to the practical VRAM limit once KV cache and runtime overhead are included.

## Install

From the extracted package directory:

```bash
mkdir -p ~/.local/bin
cp ollama-* ~/.local/bin/
chmod +x ~/.local/bin/ollama-*
```

Confirm:

```bash
which ollama-download.sh
which ollama-test-and-monitor-RTX3090.sh
ollama-status
```

Optional legacy Python tools can remain inside the extracted package under `tools/legacy/`; they are not required for the RTX3090 workflow.

## Quick start

Download a large GGUF with resume support and import it into Ollama:

```bash
ollama-download.sh \
  --method aria2 \
  --repo bartowski/Qwen3-32B-GGUF \
  --file Qwen3-32B-Q4_K_M.gguf \
  --name qwen3-32b-q4km \
  --num-ctx 8192
```

For private/gated Hugging Face repos, authenticate first and use `--method hf`:

```bash
hf auth login
ollama-download.sh --method hf --repo ORG/REPO-GGUF --file MODEL.gguf --name local-model
```

Recommended RTX 3090 validation run:

```bash
ollama-test-and-monitor-RTX3090.sh \
  --model qwen3:8b \
  --interval 1 \
  --monitor-profile deep \
  --num-ctx 4096 \
  --long-ctx 8192 \
  --num-predict 512 \
  --long-num-predict 1024 \
  --long-prompt-words 3200 \
  --concurrency 2 \
  --think false
```

Screen behavior:

- Prints the run plan.
- Prints `START` and `DONE` for each test.
- Prints one compact final ASCII summary.
- Uses no colors and no terminal ESC control sequences.
- Keeps the summary under 50 lines.

Main outputs:

```text
~/log/ollama-test-and-monitor-RTX3090/run-*/
~/tmp/ollama-test-and-monitor-RTX3090-*.zip
```

## Resumable GGUF download and Ollama import

`ollama-download.sh` is intended for the specific case where `ollama pull` is inconvenient for a very large model on an unstable connection. The script separates model acquisition from Ollama import:

```text
resumable download -> local GGUF file -> generated Modelfile -> ollama create
```

Recommended WSL2 practice:

- Store large GGUF files under the WSL2 Linux filesystem, for example `~/models/gguf`, not under `/mnt/c`.
- Keep enough disk headroom for the downloaded GGUF and Ollama's imported model storage. For a 32 GB GGUF, keep substantially more than 32 GB free.
- Re-run the exact same command after disconnects. Do not remove the partial file or `.aria2` file unless intentionally restarting.
- Use `--method aria2` for public files when resume behavior is the top priority.
- Use `--method hf` for gated/private Hugging Face repositories after authentication.
- Use `--sha256` when the model publisher provides a checksum.

The generated Modelfile is minimal by design:

```text
FROM /absolute/path/to/model.gguf
PARAMETER num_ctx 8192
```

Add additional Ollama parameters by repeating `--param KEY=VALUE`.

## Command reference

### `ollama-download.sh`

Resumable GGUF downloader and Ollama importer. Use this instead of `ollama pull` when a 10-40+ GB model download is likely to be interrupted.

Common examples:

```bash
# Most explicit resume behavior for public Hugging Face GGUF files
ollama-download.sh \
  --method aria2 \
  --repo bartowski/Qwen3-32B-GGUF \
  --file Qwen3-32B-Q4_K_M.gguf \
  --name qwen3-32b-q4km \
  --num-ctx 8192

# Hugging Face CLI path; better for gated/private repos
hf auth login
ollama-download.sh \
  --method hf \
  --repo ORG/PRIVATE-GGUF \
  --file MODEL-Q4_K_M.gguf \
  --name private-model-q4km

# Download only; do not create an Ollama model
ollama-download.sh --repo REPO_ID --file MODEL.gguf --no-create

# Import an already-downloaded local GGUF
ollama-download.sh --local-file ~/models/gguf/model.gguf --name model-local --num-ctx 8192
```

Important options:

```text
--repo ID               Hugging Face repo id, e.g. bartowski/Qwen3-32B-GGUF
--file PATH             GGUF file path inside repo, or output filename for --url
--revision REV          Hugging Face revision/branch/commit; default main
--url URL               Direct download URL
--local-file PATH       Skip download and import an existing local GGUF
--method auto|hf|aria2|curl
--out-dir DIR           Directory for the local GGUF file
--retry-wait SEC        Wait before retrying failed attempts
--max-tries N           0 means retry forever
--timeout-sec N         Network idle timeout / HF timeout seconds
--connect-timeout-sec N Connect timeout seconds
--split N               aria2 split count
--connections N         aria2 max connections per server
--sha256 HEX            Expected SHA256
--name NAME             Ollama model name to create; if omitted, script downloads only
--no-create             Download/verify only
--param KEY=VALUE       Add PARAMETER line to generated Modelfile; repeatable
--num-ctx N             Shortcut for --param num_ctx=N
```

Default output locations:

```text
~/models/gguf/<repo-id-with-slashes-replaced>/MODEL.gguf
~/log/ollama-download/run-<id>/
```

Resume behavior:

- `aria2` mode resumes the destination file using `--continue=true` and keeps `.aria2` state next to the partial download.
- `hf` mode retries `hf download` into the same `--local-dir`, preserving Hugging Face cache/local state.
- `curl` mode uses `--continue-at -` and external retry loops.
- Re-run the same command after interruption; do not delete the partial file or `.aria2` file unless intentionally restarting with `--force`.

### `ollama-test-and-monitor-RTX3090.sh`

Primary command. It runs the monitor and test script together.

Common options:

```text
--model NAME              Ollama model pattern; required unless passed positionally
--think false             Disable thinking output for Qwen3-style models
--interval 1              Monitor sample interval in seconds
--monitor-profile deep    Richest GPU telemetry profile
--num-ctx 4096            Normal context window
--long-ctx 8192           Long-context test window
--long-prompt-words 3200  Approximate generated long prompt size
--num-predict 512         Standard test generation budget
--long-num-predict 1024   Sustained generation budget
--concurrency 2           Parallel request count for concurrency probe
--no-conc                 Disable concurrency probe
--run-cpu                 Add CPU reference; can be slow
--soak-minutes N          Add repeated sustained generation for N minutes
--run-vram-pressure       Add optional VRAM pressure probe
--vram-model NAME         Larger model for VRAM pressure probe
--pull                    Pull missing model(s); off by default
--no-zip                  Do not create archive
```

### `ollama-test-RTX3090.sh`

Runs only the Ollama API tests. It does not run the parallel GPU monitor.

```bash
ollama-test-RTX3090.sh qwen3 --think false
```

Useful variants:

```bash
# True long-context probe with larger prompt
ollama-test-RTX3090.sh qwen3 --long-ctx 8192 --long-prompt-words 5000

# Add a 15-minute thermal/performance soak
ollama-test-RTX3090.sh qwen3 --soak-minutes 15

# Add CPU reference; slow and may force reloads
ollama-test-RTX3090.sh qwen3 --run-cpu

# Optional larger-model VRAM pressure; model must already exist unless --pull is used
ollama-test-RTX3090.sh qwen3 --run-vram-pressure --vram-model qwen3:30b --vram-ctx 8192
```

### `ollama-monitor.sh`

Runs only the GPU/Ollama monitor.

```bash
ollama-monitor.sh --interval 1 --profile deep
```

Stop with `Ctrl+C`. A report is generated on exit.

Fixed-duration capture:

```bash
ollama-monitor.sh --interval 1 --duration 300 --profile deep
```

Self-test:

```bash
ollama-monitor.sh --self-test
```

### Support commands

| Command | Purpose |
|---|---|
| `ollama-download.sh` | Resumable GGUF download, verification, Modelfile generation, and `ollama create`. |
| `ollama-start` | Start Ollama server if not reachable. |
| `ollama-status` | Compact service/API/GPU status by default; use `--models` or `--full` for more detail. |
| `ollama-stop` | Stop Ollama server/runner processes. |
| `ollama-gen` | Small `/api/generate` wrapper. |
| `ollama-perf`, `ollama-perf-table` | Legacy benchmark scripts retained for compatibility. |

## Output structure

Combined orchestrator run:

```text
~/log/ollama-test-and-monitor-RTX3090/run-<id>/
  terminal-summary.txt
  orchestrator-summary.md
  test.console.log
  monitor.console.log
  archive.path
  test/run-<id>-test/
    terminal-summary.txt
    summary.md
    summary.csv
    concurrency-aggregate.csv
    soak-summary.csv
    raw/*.json
    raw/*.stderr
    payloads/*.json
    meta.txt
    nvidia-smi-before.txt
    nvidia-smi-after.txt
    nvidia-smi-q-before.txt
    nvidia-smi-q-after.txt
    dmesg-gpu-errors.txt
    failure-hints.txt
    ollama-server-log-tail.txt
    wsl-diagnostics.txt
    ollama-api-version.json
    ollama-api-tags.json
    ollama-api-show-model.json
    ollama-show-model.txt
  monitor/run-<id>-monitor/
    terminal-summary.txt
    report.md
    gpu.csv
    ollama-ps.txt
    ollama-api-ps.jsonl
    processes.tsv
    nvidia-compute-apps.csv
    nvidia-smi-q-start.txt
    nvidia-smi-q-end.txt
    dmesg-gpu-errors.txt
```

Downloader run:

```text
~/log/ollama-download/run-<id>/
  download.log
  errors.log
  meta.txt
  sha256.txt
  summary.txt
  Modelfile.<model-name>
```

Archive:

```text
~/tmp/ollama-test-and-monitor-RTX3090-<id>.zip
```

## How to interpret results

### Performance metrics

| Metric | Meaning |
|---|---|
| `Cold` | First model/context load time, dominated by disk/model load and runner initialization. Do not use it as steady-state speed. |
| `Warm` | Average single-request GPU generation speed from `throughput` and `sustained` categories only. This is the best default headline. |
| `LongCtx` | Long-context prompt-evaluation/generation behavior. Check `prompt_tokens` and `fill`; a low fill means the prompt did not really stress the context window. |
| `Conc` | Aggregate concurrency throughput across parallel requests. This is separate from per-request token/sec. |
| `Soak` | Optional aggregate throughput over repeated requests for thermal/performance stability. |
| `Error`, `http_code`, `error_class`, `error_body` | v0.9 failure-classification columns. Use these first when a run fails before token generation. |

### Health metrics

| Metric | Meaning |
|---|---|
| `Health: PASS` | No critical thermal/throttle/VRAM/PCIe check condition detected by available telemetry. If no model-load snapshot or generated tokens exist, treat this as monitor-health only, not inference-health. |
| `Health: PASS_WITH_CHECKS` | Test succeeded but one or more check conditions were observed, such as PCIe width below max while busy. |
| `Health: FAIL` | Critical temperature or hardware slowdown throttle was detected, or the test process failed. |
| `Thermal` | Max GPU core temperature and power draw during monitoring. |
| `VRAM` | Max VRAM used and percentage of total visible VRAM. |
| `PCIe` | Current PCIe generation and width compared with max reported width. |
| `Throttle` | Hardware slowdown and software power-cap counts, plus low-clock observations and memory-temperature availability. |

### Qwen3 thinking-mode note

Thinking-capable models can emit a separate `thinking` field. If the token budget is consumed by thinking, `response` may be empty even though the GPU worked correctly.

The default is:

```bash
--think false
```

Raw JSON still preserves `thinking`, `response`, durations, token counts, and `done_reason` for audit.

## Troubleshooting findings

### HTTP 500: `unable to load model: .../blobs/sha256-*`

This is a model-load failure, not an RTX 3090 performance result. v0.9 classifies it as `model_load_error` and writes the full API body to `summary.csv` and `failure-hints.txt`.

Immediate checks:

```bash
# Check for model-store activity that should not overlap with benchmarks.
pgrep -af 'ollama pull|ollama serve|ollama runner'

# Stop the target model if partially loaded.
ollama stop qwen3.6:35b 2>/dev/null || true

# Inspect the referenced blob from failure-hints.txt.
stat '/home/alex/.ollama/models/blobs/sha256-...'
sha256sum '/home/alex/.ollama/models/blobs/sha256-...'

# Capture current model metadata.
ollama show qwen3.6:35b
ollama ps
```

Likely fixes:

```bash
# If the model came from Ollama registry and the blob is missing/corrupt:
ollama rm qwen3.6:35b
ollama pull qwen3.6:35b

# If the model came from a local GGUF import:
# Recreate the model from the known-good GGUF/Modelfile.
ollama create qwen3.6:35b -f Modelfile
```

Rerun a conservative baseline before concurrency:

```bash
ollama-test-and-monitor-RTX3090.sh qwen3.6 --no-conc --concurrency 1
```

Only after that produces valid tokens should you rerun with `--concurrency 2`.

### PCIe width x8 / max x16

If the summary shows:

```text
PCIe: gen 3; width x8 / max x16; busy-width-checks=N
```

then the card reports a narrower active link than its maximum while busy. For local LLM inference, this often has limited impact after the model is resident in VRAM, but it is worth checking:

- GPU slot electrical width.
- BIOS lane allocation.
- Other PCIe devices sharing lanes.
- Whether the card is fully seated.
- Workstation vendor slot topology.

### Busy GPU with low clocks

`lowclk_obs` is treated as an observation unless it correlates with throttle flags, high temperature, or poor performance. Inference can be memory-bound or bursty, and WSL2 sampling can catch transient low-clock states.

### Memory junction temperature unavailable

RTX 3090 GDDR6X memory junction temperature is important, but WSL2 `nvidia-smi` may report it as `N/A`. The monitor records this as `memtemp_NA`. It is a coverage limitation, not proof of overheating.

### Long context underfilled

If `LongCtx` shows low fill percentage, increase:

```bash
--long-prompt-words 5000
```

or use a larger `--long-ctx` only when the model supports it.

## Retention guidance

Keep the generated zip and these files:

| File | Keep? | Reason |
|---|---:|---|
| `terminal-summary.txt` | Yes | Compact pasteable result. |
| `summary.md` / `report.md` | Yes | Human-readable interpretation. |
| `summary.csv` | Yes | Sortable test metrics and regression comparison. |
| `concurrency-aggregate.csv` | Yes | Correct aggregate concurrency throughput. |
| `raw/*.json` | Yes | Exact Ollama API evidence. |
| `payloads/*.json` | Yes | Reproducibility: exact request sent to Ollama. |
| `gpu.csv` | Yes | Independent GPU telemetry source. |
| `nvidia-smi-q-*.txt` | Yes | Deeper NVIDIA state snapshot. |
| `dmesg-gpu-errors.txt` | Yes | Linux/WSL-visible GPU error scan. |
| `failure-hints.txt` | Yes | First-pass failure classification and next-action hints. |
| `ollama-server-log-tail.txt` | Yes | Server-side context around model-load/API failures. |
| `wsl-diagnostics.txt` | Yes | WSL and `.wslconfig` evidence for environment reviews. |

Do not keep only screenshots. They are insufficient for later troubleshooting.

## Legacy tools and Python

The primary RTX3090 workflow does not require Python:

```text
ollama-monitor.sh
ollama-test-RTX3090.sh
ollama-test-and-monitor-RTX3090.sh
```

Legacy CSV helpers are retained under:

```text
tools/legacy/calc_perf_ollama.py
tools/legacy/calc_perf_ollama_table.py
```

They are useful for older `ollama-perf` CSV post-processing, not for the main RTX3090 workflow.

## Safety

The scripts do not:

- overclock or undervolt the GPU;
- change NVIDIA driver settings;
- flash GPU BIOS;
- modify Windows registry;
- install drivers;
- auto-download large models during diagnostics unless `--pull` is explicitly passed. `ollama-download.sh` is the intentional large-model download command and requires an explicit `--repo`/`--url`/`--local-file`.

CPU tests are off by default because they can be slow and may force model reloads.

## Validation and development notes

v0.9 validation performed during packaging:

```text
bash -n for all Bash scripts
ollama-monitor.sh --self-test --no-zip
fake Ollama HTTP 500 model-load server test for ollama-test-RTX3090.sh
summary.csv includes http_code/error_class/error_body
failure-hints.txt captures model_load_error and referenced sha256 blob path
manifest regenerated with SHA256 checksums
unzip final package and repeat basic validation
```

The package is intended to be inspected and modified. The implementation plan for v0.7 is in `plan.txt`; v0.9 validation details are in `VERIFY-v0.9.md`; v1.0 validation details are in `VERIFY-v1.0.md`; final v1.0 requirement status is in `REFLECTION-v1.0.md`; v1.1 validation and requirement status are in `VERIFY-v1.1.md` and `REFLECTION-v1.1.md`.

## Changelog summary

See `CHANGELOG.md` for version history.
