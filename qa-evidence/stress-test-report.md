# Stress test report

Stress cases covered:

1. `--full MODEL` parses without swallowing MODEL as an option value.
2. `--min-context 65536` reaches summarizer and scorecard.
3. one-token context output is not a pass.
4. 65K context pass sets Hermes gate to PASS.
5. aggregate recommendations separate coding, chat, Hermes main, Hermes fallback, ADOS, and heavy reasoning.
