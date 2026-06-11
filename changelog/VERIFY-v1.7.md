# VERIFY v1.7

## Verification environment

- Base package: `ollama-info-v1.6.zip`
- Governance package: `ados-apply-verify-v5.2.0-implementation-ready.zip`
- Runtime validation: Bash syntax checks and fake Ollama/NVIDIA shims in the sandbox
- Output log: `qa-evidence/verification-output-v1.7.txt`
- Evidence ledger: `qa-evidence/evidence-ledger.jsonl`
- Ledger schema: `qa-evidence/ados-apply-verify-schema.json`

## Checks performed

### 1. Bash syntax

Command class:

```bash
bash -n scripts/ollama-*.sh
bash -n scripts/ollama-start scripts/ollama-stop scripts/ollama-status
bash -n scripts/ollama-gen scripts/ollama-perf scripts/ollama-perf-table
bash -n bashrc/.bashrc
```

Result: PASS for all package shell files.

### 2. Bench auto-route verification

Commands:

```bash
PATH=/mnt/data/work/fakebin:$PATH ./scripts/ollama-bench-RTX3090.sh qwen3-embedding:4b --route-only
PATH=/mnt/data/work/fakebin:$PATH ./scripts/ollama-bench-RTX3090.sh fakegen:1b --route-only
```

Observed:

```text
model=qwen3-embedding:4b role=embedding
route=embedding ... --embedding

model=fakegen:1b role=generate
route=generate ... --model fakegen:1b
```

Result: PASS.

### 3. Strict unsupported generation

Command:

```bash
PATH=/mnt/data/work/fakebin:$PATH \
OUT_DIR=/mnt/data/work/final-verify-runs \
TMP_DIR=/mnt/data/work/final-verify-tmp \
TIMEOUT_SEC=20 \
./scripts/ollama-test-RTX3090.sh qwen3-embedding:4b \
  --stream --no-zip --terminal-summary --no-wsl-diagnostics \
  --run-id unsupported --no-ensure-server
```

Observed:

```text
exit code: 2
Status  : UNSUPPORTED
Errors  : API rows=0
Next    : ... ollama embed-test qwen3-embedding:4b
```

Result: PASS.

### 4. Streaming generation benchmark

Command:

```bash
PATH=/mnt/data/work/fakebin:$PATH \
OUT_DIR=/mnt/data/work/final-verify-runs \
TMP_DIR=/mnt/data/work/final-verify-tmp \
TIMEOUT_SEC=20 \
./scripts/ollama-test-RTX3090.sh fakegen:1b \
  --stream --no-zip --terminal-summary --no-wsl-diagnostics \
  --run-id gen-stream --long-prompt-words 100 --no-ensure-server
```

Observed:

```text
summary.csv rows: 4
summary.csv columns: 43
TTFT fields present
FirstReqLoad present in summary
sample_status values: OK,OK,OK,UNDERFILLED
```

Result: PASS.

### 5. Embedding benchmark

Command:

```bash
PATH=/mnt/data/work/fakebin:$PATH \
OUT_DIR=/mnt/data/work/final-verify-runs \
TMP_DIR=/mnt/data/work/final-verify-tmp \
TIMEOUT_SEC=20 \
./scripts/ollama-test-RTX3090.sh qwen3-embedding:4b \
  --embedding --no-zip --terminal-summary --no-wsl-diagnostics \
  --run-id embed --long-prompt-words 100 --no-ensure-server
```

Observed:

```text
embedding rows: 4
embedding tests: 01_embed_sanity,02_embed_batch,03_embed_longctx,04_embed_rag_profile
endpoint: /api/embed for every row
vector_dim present for every row
```

Result: PASS.

### 6. Cleanup and package hygiene precheck

Checks:

```bash
test ! -d scripts/legacy
test ! -e changelog/plan.txt
find . -type d \( -name '__pycache__' -o -name 'run-*' -o -name 'legacy' \) -print
find . -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '*.zip' \) -print
```

Observed:

```text
PASS no scripts/legacy
PASS no obsolete changelog/plan.txt
PASS no generated/cache/archive debris in package tree
```

Result: PASS.

### 7. ADOS evidence ledger schema validation

Command:

```bash
python3 - <<'PY'
import json
from pathlib import Path
from jsonschema import Draft202012Validator
schema = json.loads(Path('qa-evidence/ados-apply-verify-schema.json').read_text())
validator = Draft202012Validator(schema)
for i, line in enumerate(Path('qa-evidence/evidence-ledger.jsonl').read_text().splitlines(), 1):
    obj = json.loads(line)
    errors = sorted(validator.iter_errors(obj), key=lambda e: e.path)
    if errors:
        raise SystemExit(f'line {i}: {errors[0].message}')
print('PASS')
PY
```

Result: PASS.

### 8. Final package hygiene

Post-package checks verify that `ollama-info-v1.7.zip` contains the expected root directory and does not contain generated run directories, cache files, nested release zips, or legacy directories.

Result: PASS.

## Verification conclusion

v1.7 satisfies the requested implementation, cleanup, packaging, and ADOS evidence requirements. Real hardware performance validation remains a downstream user-side run on the RTX 3090 host.
