# Reflection Iteration for ollama-info v0.5

## Requested goal

Produce `ollama-info-v0.5.zip` after deep review of the package and implement RTX 3090/Ollama monitoring and testing improvements.

## Requirement verification

| Requirement | Implemented | Evidence |
|---|---:|---|
| Deep review of attached package | Yes | `REVIEW-v0.5.md` documents defects and changes. |
| Improve `ollama-monitor.sh` precision | Yes | Rich NVIDIA query fields, Ollama snapshots, API `/api/ps`, process snapshots, compute-app snapshots, diagnostic flags, energy estimate, and Markdown report. |
| Monitor creates one zip in `~/tmp` for monitoring directory | Yes | `ollama-monitor.sh` defaults to `ZIP_ON_EXIT=1` and writes `~/tmp/ollama-monitor-<run_id>.zip`. |
| Create `ollama-test-RTX3090.sh` | Yes | Script added. Runs sanity, throughput, sustained generation, long-context, optional concurrency, optional CPU comparison. |
| Create `ollama-test-and-monitor-RTX3090.sh` | Yes | Script added. Starts monitor, runs test script, stops monitor, creates combined archive. |
| Orchestrator may call package scripts to ensure server | Yes | Calls package-local `ollama-start` if server is not reachable. |
| Update README | Yes | `README.md` rewritten for v0.5 workflows and interpretation. |
| Produce `ollama-info-v0.5.zip` | Yes | Final zip is generated outside the package directory. |
| Reflection iteration and fix if needed | Yes | Validation found one orchestration stop-signal defect and it was fixed before final packaging. No v0.6 required. |

## Validation performed in sandbox

The sandbox does not expose the user's WSL2 RTX 3090 or Ollama instance, so hardware validation was simulated where required. The following checks were executed:

1. `bash -n` syntax validation for:
   - `ollama-monitor.sh`
   - `ollama-test-RTX3090.sh`
   - `ollama-test-and-monitor-RTX3090.sh`
   - `ollama-start`
   - `ollama-status`
   - `ollama-stop`
   - `ollama-gen`
   - `ollama-perf`
   - `ollama-perf-table`
2. Python syntax validation:
   - `python3 -m py_compile calc_perf_ollama.py calc_perf_ollama_table.py`
3. Help-command checks:
   - `./ollama-monitor.sh --help`
   - `./ollama-test-RTX3090.sh --help`
   - `./ollama-test-and-monitor-RTX3090.sh --help`
   - `./ollama-gen --help`
4. Monitor self-test:
   - `ollama-monitor.sh --self-test`
   - verified `gpu.csv`, `report.md`, `archive.path`, and zip archive creation.
5. Fake Ollama API test:
   - ran `ollama-test-RTX3090.sh` against a local fake `/api/tags`, `/api/ps`, and `/api/generate` server.
   - verified raw JSON, payload JSON, `summary.csv`, `summary.md`, and zip archive creation.
6. Fake Ollama + fake `nvidia-smi` orchestration test:
   - ran `ollama-test-and-monitor-RTX3090.sh` with a fake RTX 3090 telemetry provider.
   - verified nested monitor output, nested test output, component archives, combined `orchestrator-summary.md`, and combined zip archive.

## Defect found during reflection and fixed

### Defect

The first orchestration simulation showed that stopping the background monitor with `SIGINT` could hang in non-interactive Bash because background jobs may inherit SIGINT ignored.

### Fix

`ollama-test-and-monitor-RTX3090.sh` now stops the monitor with `SIGTERM`, waits up to 10 seconds, and sends `SIGKILL` only if the monitor fails to exit. `ollama-monitor.sh` traps `TERM` and finalizes `report.md` + zip correctly.

### Retest result

The fake orchestration test completed successfully after the fix and produced:

- component monitor zip
- component test zip
- combined orchestrator zip
- combined Markdown summary

## Remaining limitations

- Real GPU telemetry must be validated on the user's WSL2 host with actual `nvidia-smi` and Ollama.
- `nvidia-smi` fields can differ by driver/WSL2 version; `ollama-monitor.sh` falls back from deep to normal/base query sets if unsupported fields are found.
- Qwen3 may still generate `thinking` before `response`; the test script records both fields and uses `/no_think` by default.
- PCIe x8 vs x16 is reported, not fixed. Corrective action depends on Dell slot wiring, BIOS lane allocation, and physical seating.

## Decision

No `ollama-info-v0.6.zip` is required because the only reflection-stage defect found was fixed before final v0.5 packaging, and the corrected package passed the validation checks above.
