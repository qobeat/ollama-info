#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"
VERSION="1.12.0"
SCRIPT_SIGNATURE="OLLAMA_EMBED_TEST_RTX3090_SCRIPT_SIGNATURE=v1.12-settings-rag-embed"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-embed-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
MODEL_PATTERN=""
ZIP_ON_EXIT=1
ROUTE_ONLY=0
TIMEOUT_SEC=600
usage(){ cat <<EOF_USAGE
ollama-embed-test-RTX3090.sh v$VERSION
Run Ollama /api/embed benchmark for embedding/RAG models.
Usage: ollama-embed-test-RTX3090.sh MODEL [--route-only] [--zip|--no-zip]
EOF_USAGE
}
while [[ $# -gt 0 ]]; do case "$1" in
  --model) MODEL_PATTERN="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
  --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
  --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
  --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
  --timeout-sec) TIMEOUT_SEC="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
  --route-only|--dry-run) ROUTE_ONLY=1; shift;;
  --zip) ZIP_ON_EXIT=1; shift;; --no-zip) ZIP_ON_EXIT=0; shift;;
  --quick|--terminal-summary|--no-terminal-summary|--strict-exit|--force-context-pressure) shift;;
  --profile|--mode|--evidence-level|--num-ctx|--num-predict|--context-steps|--keep-alive|--temperature|--think) shift 2;;
  -h|--help) usage; exit 0;;
  --*) ollama_warn "ignoring generation-only option for embed-test: $1"; shift;;
  *) [[ -z "$MODEL_PATTERN" ]] && MODEL_PATTERN="$1" || ollama_die "one model only"; shift;;
