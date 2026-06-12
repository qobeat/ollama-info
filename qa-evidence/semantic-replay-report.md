# Semantic replay report v1.11 final

Replay: user observes impossible context-pressure speed and asks for the final repair.

Correct behavior after repair:

1. Treat one-token context output as insufficient evidence.
2. Preserve valid resident-warm speed and capability evidence.
3. Do not confirm larger context or HIGH_CONFIRMED settings without context evidence.
4. Prefer fast `ollama test` for daily comparison and explicit `ollama diagnose` for full cold/context diagnostics.

Verdict: PASS.
