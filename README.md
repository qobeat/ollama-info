# ollama-info v1.8

Production-oriented RTX 3090 + WSL2 + Ollama diagnostics, capability probes, and benchmark package.

`ollama-info` answers four operational questions:

1. Is Ollama running and reachable?
2. Is the requested model available, loadable, and role-compatible?
3. Does the model behave correctly on ADOS-relevant local tasks?
4. What performance, residency, load-state, and hardware warnings should be trusted for local-agent workflows?

## Primary entry point

v1.8 adds `scripts/ollama.sh` as the canonical wrapper. After installing `bashrc/.bashrc`, the wrapper is exposed through `ollama ...` while unknown subcommands pass through to the native Ollama CLI.

```bash
ollama status
ollama models
ollama test qwen3.6:35b qwen3.6:27b
ollama bench qwen3.6:27b qwen3-embedding:4b
ollama embed-test qwen3-embedding:4b
```

Compatibility scripts remain available, but `ollama.sh` owns command routing so logic does not drift across bashrc, bench, and test wrappers.

## v1.8 default test behavior

Default generation tests now use the ADOS capability profile:

```text
01_coding_first_prompt          coding capability probe
02_essay_second_prompt          structured essay capability probe
03_internet_access_third_prompt internet-access boundary probe
```

The default load mode is now:

```text
--load-mode empty-card
```

`empty-card` unloads all resident Ollama models before the first benchmark request and records:

```text
empty_card_requested
empty_card_verified
resident_models_before
load_state_verdict
cold_verified
```

`ColdVerified=1` means the model-residency precondition was verified. It is not a disk-cache, filesystem, or storage-throughput claim.

Use the legacy performance profile when you want the v1.7-style throughput/long-context rows:

```bash
ollama test qwen3.6:27b --profile perf
```

That profile preserves:

```text
01_sanity_gpu
02_throughput_gpu
03_sustained_gpu
04_longctx_gpu
```

## Multi-model usage

The wrapper supports several models in one command:

```bash
ollama test qwen3.6:35b qwen3.6:27b
ollama bench qwen3-embedding:4b qwen3.6:27b
```

Each model is resolved independently. By default, failures do not prevent later models from being attempted; use `--fail-fast` for strict sequential CI behavior.

Dry-run route checks:

```bash
ollama test qwen3.6:35b qwen3.6:27b --route-only
ollama bench qwen3-embedding:4b qwen3.6:27b --route-only
```

## Role-aware routing

`ollama bench MODEL` resolves the local model and routes by role:

```text
generation-capable model -> monitored /api/generate benchmark
embedding-only model     -> monitored /api/embed benchmark
unknown role             -> preflight refusal with evidence
```

Strict explicit commands remain available:

```bash
ollama test qwen3.6:27b          # generation capability/performance path
ollama embed-test bge-m3:latest  # embedding benchmark only
```

Embedding-only models remain `UNSUPPORTED` in strict generation mode and are not counted as failed generation benchmarks.

## Package layout

```text
ollama-info/
  README.md
  PACKAGE-MANIFEST.txt
  bashrc/
    .bashrc
    README.md
  scripts/
    ollama.sh                         primary wrapper
    ollama-common.sh                  shared library
    ollama-status                     status/model helper
    ollama-start                      service start helper
    ollama-stop                       service stop helper
    ollama-bench-RTX3090.sh           compatibility shim to ollama.sh bench
    ollama-test-and-monitor-RTX3090.sh monitored test orchestrator
    ollama-test-RTX3090.sh            generation/embed execution engine
    ollama-embed-test-RTX3090.sh      embed-test compatibility wrapper
    ollama-monitor.sh                 hardware monitor
    ollama-download.sh                model download utility
    ollama-gen
    ollama-perf
    ollama-perf-table
  changelog/
    plan-1.8.txt
    atomic-requirements-v1.8.txt
    REVIEW-v1.8.md
    VERIFY-v1.8.md
    REFLECTION-v1.8.md
  qa-evidence/
    evidence-ledger.jsonl
    evidence-ledger-v1.8.jsonl
    verification-output-v1.8.txt
    QUALITY-EVIDENCE-SUMMARY-v1.8.md
    test-results-review-v1.8.md
    self-evaluation-v1.8.md
```

## Quick start

From the package directory:

```bash
cd ~/dev/ollama-info
chmod +x scripts/ollama*
```

Optional shell integration:

```bash
cp ~/.bashrc ~/.bashrc.backup-$(date +%Y%m%d-%H%M%S)
cp bashrc/.bashrc ~/.bashrc
source ~/.bashrc
hash -r
```

Check setup:

```bash
ollama status
ollama models
```

Run ADOS default capability tests:

```bash
ollama test qwen3.6:35b qwen3.6:27b
```

Run performance profile:

```bash
ollama test qwen3.6:27b --profile perf
```

Run role-aware benchmark:

```bash
ollama bench qwen3.6:27b
ollama bench qwen3-embedding:4b
```

## Feature coverage

| Feature group | v1.8 coverage |
|---|---|
| Primary wrapper | `scripts/ollama.sh` centralizes `status`, `start`, `stop`, `models`, `gpu`, `logs`, `test`, `bench`, and `embed-test`. |
| Bash integration | `.bashrc` delegates to `ollama.sh` instead of duplicating command logic. |
| Multi-model commands | `ollama test MODEL MODEL ...` and `ollama bench MODEL MODEL ...` run sequentially with route-only support. |
| Empty-card default | Default tests unload all resident Ollama models and verify `/api/ps` is empty when possible. |
| ADOS capability prompts | Default generation profile tests coding, essay, and internet-access boundary behavior. |
| Performance profile | `--profile perf` preserves v1.7 throughput/sustained/long-context benchmark rows. |
| Generation benchmark | `/api/generate`, streaming TTFT, visible-answer throughput, thinking-only detection, sample status. |
| Embedding benchmark | `/api/embed`, vector count/dim, embedding throughput, batch/long-context/RAG-style rows. |
| Load-state semantics | `FirstReqLoad`, `FirstTTFT`, `WarmTTFT`, `EmptyCard`, `ColdVerified`, and residency warnings are separated. |
| Hardware telemetry | Monitor captures GPU, PCIe, power, VRAM, clocks, throttle flags, Ollama process/model state, and warning severity. |
| Evidence retention | Raw JSON, stream NDJSON, payloads, summary CSV/MD, capability analysis, load state, failure hints, logs, and zip archive. |
| Package hygiene | Release archive excludes run debris, caches, nested zips, legacy/generated clutter, and pyc artifacts. |

## Notes on interpreting results

- `empty_card_verified=1` proves Ollama residency was cleared before the first request. It does not prove a storage-cold load.
- `FirstReqLoad` belongs to the first request path and can include allocation, model mapping, GPU transfer, and runtime setup.
- `WarmTTFT` is the better indicator for already-loaded interactive behavior.
- `--profile ados` is capability-oriented. `--profile perf` is performance-oriented.
- `PASS_WITH_WARNINGS` can still represent a usable run when warnings are advisory, for example high VRAM occupancy without hardware slowdown.

## Verification

v1.8 verification uses shell syntax checks, deterministic fake Ollama/NVIDIA route checks, package hygiene checks, evidence-ledger parsing, and extracted-archive validation. The sandbox fake harness validates behavior and packaging; it does not produce real RTX 3090 throughput numbers.
