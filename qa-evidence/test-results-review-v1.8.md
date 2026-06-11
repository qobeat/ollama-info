# v1.8 review of three supplied test results

## Inputs

- `ollama-test-RTX3090-20260611-141433.zip`
- `ollama-test-RTX3090-20260611-141928.zip`
- `ollama-test-and-monitor-RTX3090-20260611-142622.zip`
- `Pasted text.txt`
- `requirements.improved.md`

## Summary table

| Run | Model | State | Valid warm throughput | First request path | Long-context | Main warning |
|---|---|---|---:|---:|---|---|
| 20260611-141433 | `qwen3.6:27b` | observed absent, full GPU after run | `31.87 tok/s` | `203.28s`, `ColdVerified=0` | OK, `6474/8192`, `30.33 tok/s` | first request path is very large |
| 20260611-141928 | `qwen3.6:35b` | model switch observed | `22.65 tok/s` | `251.35s`, `ColdVerified=0` | SHORT_SAMPLE | CPU/GPU offload, prior model resident |
| 20260611-142622 | `qwen3.6:35b` | warm/resident before monitored run | `21.83 tok/s` | `15.49s`, resident before | SHORT_SAMPLE | CPU/GPU offload, VRAM 96.6% |

## Interpretation

`qwen3.6:27b` remains the cleaner full-GPU result. The large first-request path means default tests should clear current residency before running, but it should not be called a storage-cold load.

`qwen3.6:35b` direct and monitored results are useful for offload and warm-resident behavior. They should not be ranked as clean full-GPU RTX 3090 resident results.

The monitored `qwen3.6:35b` run demonstrates v1.7.1 correctly separated warm/resident behavior from verified cold behavior, but it also proves default observed mode is insufficient for fair repeated comparisons.

## Repair carried into v1.8

- Default load mode changed from `observed` to `empty-card`.
- All resident Ollama models are unloaded before the first request when possible.
- Load-state evidence now records `empty_card_requested` and `empty_card_verified`.
- Default tests use ADOS capability prompts rather than only performance probes.
- Performance probes remain under `--profile perf`.
- Multi-model wrapper support allows sequential comparison commands.
