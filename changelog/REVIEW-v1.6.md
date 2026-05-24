# REVIEW v1.6

## Test-output review

### `ollama test bge-m3` failure

The failure was not an RTX 3090, CUDA, WSL2, or Ollama service failure. The selected model was `bge-m3:latest`, an embedding-only model. The v1.5 generation runner sent all four benchmark requests to `/api/generate`, and Ollama returned HTTP 400 with `does not support generate` for each row.

Problem in v1.5 interpretation:

- Failure was classified as generic `ollama_client_error_400`.
- Long-context output showed `UNDERFILLED` even though prompt evaluation never occurred.
- The monitor could show hardware telemetry PASS while the inference benchmark was invalid.

### `ollama test gemma3:1b` success

The later `gemma3:1b` run passed all four generation rows. It validated the generation benchmark path:

- 4/4 visible rows.
- no API errors.
- long-context row reached 6070 prompt tokens / 8192 ctx = 74.1% fill.
- warm generation average reported about 176 tok/s.
- RTX 3090 telemetry stayed in a healthy range for that small model.

### Direct `bge-m3` embedding success

The direct `/api/embed` call returned a valid embedding response. The direct `/api/show` call identified `bge-m3:latest` as an embedding-capability BERT-family model with 8192 context length and 1024 embedding length.

## Implementation review

Changes made:

- Added model role detection from `/api/show`.
- Added `unsupported_generate_for_embedding_model` failure class.
- Added `/api/embed` benchmark mode and vector metrics.
- Added `ollama-embed-test-RTX3090.sh` and Bash wrapper `ollama embed-test`.
- Added slim `/api/show` metadata default and optional `--full-model-show`.
- Changed monitored summary wording from ambiguous hardware `Health` to explicit `Telemetry`, plus separate `Inference` verdict.
- Split dmesg findings into new-during-run and historical-since-boot sections.
- Updated README and Bash README for v1.6 feature coverage.

## Residual limitations

- The sandbox cannot execute real RTX 3090/Ollama workloads. Validation used syntax checks and fake Ollama/NVIDIA shims.
- Embedding throughput is reported as embeddings/second from Ollama duration fields when present; it is not directly comparable to generation tok/s.
- Some embedding models may not return prompt evaluation counts; in that case context-fill metrics may be blank or underfilled, but vector validation remains the primary embedding health signal.
