# Test-results reference review v1.13

Uploaded v1.12 runtime ZIPs were used as replay evidence.

Replay checks performed with v1.13 summarizer:

- latest full 6-model result replayed successfully;
- context-only 6-model result replayed successfully;
- skipped 65K rows became `CONTEXT_NOT_RUN_SKIPPED`;
- `context_65k_attempted=0` for skipped-only 65K rows;
- Hermes/main-chat remained `NOT CONFIRMED`;
- old rows with ambiguous internet boundary were downgraded to `decision_grade=0`;
- aggregate summary no longer emits a bare invalid `ollama vision-test` command and instead requires `--image /path/to/test-image.png`.
