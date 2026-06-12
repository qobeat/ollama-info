# ollama-info v1.13 requirements

## Goal

Produce a production-grade local Ollama diagnostic package for RTX 3090 / WSL2 that gives evidence-backed recommendations for generation, context, embedding, and explicit vision use cases.

## Atomic requirements

| ID | Requirement | Acceptance condition |
|---|---|---|
| R-001 | Default generation test | `ollama test MODEL` runs resident-warm coding, essay, and internet/current-facts boundary probes. |
| R-002 | Full diagnostics | `ollama test --full MODEL` runs empty-card, resident-warm, and context-pressure lanes. |
| R-003 | Context gate | `--min-context 65536` is supported and used as the default Hermes/main-chat gate. |
| R-004 | Context truth labels | Skipped context rows are labeled `CONTEXT_NOT_RUN_SKIPPED` and do not count as runtime-tested. |
| R-005 | Hermes recommendation safety | Hermes/main-chat is confirmed only when a real row at or above `--min-context` passes. |
| R-006 | Joined text evidence | `/api/generate` streams produce joined `answer.txt` and `thinking.txt` artifacts. |
| R-007 | Category-aware gates | Coding, essay, and internet/current-facts boundary gates are reported separately. |
| R-008 | Decision-grade safety | A normal generation run is decision-grade only when required category gates pass. |
| R-009 | Exit-code correctness | Single-model exit status is derived from `model-scorecard.csv`, not legacy Markdown. |
| R-010 | Aggregate clarity | Aggregate output separates balanced ranking, TTFT ranking, TPS ranking, and context-only summaries. |
| R-011 | Vision workflow | `ollama vision-test MODEL --image PATH` runs an explicit image test and never appears as an invalid command. |
| R-012 | Bash integration | The supplied Bash snippet supports `ollama test ...` and safely passes native Ollama commands through. |
| R-013 | Documentation correctness | README command examples correspond to implemented routes and generated artifact names. |
| R-014 | Settings safety | Generated settings include confidence labels and conservative defaults when context is not confirmed. |
| R-015 | Package hygiene | Source package contains no runtime run directories and all scripts pass syntax/compile checks. |

## Non-goals

- The package does not guarantee model quality beyond the included lightweight probes.
- The package does not claim internet access for local models.
- The package does not confirm vision quality from text-only tests.
- The package does not apply systemd settings automatically during tests.