esac; done
[[ -n "$MODEL_PATTERN" ]] || { usage; echo; ollama_print_available_model_commands "$BASE_URL" "ollama embed-test"; exit 0; }
ollama_need_cmd jq
ollama_api_ready "$BASE_URL" 3 || ollama_die "Ollama API is not ready at $BASE_URL"
MODEL="$(ollama_resolve_model "$MODEL_PATTERN" "$BASE_URL")"
ROLE="$(ollama_model_role "$MODEL" "$BASE_URL" 2>/dev/null || echo unknown)"
if [[ "$ROUTE_ONLY" -eq 1 ]]; then echo "model=$MODEL role=$ROLE route=ollama-embed-test endpoint=/api/embed"; exit 0; fi
MODEL_SAFE="$(ollama_sanitize_name "$MODEL")"
RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"; PAYLOAD_DIR="$RUN_DIR/payloads"; mkdir -p "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
SUMMARY_CSV="$RUN_DIR/summary.csv"
cat >"$SUMMARY_CSV" <<'EOF_CSV'
timestamp,test,endpoint,result_state,sample_status,input_count,input_chars,prompt_eval_tokens,vector_count,vector_dim,total_s,load_s,embed_tokens_per_s,embeddings_per_s,http,notes
EOF_CSV
ollama_log "ollama-embed-test-RTX3090.sh v$VERSION"
ollama_log "$SCRIPT_SIGNATURE"
ollama_log "Run dir: $RUN_DIR"
ollama_log "Model: $MODEL role=$ROLE"
ollama_capture_environment_summary "$RUN_DIR/environment-summary.md" "$RUN_DIR" "$MODEL" "$BASE_URL" || true
run_embed(){
  local test_name input_json notes payload raw http err
  test_name="$1"; input_json="$2"; notes="$3"
  payload="$PAYLOAD_DIR/${test_name}.json"; raw="$RAW_DIR/${test_name}.json"; http="$RAW_DIR/${test_name}.http"; err="$RAW_DIR/${test_name}.stderr"
  jq -nc --arg model "$MODEL" --argjson input "$input_json" '{model:$model,input:$input}' >"$payload"
  curl -sS --connect-timeout 5 --max-time "$TIMEOUT_SEC" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload" --output "$raw" --write-out '%{http_code}' "$BASE_URL/api/embed" >"$http" 2>"$err" || true
  local code vc dim total load pe cnt chars etps eps state sample
  code="$(cat "$http" 2>/dev/null || echo 0)"
  vc="$(jq -r '(.embeddings // []) | length' "$raw" 2>/dev/null || echo 0)"
  dim="$(jq -r 'if ((.embeddings // [])|length)>0 then (.embeddings[0]|length) else 0 end' "$raw" 2>/dev/null || echo 0)"
  total="$(jq -r '(.total_duration // 0)/1000000000' "$raw" 2>/dev/null || echo 0)"
  load="$(jq -r '(.load_duration // 0)/1000000000' "$raw" 2>/dev/null || echo 0)"
  pe="$(jq -r '.prompt_eval_count // 0' "$raw" 2>/dev/null || echo 0)"
  cnt="$(jq -r 'if type=="array" then length else 1 end' <<<"$input_json")"
  chars="$(jq -r 'if type=="array" then map(length)|add else length end' <<<"$input_json")"
  etps="$(awk -v pe="$pe" -v t="$total" 'BEGIN{if(t>0) printf "%.2f", pe/t; else print ""}')"
  eps="$(awk -v vc="$vc" -v t="$total" 'BEGIN{if(t>0) printf "%.2f", vc/t; else print ""}')"
  state="PASS"; sample="OK"
  [[ "$code" -ge 400 || "$vc" -eq 0 || "$dim" -eq 0 ]] && { state="FAIL"; sample="API_OR_VECTOR_ERROR"; }
  printf '%s,%s,/api/embed,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$(ollama_now_iso)" "$test_name" "$state" "$sample" "$cnt" "$chars" "$pe" "$vc" "$dim" "$total" "$load" "$etps" "$eps" "$code" "$(printf '%s' "$notes"|tr ',' ';')" >>"$SUMMARY_CSV"
}
run_embed 01_embed_sanity '"short sanity embedding input"' "single short input"
run_embed 02_embed_batch "$(python3 - <<'PY'
import json
print(json.dumps([f'code chunk {i}: function behavior and data model notes' for i in range(32)]))
PY
)" "32 chunk batch"
run_embed 03_embed_rag_profile "$(python3 - <<'PY'
import json
print(json.dumps([('requirements evidence traceability schema validation ADOS runtime ' * 30), ('python code architecture agent workflow tool routing ' * 30), ('RAG retrieval chunk semantic claim identity truth status ' * 30)]))
PY
)" "RAG-like document chunks"
python3 - <<'PY' "$RUN_DIR" "$MODEL" "$ROLE"
import csv,sys,statistics
from pathlib import Path
rd=Path(sys.argv[1]); model=sys.argv[2]; role=sys.argv[3]
rows=list(csv.DictReader(open(rd/'summary.csv',encoding='utf-8')))
status='PASS' if rows and all(r['result_state']=='PASS' for r in rows) else 'FAIL'
dims=sorted(set(r['vector_dim'] for r in rows if r.get('vector_dim') not in ('','0')))
eps=[float(r['embeddings_per_s']) for r in rows if r.get('embeddings_per_s')]
etps=[float(r['embed_tokens_per_s']) for r in rows if r.get('embed_tokens_per_s')]
eps_avg=f'{statistics.mean(eps):.2f}' if eps else 'N/A'
etps_avg=f'{statistics.mean(etps):.2f}' if etps else 'N/A'
summary=f'''# RTX 3090 Ollama Embed Test Summary

- model: {model}
- role: {role}
- endpoint: /api/embed
- status: {status}
- vector_dims: {', '.join(dims) if dims else 'N/A'}
- embeddings_per_s_avg: {eps_avg}
- embed_tokens_per_s_avg: {etps_avg}

Use this output for RAG/indexing model selection. Generation models should be compared with `ollama test` or `ollama bench`.
'''
(rd/'summary.md').write_text(summary)
term=f"""============================================================\nRTX3090 OLLAMA EMBED TEST SUMMARY\nModel   : {model}\nRole    : {role}\nEndpoint: /api/embed\nStatus  : {status}\nDim     : {', '.join(dims) if dims else 'N/A'}\nRows    : {len(rows)}\nFiles   : {rd}\n============================================================\n"""
(rd/'terminal-summary.txt').write_text(term); print(term)
PY
if [[ "$ZIP_ON_EXIT" -eq 1 ]]; then
  ARCHIVE_PATH="$TMP_DIR/ollama-embed-test-RTX3090-${MODEL_SAFE}-${RUN_ID}.zip"
  (cd "$(dirname "$RUN_DIR")" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  echo "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  ollama_log "zip: $ARCHIVE_PATH"
fi
