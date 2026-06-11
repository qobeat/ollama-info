# REFLECTION v1.8

v1.8 moves the package toward the requested ADOS runtime evaluation shape. The prior v1.7.1 package correctly fixed load-state/offload reporting, but default behavior still allowed current model residency to influence results. v1.8 changes that default to empty-card and records explicit verification evidence.

The default test surface now separates capability probing from performance benchmarking. Coding, essay, and internet-access-boundary prompts are the default ADOS profile. The v1.7 performance workload remains available through `--profile perf`, so backward comparability is preserved.

Command logic is now centralized in `scripts/ollama.sh`. Bashrc is a thin delegation layer and `ollama-bench-RTX3090.sh` is a compatibility shim. This reduces logic redundancy while keeping old entry points usable.

Residual limitations:

- Empty-card verification clears Ollama model residency; it does not prove OS page-cache coldness or storage-cold load.
- The capability-analysis checks are deterministic evidence aids, not full model-quality scoring.
- The sandbox fake harness verifies package behavior, not real RTX 3090 throughput.
- Live model quality still requires running v1.8 on the target workstation.

Finalization decision: PASS, with stated limitations.
