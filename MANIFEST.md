# ollama-info v1.13 manifest

## Package purpose

Local RTX 3090 / WSL2 Ollama diagnostic package with evidence-backed model recommendations, required-context gates, explicit vision testing, embedding tests, and conservative settings output.

## Authoritative files

1. `README.md` is the user-facing operating manual.
2. `requirements.md` defines the atomic requirements and acceptance conditions.
3. `scripts/ollama.sh` is the command router.
4. `scripts/ollama-test-RTX3090.sh` is the single-model generation/context runner.
5. `scripts/ollama-summarize-results.py` owns decision-grade scoring and settings output.
6. `scripts/ollama-aggregate-summary.py` owns multi-model summaries and use-case winners.
7. `scripts/ollama-vision-test-RTX3090.sh` owns explicit image/vision evidence.
8. `bashrc/.bashrc` owns shell integration.
9. `qa-evidence/` records verification and self-review.

## Production-quality gates

- Shell syntax passes for all shipped shell scripts.
- Python compilation passes for all shipped Python scripts.
- JSON files parse successfully.
- README examples match implemented `scripts/ollama.sh` routes.
- Aggregate summary no longer emits an invalid vision command.
- Skipped context rows are not counted as runtime attempts.
- Decision-grade generation requires category-aware capability gates.
