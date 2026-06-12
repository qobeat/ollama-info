#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"
VERSION="1.13.0"
SCRIPT_SIGNATURE="OLLAMA_VISION_TEST_RTX3090_SCRIPT_SIGNATURE=v1.13-explicit-image-evidence"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-vision-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
MODEL_PATTERN=""
IMAGE_PATH=""
PROMPT="Describe the image precisely. Then answer: what visible objects, text, and layout details are present? If you cannot inspect the image, say so clearly."
NUM_CTX="${NUM_CTX:-4096}"
NUM_PREDICT="${NUM_PREDICT:-512}"
TEMPERATURE="${TEMPERATURE:-0.1}"
KEEP_ALIVE="${KEEP_ALIVE:-24h}"
TIMEOUT_SEC="${TIMEOUT_SEC:-1200}"
ZIP_ON_EXIT=1
ROUTE_ONLY=0
PRINT_TERMINAL_SUMMARY=1
usage(){ cat <<EOF_USAGE
ollama-vision-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Usage:
  ollama-vision-test-RTX3090.sh MODEL --image PATH [options]

Options:
  --image PATH              Required local image path: png, jpg, jpeg, webp, bmp, or gif.
  --prompt TEXT             Vision prompt. Default asks for visible objects/text/layout.
  --num-ctx N               Context length (default: $NUM_CTX)
  --num-predict N           Prediction length (default: $NUM_PREDICT)
  --keep-alive VALUE        Ollama keep_alive (default: $KEEP_ALIVE)
  --temperature X           Temperature (default: $TEMPERATURE)
  --timeout-sec N           Request timeout (default: $TIMEOUT_SEC)
  --base-url URL            Ollama API base URL
  --out-dir DIR             Output root
  --run-id ID               Run id
  --zip / --no-zip          Create final ZIP (default: $ZIP_ON_EXIT)
  --terminal-summary / --no-terminal-summary
  --route-only              Resolve model and print route without running
EOF_USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_PATTERN="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --image) IMAGE_PATH="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --prompt) PROMPT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-ctx) NUM_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-predict) NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --keep-alive) KEEP_ALIVE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --temperature) TEMPERATURE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    --terminal-summary) PRINT_TERMINAL_SUMMARY=1; shift ;;
    --no-terminal-summary) PRINT_TERMINAL_SUMMARY=0; shift ;;
    --route-only|--dry-run) ROUTE_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) ollama_die "unknown option: $1" ;;
    *) if [[ -z "$MODEL_PATTERN" ]]; then MODEL_PATTERN="$1"; else ollama_die "unexpected positional argument: $1"; fi; shift ;;
  esac
done
[[ -n "$MODEL_PATTERN" ]] || { usage; exit 0; }
ollama_need_cmd jq
ollama_need_cmd python3
MODEL="$(ollama_resolve_model "$MODEL_PATTERN" "$BASE_URL")"
ROLE="$(ollama_model_role "$MODEL" "$BASE_URL" 2>/dev/null || echo generate)"
if [[ "$ROUTE_ONLY" -eq 1 ]]; then
  echo "model=$MODEL role=$ROLE route=ollama-vision-test endpoint=/api/generate image_required=1"
  exit 0
fi
[[ -n "$IMAGE_PATH" ]] || ollama_die "vision-test requires --image PATH"
[[ -f "$IMAGE_PATH" ]] || ollama_die "image file not found: $IMAGE_PATH"
case "${IMAGE_PATH,,}" in
  *.png|*.jpg|*.jpeg|*.webp|*.bmp|*.gif) ;;
  *) ollama_die "unsupported image extension for $IMAGE_PATH" ;;
esac
ollama_api_ready "$BASE_URL" 3 || ollama_die "Ollama API is not ready at $BASE_URL"
MODEL_SAFE="$(ollama_sanitize_name "$MODEL")"
RUN_DIR="$OUT_DIR/run-$RUN_ID-$MODEL_SAFE-vision"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
mkdir -p "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
IMAGE_B64_FILE="$RAW_DIR/image.base64.txt"
python3 - <<'PY' "$IMAGE_PATH" "$IMAGE_B64_FILE"
import base64, pathlib, sys
src=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
out.write_text(base64.b64encode(src.read_bytes()).decode('ascii'), encoding='ascii')
PY
PAYLOAD="$PAYLOAD_DIR/vision.json"
RAW="$RAW_DIR/vision.ndjson"
METRICS="$RAW_DIR/vision.metrics.json"
HTTP="$RAW_DIR/vision.http"
ERR="$RAW_DIR/vision.stderr"
ANSWER="$RAW_DIR/vision.answer.txt"
THINKING="$RAW_DIR/vision.thinking.txt"
PREVIEW="$RAW_DIR/vision.answer-preview.md"
jq -nc --arg model "$MODEL" --arg prompt "$PROMPT" --rawfile image "$IMAGE_B64_FILE" --arg keep_alive "$KEEP_ALIVE" --argjson ctx "$NUM_CTX" --argjson predict "$NUM_PREDICT" --argjson temp "$TEMPERATURE" \
  '{model:$model,prompt:$prompt,stream:true,images:[$image],keep_alive:$keep_alive,options:{num_ctx:$ctx,num_predict:$predict,temperature:$temp}}' >"$PAYLOAD"
