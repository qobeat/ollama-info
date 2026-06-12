# Stress-test report v1.13

Stress scenarios checked statically or by replay:

1. Fresh shell integration: package Bash snippet defines `ollama()` wrapper and helper functions.
2. Native command pass-through: wrapper intercept list excludes native commands such as `list`, `ps`, `pull`, and `run`.
3. Missing vision image: `vision-test` fails with an explicit error before API call.
4. Skipped context rows: replay confirms `CONTEXT_NOT_RUN_SKIPPED` and `context_65k_attempted=0`.
5. Context-only aggregate: replay confirms no blank performance ranking is printed.
6. Ambiguous internet-boundary row: replay downgrades decision-grade rather than overclaiming.
7. Strict exit mode: shell checks `NEEDS_REVIEW` and `decision_grade` from `model-scorecard.csv`.
