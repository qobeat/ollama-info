# Verify v1.11

Verification targets:

- Bash syntax over shell scripts.
- Python syntax over helper scripts.
- Fake Ollama success harness confirms boolean `think:false` payload and PASS summary.
- Fake Ollama failure harness confirms TOOL_FAILURE, RootErr, nonzero exit, no recommendations, and LOW_UNCONFIRMED settings.
- Aggregate fake harness confirms aggregate recommendations only from decision-grade rows.
- Package hygiene confirms no runtime runs, nested zips, pycache, pyc, or OS debris.
