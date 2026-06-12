# Self-evaluation v1.10

| Axis | Score | Verdict | Evidence |
|---|---:|---|---|
| Request fit | 9.2 | PASS | Default suite now targets model choice plus applyable settings. |
| Decision utility | 9.3 | PASS | `model-scorecard.csv`, `recommendations.md`, and `performance-settings.sh` are main outputs. |
| Runtime boundary | 8.8 | PASS | Scripts generate settings but require user execution/review. |
| Evidence materialization | 9.0 | PASS | Plan, request record, test review, compliance mapping, evidence ledger, verification summary. |
| ADOS prompt continuity | 8.7 | PASS | Coding, essay, internet probes retained and improved. |
| Measurement integrity | 8.6 | PASS | Cold/warm/context modes separated; thinking-only rows excluded from visible throughput. |
| Compaction | 8.5 | PASS | Source package excludes run artifacts and nested archives. |
| Reproducibility | 8.7 | PASS | Environment and runner facts are logged by default. |
| Live hardware proof | 7.5 | ADVISORY | Build sandbox uses fake hardware; live RTX evidence is produced by user-side execution. |

Overall verdict: PASS_WITH_ADVISORY.
