# ollama-info durable requirements

## Project Shape

| Field | Value |
|---|---|
| Project | `ollama-info` |
| Package type | RTX 3090 Ollama model evaluation and configuration package |
| Target host | WSL2/Linux workstation with RTX 3090 and local Ollama |
| Main delivery | ZIP package with scripts, README, schemas, and QA evidence |
| Evidence delivery | ZIP package with verification reports and evidence ledger |

## Goal Figure

The package must identify best local Ollama models and safe performance settings for coding, chat, Hermes, ADOS, ADOS code-repair, heavy reasoning, and vision workflows on the current RTX 3090 host.

## Goal Surface

A release is inside the goal surface when it:

1. Measures warm model performance without requiring full diagnostic overhead by default.
2. Runs full diagnostics through `--full`, including empty-card, resident-warm, and context-pressure lanes.
3. Validates context with explicit gates and supports `--min-context 65536` for Hermes main chat.
4. Refuses to confirm Hermes main-chat suitability until the 65K context gate passes.
5. Reports final summaries in clear tables.
6. Emits applyable WSL2/Ollama settings with explicit confidence levels.
7. Separates measurement evidence from use-case recommendations.
8. Preserves compact, traceable QA evidence.

## Objectives

| ID | Objective | Success condition |
|---|---|---|
| OBJ-001 | Add `--full` as the all-tests switch. | `ollama test --full MODEL` runs empty-card, resident-warm, and context-pressure lanes. |
| OBJ-002 | Add `--min-context` as the required context gate. | `--min-context 65536` appears in test plan, context summary, scorecard, and Hermes compatibility output. |
| OBJ-003 | Redesign terminal summaries as tables. | Per-model terminal output has Execution State, Performance, Capability Rows, Context Window, and Use-Case tables. |
| OBJ-004 | Validate context windows properly. | Context rows require HTTP 200, prompt fill, eval-token, and response-char gates. |
| OBJ-005 | Support Hermes main-chat gate. | No model is labeled Hermes main-chat winner unless `Hermes65K=PASS`. |
| OBJ-006 | Add use-case-aware aggregate recommendations. | Aggregate output separates coding, chat, Hermes main, Hermes fallback, ADOS, ADOS coding repair, vision, and heavy reasoning. |
| OBJ-007 | Expose preload/model-ready timing. | Scorecards include `preload_wait_s` and `model_ready_s`. |
| OBJ-008 | Keep settings confidence explicit. | Settings confidence is one of `LOW_UNCONFIRMED`, `MEDIUM_WARM_ONLY`, `MEDIUM_CONTEXT_PARTIAL`, or `HIGH_CONTEXT_CONFIRMED`. |
| OBJ-009 | Preserve package hygiene. | Release ZIP excludes run folders, nested ZIPs, caches, and generated local debris. |

## Atomic Requirements

| Req ID | Requirement | Verification |
|---|---|---|
| REQ-001 | The wrapper must accept `ollama test --full MODEL...` without treating the first model as an option value. | Route-only and fake-harness tests. |
| REQ-002 | The test engine must accept `--min-context N` and include N in context validation. | Fake context-harness and grep checks. |
| REQ-003 | Context rows with too few prompt/eval/output tokens must not pass. | One-token/underfilled semantic replay. |
| REQ-004 | Hermes main-chat recommendation must require `hermes_65k_context=PASS`. | Aggregate scoring replay. |
| REQ-005 | Terminal summaries must use tables for major sections. | Verification scans `terminal-summary.txt` output. |
| REQ-006 | Aggregate summary must include use-case winners and Hermes context gate table. | Verification scans aggregate artifacts. |
| REQ-007 | Settings must stay conservative when context is not validated. | Scorecard and settings evidence. |
| REQ-008 | README must define project goal, objectives, commands, context rules, settings confidence, and troubleshooting. | Markdown review. |
