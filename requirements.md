# ollama-info durable requirements

## Project shape

| Field | Value |
|---|---|
| Project | ollama-info |
| Artifact family | local AI playground / non-UI diagnostic toolkit |
| Target host | WSL2/Linux Ollama service with RTX 3090 telemetry |
| Main delivery | source ZIP containing scripts, README, manifest, schema, and QA evidence |
| Evidence delivery | quality-evidence ZIP with verification, stress, replay, reflection, and ledger records |

## Goal Figure

`ollama-info` identifies decision-grade local Ollama model choices and safe performance settings for the current hardware, service environment, model set, and intended coding/chat/agentic workloads.

### Goal surface

A release is inside the goal surface when it:

1. sends valid typed Ollama API payloads;
2. runs role-aware generation and embedding diagnostics;
3. measures empty-card, resident-warm, and context-pressure behavior for generation models;
4. preserves ADOS capability probes for coding, essay, and internet-access boundary behavior;
5. emits model recommendations only from decision-grade evidence;
6. emits settings with explicit confidence and avoids unverified “tested/safe” claims;
7. logs environment, service, model, runner, and GPU facts needed to explain performance;
8. packages source and QA evidence compactly without runtime debris.

## Objectives

| ID | Objective | Success indicator |
|---|---|---|
| OBJ-01 | Repair request serialization so boolean and string fields preserve Ollama API types. | Payloads use `"think": false`, not `"think": "false"`, when thinking is disabled. |
| OBJ-02 | Fail closed when generation rows fail. | Runs with no valid generation rows emit `TOOL_FAILURE`, `NO_MODEL_RANKING`, and no best-model recommendation. |
| OBJ-03 | Gate model rankings on evidence. | Aggregate recommendations use only rows with `ranking_allowed=1`. |
| OBJ-04 | Gate settings confidence on evidence. | Context increases require passing context-pressure rows; otherwise settings are `LOW_UNCONFIRMED` or baseline only. |
| OBJ-05 | Surface root errors in terminal and scorecard outputs. | `RootErr` appears in `terminal-summary.txt`, `summary.md`, and `model-scorecard.csv`. |
| OBJ-06 | Make README an operational authority. | README explains GOAL, objectives, commands, modes, settings confidence, decision-grade gating, and troubleshooting. |
| OBJ-07 | Preserve ADOS evidence discipline. | QA evidence includes plan, atomic requirements, verification, stress/replay, self-evaluation, reflection, and evidence ledger. |

## Atomic requirements

| ID | Requirement | Verification |
|---|---|---|
| AR-01 | `ollama test` must serialize `think=false` as a JSON boolean. | Fake Ollama harness rejects string false and accepts boolean false; payload inspection passes. |
| AR-02 | `ollama-run-generate.py` must capture HTTP error body and extracted API error text. | Failure harness emits root error in metrics and terminal summary. |
| AR-03 | Summaries must classify all-row API failure as `TOOL_FAILURE`. | Failure harness exits nonzero and emits `NO_MODEL_RANKING`. |
| AR-04 | Single-model recommendations must be suppressed when no valid generation row exists. | Failure harness `recommendations.md` says no best-model recommendation. |
| AR-05 | Aggregate recommendations must be suppressed when no candidate is decision-grade. | Aggregate ranking code filters by `ranking_allowed=1`. |
| AR-06 | Settings must declare confidence and avoid unconfirmed context/KV claims. | Scorecard includes `settings_confidence`, `context_validated`, and `kv_cache_type`. |
| AR-07 | README must document command behavior and interpretation. | README review confirms command and configuration sections. |
| AR-08 | Package must exclude runtime debris, caches, and nested ZIPs. | Package hygiene check passes. |
