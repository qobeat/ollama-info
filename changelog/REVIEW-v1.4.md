# REVIEW v1.4

## Reviewed user issue

The recommended command still included `--no-conc --concurrency 1`, which made the short UX look unfinished. The README also only described the latest delta instead of presenting the package as a coherent production tool.

## Decision

Make the safe single-request baseline the default. Keep concurrency as an explicit stress mode via `--run-conc --concurrency 2` or `--stress`.

## Files changed

- `README.md`
- `bashrc/.bashrc`
- `bashrc/README.md`
- `scripts/ollama-test-and-monitor-RTX3090.sh`
- `scripts/ollama-test-RTX3090.sh`
- `scripts/ollama-monitor.sh`
- `scripts/ollama-status`
- `changelog/CHANGELOG.md`
