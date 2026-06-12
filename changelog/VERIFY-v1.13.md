# Verify v1.13

Verification must include:

- `bash -n` for shipped shell scripts.
- `python3 -m py_compile` for shipped Python scripts.
- JSON parse for package metadata and QA JSON files.
- `scripts/ollama.sh --help` includes `vision-test`.
- README commands match implemented routes.
- Replay summarization on uploaded v1.12 result folders shows skipped context rows are not runtime attempts.
- Aggregate summary emits `ollama vision-test ... --image /path/to/test-image.png`, not an invalid bare command.
