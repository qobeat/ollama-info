# v1.9/v1.10 reference test review

Reference artifact: `ollama-test-and-monitor-RTX3090-20260611-194424.zip`.

Key evidence extracted from the qwen3.6:27b run:

- model: qwen3.6:27b
- role: generate
- test profile: ados
- load mode: empty-card
- first request load: 183.47s
- first TTFT: 184127ms
- warm TTFT: 411ms average
- visible speed: 32.34 tok/s average
- residency: full GPU
- max VRAM: 23979 / 24576 MiB = 97.6%
- monitor classification: PASS_WITH_WARNINGS due to VRAM/power headroom, not thermal failure

Derived v1.10 implications:

- A single empty-card capability run is insufficient as the default test.
- The suite must distinguish cold/empty-card behavior from resident-warm daily behavior.
- The suite must emit `GOOD_WARM_BAD_COLD` and `RESIDENT_ONLY_RECOMMENDED` when warm TTFT is good but cold load is slow.
- The suite must emit `VRAM_CRITICAL_HEADROOM` and avoid larger context by default when 4K context already consumes more than 97% VRAM.
- The output must contain applyable settings for WSL2/systemd, especially `KEEP_ALIVE`, `MAX_LOADED_MODELS`, `NUM_PARALLEL`, and conservative context length.
