# Review v1.10

The v1.9 test artifacts showed that single empty-card ADOS capability testing was not enough to determine the best daily model or performance settings. The qwen3.6:27b reference run showed a strong split between cold startup and warm resident usability, plus critical VRAM headroom. v1.10 therefore changes the default diagnostic from a single prompt set into a mode-complete diagnostic suite.

Key review findings:

- Cold first request and warm resident use require separate classification.
- Critical VRAM headroom must block larger context by default.
- All service settings and request options must be logged for reproducibility.
- The primary outputs must be decision artifacts, not only raw benchmark logs.
- Applyable WSL2/systemd settings should be produced per model.
- ADOS prompt checks remain useful but require stronger visible-output semantics.
