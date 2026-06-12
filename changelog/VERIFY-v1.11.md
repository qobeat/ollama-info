# Verify v1.11 final

Verification targets:

- Bash and Python syntax pass.
- One-token context rows become inconclusive.
- One-token context rows do not inflate visible speed.
- One-token context rows do not validate 8K/16K context.
- Settings confidence downgrades when context proof is absent.
- Routine `ollama test` defaults to resident-warm; full diagnostic is explicit.
- README documents command defaults and context gates.
- Package hygiene passes.
