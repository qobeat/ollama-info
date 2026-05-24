# VERIFY-v0.7

## Environment

Validation was performed in the packaging sandbox with fake Ollama and fake `nvidia-smi` tools for workflow-level tests. Real RTX 3090 hardware validation must be run on the target WSL2 workstation.

## Checks performed

### 1. Bash syntax

Command:

```bash
for f in ollama-* *.sh; do [ -f "$f" ] || continue; bash -n "$f" || exit 1; done
```

Result: PASS.

### 2. Legacy Python syntax

Command:

```bash
python3 -m py_compile tools/legacy/*.py
```

Result: PASS.

### 3. Help checks

Commands:

```bash
./ollama-monitor.sh --help
./ollama-test-RTX3090.sh --help
./ollama-test-and-monitor-RTX3090.sh --help
```

Result: PASS. All primary scripts report v0.7.0 and expose new options.

### 4. Monitor self-test

Command:

```bash
HOME=/tmp/ollama-info-v07-self ./ollama-monitor.sh --self-test --no-zip
```

Result: PASS.

Observed:

```text
Health  : PASS_WITH_CHECKS
PCIe    : gen 3; width x8 / max x16; busy-width-checks=2
Throttle: hw_slowdown=0 sw_power_cap=0; lowclk_obs=2; memtemp_NA=3/3
```

Report contained:

```text
Diagnostic verdicts
nvidia-smi -q start snapshot
nvidia-smi -q end snapshot
dmesg GPU/error scan
```

Terminal summary line count: 15, no ESC byte found.

### 5. Fake Ollama + fake nvidia-smi orchestrator workflow

Command shape:

```bash
PATH=/tmp/ollama-info-fakebin:$PATH \
HOME=/tmp/ollama-info-fakehome \
./ollama-test-and-monitor-RTX3090.sh \
  --model qwen3:8b \
  --interval 1 \
  --monitor-profile deep \
  --num-ctx 4096 \
  --long-ctx 8192 \
  --num-predict 64 \
  --long-num-predict 128 \
  --long-prompt-words 3200 \
  --concurrency 2 \
  --think false \
  --no-zip
```

Result: PASS.

Observed:

```text
Test    : PASS
Warm    : single GPU 49.97 tok/s avg
LongCtx : prompt_tokens=6369 ctx=8192 fill=77.7% ... OK
Conc    : x2 aggregate ... tok/s
Health  : PASS_WITH_CHECKS
```

Terminal summary line count: 31, no ESC byte found.

### 6. Fake curl failure return-code preservation

Command shape:

```bash
PATH=/tmp/ollama-info-fakefail:$PATH \
HOME=/tmp/ollama-info-failhome \
./ollama-test-RTX3090.sh --model qwen3:8b --no-conc --no-zip --no-terminal-summary
```

Result: PASS.

Observed:

```text
curl_failed_rc_28
```

Script exit code: 1 when request errors were present.

### 7. Archive creation

Command shape:

```bash
PATH=/tmp/ollama-info-fakebin:$PATH \
HOME=/tmp/ollama-info-fakehome \
./ollama-test-and-monitor-RTX3090.sh ...
```

Result: PASS.

Observed combined archive under:

```text
~/tmp/ollama-test-and-monitor-RTX3090-<run_id>.zip
```

### 8. Core workflow Python dependency check

Command:

```bash
grep -R "python3" -n ollama-monitor.sh ollama-test-RTX3090.sh ollama-test-and-monitor-RTX3090.sh
```

Result: PASS. No Python dependency in the primary RTX3090 workflow.

## Known limitations after v0.7

- The package still cannot read Windows Event Viewer logs from inside WSL2.
- RTX 3090 memory junction temperature may be unavailable in WSL2 `nvidia-smi` output.
- True hardware validation requires running the final package on the actual RTX 3090 machine.

### 9. Final packaged zip validation

Command shape:

```bash
unzip -q ollama-info-v0.7.zip
cd ollama-info
bash -n primary scripts
python3 -m py_compile tools/legacy/*.py
./ollama-monitor.sh --self-test --no-zip
fake orchestrator workflow with no zip
```

Result: PASS.

Observed final packaged fake orchestrator summary:

```text
Test    : PASS
Warm    : single GPU ... tok/s
LongCtx : prompt_tokens=6369 ctx=8192 fill=77.7% ... OK
Conc    : x2 aggregate ... tok/s
Health  : PASS_WITH_CHECKS
```
