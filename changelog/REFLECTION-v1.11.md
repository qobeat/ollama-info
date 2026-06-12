# Reflection v1.11

The v1.10 design was directionally correct but violated the release goal because request payload serialization invalidated the run and the decision layer still emitted recommendations. v1.11 moves the tool closer to ADOS-style evidence discipline: failed rows now route to repair, model winners require decision-grade evidence, and settings carry explicit confidence.

Residual limitation: sandbox tests use fake Ollama/NVIDIA shims. Live RTX 3090 performance and final model selections still require a real host rerun.
