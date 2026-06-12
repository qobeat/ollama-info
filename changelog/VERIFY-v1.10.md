# Verify v1.10

Verification gates:

- Shell syntax checks for all package shell scripts.
- Python syntax checks for streaming collector and summarizer.
- Fake Ollama API harness for generation route.
- Fake Ollama API harness for embedding route.
- Single-model ZIP naming check.
- Multi-model aggregate ZIP check.
- Role-aware bench route check.
- Evidence ledger JSONL parse.
- Package hygiene check: no runtime run directories, nested ZIPs, caches, or pyc files.
- README command coverage check.
