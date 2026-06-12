# Reference result review

The clean v1.11 resident-warm rerun proved that default testing is now operational and much faster than full diagnostics. It also showed two remaining usability gaps: final summaries were hard to interpret, and Hermes main-chat context was unresolved because 65K context was not validated.

v1.12 response:

- add `ollama test --full MODEL...` for all lanes;
- add `--min-context 65536` as the explicit Hermes context gate;
- add `ollama context-test MODEL... --min-context 65536`;
- redesign per-model and aggregate summaries into tables;
- expose preload/model-ready time separately from warm TTFT;
- emit `context-summary.csv` and `hermes-compatibility.md`;
- prevent Hermes main-chat recommendation unless `hermes_65k_context=PASS`;
- preserve fast resident-warm default for routine model comparison.
