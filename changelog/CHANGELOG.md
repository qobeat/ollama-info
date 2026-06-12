# CHANGELOG

## v1.10.0

- Added mode-complete diagnostics: empty-card, resident-warm, and context-pressure.
- Kept ADOS coding, essay, and internet-access probes with improved visible-output semantics.
- Added environment-summary.md and runner-log-facts.md.
- Added model-scorecard.csv, recommendations.md, performance-settings.sh, and performance-settings.md.
- Added single-model ZIP names with sanitized model names.
- Added one-ZIP aggregate behavior for multi-model generation and mixed-role bench runs.
- Added role-aware /api/embed benchmark path.
- Added ADOS compliance evidence surfaces, source-of-truth map, manifest, package metadata, schema, and evidence ledger.
- Removed legacy and duplicate generated surfaces from the source package boundary.

## v1.11.0

- Fixed `think=false` serialization to JSON boolean false.
- Added API error extraction to generation metrics.
- Added fail-closed `TOOL_FAILURE`, `NO_VALID_GENERATION_ROWS`, and `NO_MODEL_RANKING` behavior.
- Suppressed model recommendations when rows are not decision-grade.
- Added settings confidence and context validation fields.
- Added `recommended-ollama-env.conf` as the plain systemd drop-in output.
- Rewrote README around GOAL, objectives, command modes, settings interpretation, and troubleshooting.
- Added `requirements.md` as the durable goal/objective/requirement authority.

## v1.11.0-final

- Fixed the final context-pressure false-positive: HTTP 200 rows with only one/few generated tokens are now `SHORT_CONTEXT_SAMPLE` / `CONTEXT_PRESSURE_INCONCLUSIVE`.
- Excluded context-pressure rows from `visible_tps_avg` and aggregate model ranking so impossible one-token speeds cannot select winners.
- Context settings are confirmed only when minimum output gates pass; otherwise settings confidence is downgraded and context remains conservative.
- Routine `ollama test` now defaults to resident-warm comparison to avoid repeated empty-card first-load cost; `ollama diagnose` runs the full long diagnostic.
