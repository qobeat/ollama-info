# VERIFY-v0.8

## Scope

Validation for `ollama-info` v0.8 focused on the new `ollama-download.sh` utility and package consistency after adding it.

## Checks performed

```bash
bash -n ollama-download.sh
for f in ollama-*; do
  if head -1 "$f" | grep -q bash; then bash -n "$f"; fi
done
./ollama-download.sh --help
./ollama-download.sh --repo foo/bar --file model.gguf --name local --dry-run --method aria2 --num-ctx 8192
```

Synthetic local-file verification:

```bash
printf 'GGUFfake' > fake.gguf
./ollama-download.sh --local-file fake.gguf --no-create --print-path
```

Synthetic `ollama create` verification with a fake `ollama` executable:

```bash
./ollama-download.sh \
  --local-file fake.gguf \
  --name fake-model \
  --no-ensure-server \
  --num-ctx 8192 \
  --param temperature=0.2
```

Expected generated Modelfile shape:

```text
FROM /absolute/path/fake.gguf
PARAMETER num_ctx 8192
PARAMETER temperature 0.2
```

Package validation:

```bash
zip -r ollama-info-v0.8.zip ollama-info
unzip -q ollama-info-v0.8.zip -d verify
find verify/ollama-info -maxdepth 2 -type f
bash -n verify/ollama-info/ollama-download.sh
verify/ollama-info/ollama-download.sh --help
```

## Result

PASS for static Bash syntax, help output, dry-run planning, local-file verification, fake Ollama create flow, manifest regeneration, and final ZIP extraction.

## Limitation

A live 32 GB Hugging Face download was not executed during packaging. The script path for actual large downloads is implemented using the same command-line mechanisms validated here: `aria2c --continue=true`, `hf download` retry into a stable local directory, or `curl --continue-at -` fallback.
