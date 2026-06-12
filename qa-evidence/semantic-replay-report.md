# Semantic replay report

Replay scenario: a model returns HTTP 200 at 65K but emits one token.
Expected: context verdict is short/inconclusive, Hermes main chat is not confirmed, settings are not HIGH_CONTEXT_CONFIRMED.

Replay scenario: a model passes 65K with prompt fill, eval tokens, and visible output.
Expected: Hermes main chat can be confirmed and settings can reach HIGH_CONTEXT_CONFIRMED.