"$SCRIPT_DIR/ollama-run-generate.py" --base-url "$BASE_URL" --payload "$PAYLOAD" --raw "$RAW" --metrics "$METRICS" --http-file "$HTTP" --stderr-file "$ERR" --answer-file "$ANSWER" --thinking-file "$THINKING" --answer-preview-file "$PREVIEW" --timeout "$TIMEOUT_SEC" || true
HTTP_CODE="$(cat "$HTTP" 2>/dev/null || echo 0)"
RESP_CHARS="$(jq -r '.response_chars // 0' "$METRICS" 2>/dev/null || echo 0)"
EVAL_TOKENS="$(jq -r '.eval_tokens // 0' "$METRICS" 2>/dev/null || echo 0)"
TTFT="$(jq -r 'if .ttft_answer_ms==null then "" else (.ttft_answer_ms|tostring) end' "$METRICS" 2>/dev/null || true)"
TPS="$(jq -r 'if .visible_answer_tps==null then "" else (.visible_answer_tps|tostring) end' "$METRICS" 2>/dev/null || true)"
STATUS="PASS"
SAMPLE="OK"
if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 0 ]]; then STATUS="FAIL"; SAMPLE="API_ERROR"; fi
if [[ "$STATUS" == "PASS" && "$RESP_CHARS" -lt 80 ]]; then STATUS="INCONCLUSIVE"; SAMPLE="NEEDS_REVIEW"; fi
cat >"$RUN_DIR/summary.csv" <<EOF_CSV
timestamp,test,mode,category,endpoint,result_state,sample_status,ctx,predict,prompt_tokens,eval_tokens,decode_tps_raw,visible_answer_tps,ttft_any_ms,ttft_answer_ms,load_s,total_s,response_chars,thinking_chars,thinking_only,http,done_reason,notes
$(ollama_now_iso),01_vision_image,vision,vision,/api/generate,$STATUS,$SAMPLE,$NUM_CTX,$NUM_PREDICT,,${EVAL_TOKENS},,${TPS},,${TTFT},,,${RESP_CHARS},,,${HTTP_CODE},,image=$(basename "$IMAGE_PATH")
EOF_CSV
cat >"$RUN_DIR/summary.md" <<EOF_MD
# RTX 3090 Ollama Vision Test Summary

| Field | Value |
|---|---|
| Model | \`$MODEL\` |
| Role | \`$ROLE\` |
| Image | \`$IMAGE_PATH\` |
| HTTP | \`$HTTP_CODE\` |
| Status | \`$STATUS\` |
| Sample | \`$SAMPLE\` |
| Eval tokens | \`$EVAL_TOKENS\` |
| Response chars | \`$RESP_CHARS\` |
| TTFT answer | \`${TTFT:-N/A}\` ms |
| Visible TPS | \`${TPS:-N/A}\` |

## Answer preview

$(sed -n '1,80p' "$PREVIEW" 2>/dev/null || true)
EOF_MD
cat >"$RUN_DIR/terminal-summary.txt" <<EOF_TERM
================================================================================
RTX3090 OLLAMA VISION TEST SUMMARY
Model: $MODEL    Role: $ROLE
Status: $STATUS    Sample: $SAMPLE
================================================================================
| Metric | Value |
|---|---:|
| HTTP | $HTTP_CODE |
| Eval tokens | $EVAL_TOKENS |
| Response chars | $RESP_CHARS |
| TTFT answer | ${TTFT:-N/A} ms |
| Visible output speed | ${TPS:-N/A} tok/s |

Artifacts: summary.md, summary.csv, raw/vision.answer.txt, raw/vision.ndjson
================================================================================
EOF_TERM
[[ "$PRINT_TERMINAL_SUMMARY" -eq 1 ]] && cat "$RUN_DIR/terminal-summary.txt"
if [[ "$ZIP_ON_EXIT" -eq 1 ]]; then
  ARCHIVE_PATH="$TMP_DIR/ollama-vision-test-RTX3090-${MODEL_SAFE}-${RUN_ID}.zip"
  (cd "$(dirname "$RUN_DIR")" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  echo "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  echo "Vision zip: $ARCHIVE_PATH"
fi
case "$STATUS" in
  PASS) exit 0 ;;
  FAIL) exit 1 ;;
  *) exit 3 ;;
esac
