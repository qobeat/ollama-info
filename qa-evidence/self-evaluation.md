# Self-evaluation v1.13

| Area | Result |
|---|---|
| Fix invalid vision command | PASS: `vision-test` route and script added; aggregate command includes `--image`. |
| Bash integration correctness | PASS: wrapper intercepts package subcommands only; native commands pass through. |
| Exit-code correctness | PASS: single-model exit reads `model-scorecard.csv`. |
| Stream text reconstruction | PASS: runner writes joined answer/thinking files. |
| Category gates | PASS: scorecard records coding/essay/internet gates and decision-grade requires them. |
| Context truthfulness | PASS: skipped rows are not runtime attempts. |
| Aggregate clarity | PASS: balanced, TTFT, TPS, and context-only summaries are separated. |
| README correctness | PASS: command examples match implemented routes. |

Known limitation: live Ollama execution cannot be performed inside this sandbox; validation used static checks and replay over uploaded result folders.
