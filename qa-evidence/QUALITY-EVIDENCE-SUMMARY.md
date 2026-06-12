# Quality evidence summary v1.11 final

The final v1.11 repair targets the last observed serious scoring defect: context-pressure rows with insufficient output were incorrectly accepted as valid context proof and speed evidence.

Verification confirms:

- syntax and JSON/JSONL validity;
- short context rows are classified as inconclusive;
- impossible one-token speeds are excluded;
- settings confidence is downgraded when context proof is absent;
- routine `ollama test` avoids full empty-card runtime by default;
- full diagnostics remain available through `ollama diagnose`.
