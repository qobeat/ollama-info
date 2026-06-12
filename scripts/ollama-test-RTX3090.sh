#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"

VERSION="1.12.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v1.12-table-summary-full-context-hermes65k"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
MODEL_PATTERN=""
MODEL=""
MODE="resident-warm"
PROFILE="ados"
NUM_CTX="${NUM_CTX:-4096}"
NUM_PREDICT="${NUM_PREDICT:-1024}"
QUICK_PREDICT="${QUICK_PREDICT:-512}"
TEMPERATURE="${TEMPERATURE:-0.2}"
KEEP_ALIVE="${KEEP_ALIVE:-24h}"
TIMEOUT_SEC="${TIMEOUT_SEC:-1200}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"
PRINT_TERMINAL_SUMMARY="${PRINT_TERMINAL_SUMMARY:-1}"
ROUTE_ONLY=0
EVIDENCE_LEVEL="${EVIDENCE_LEVEL:-standard}"
STRICT_EXIT=0
FORCE_CONTEXT_PRESSURE=0
CONTEXT_STEPS="${CONTEXT_STEPS:-4096,8192,16384}"
CONTEXT_STEPS_USER=0
MIN_CONTEXT="${MIN_CONTEXT:-65536}"
MIN_CONTEXT_EVAL="${MIN_CONTEXT_EVAL:-128}"
MIN_CONTEXT_CHARS="${MIN_CONTEXT_CHARS:-500}"
MIN_CONTEXT_FILL="${MIN_CONTEXT_FILL:-0.65}"
THINK="${THINK:-false}"
FULL=0

usage() {
  cat <<EOF_USAGE
ollama-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Usage:
  ollama-test-RTX3090.sh MODEL [options]

Default behavior:
  Runs a fast resident-warm ADOS capability benchmark for a generation model.
  It measures practical warm latency/speed and emits decision-grade tables,
  recommendations, and WSL2/Ollama settings. It does not confirm larger context.

Full behavior:
  ollama-test-RTX3090.sh --full MODEL
  Runs empty-card/load, resident-warm, and context-pressure tests through
  --min-context (default: $MIN_CONTEXT). Use --min-context 65536 for Hermes.

Options:
  --model MODEL              Model or local pattern
  --full                     Run all lanes: empty-card + resident-warm + context-pressure
  --mode MODE                resident-warm|diagnostic|quick|empty-card|context-pressure|perf
  --profile PROFILE          ados|perf|vision (default: ados)
  --num-ctx N                Baseline context (default: $NUM_CTX)
  --num-predict N            ADOS capability prediction length (default: $NUM_PREDICT)
  --quick                    Shortcut for --mode quick --num-predict $QUICK_PREDICT
  --min-context N            Required context gate for context testing (default: $MIN_CONTEXT)
  --context-steps CSV        Context pressure steps (overrides auto ladder)
  --min-context-eval N       Minimum eval tokens for context pass (default: $MIN_CONTEXT_EVAL)
  --min-context-chars N      Minimum response chars for context pass (default: $MIN_CONTEXT_CHARS)
  --min-context-fill X       Minimum prompt/context fill ratio (default: $MIN_CONTEXT_FILL)
  --force-context-pressure   Run larger context steps even if VRAM is critical
  --keep-alive VALUE         Ollama keep_alive for resident tests (default: $KEEP_ALIVE)
  --temperature X            Temperature (default: $TEMPERATURE)
  --timeout-sec N            Request timeout (default: $TIMEOUT_SEC)
  --evidence-level LEVEL     compact|standard|full (default: $EVIDENCE_LEVEL)
  --route-only               Resolve model/role and print route without running
  --zip / --no-zip           Create final ZIP (default: $ZIP_ON_EXIT)
  --strict-exit              Nonzero for unsupported/skipped review states in CI
  -h, --help                 Show help
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_PATTERN="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --full) FULL=1; MODE="diagnostic"; shift ;;
    --mode) MODE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --profile) PROFILE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-ctx) NUM_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-predict) NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --quick) MODE="quick"; NUM_PREDICT="$QUICK_PREDICT"; shift ;;
    --min-context) MIN_CONTEXT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --context-steps) CONTEXT_STEPS="$(ollama_require_arg_value "$1" "${2-}")"; CONTEXT_STEPS_USER=1; shift 2 ;;
    --min-context-eval) MIN_CONTEXT_EVAL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --min-context-chars) MIN_CONTEXT_CHARS="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --min-context-fill) MIN_CONTEXT_FILL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --force-context-pressure) FORCE_CONTEXT_PRESSURE=1; shift ;;
    --keep-alive) KEEP_ALIVE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --temperature) TEMPERATURE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --think) THINK="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --evidence-level) EVIDENCE_LEVEL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --route-only|--dry-run) ROUTE_ONLY=1; shift ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    --terminal-summary) PRINT_TERMINAL_SUMMARY=1; shift ;;
    --no-terminal-summary) PRINT_TERMINAL_SUMMARY=0; shift ;;
    --strict-exit) STRICT_EXIT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) ollama_die "unknown option: $1" ;;
    *) if [[ -z "$MODEL_PATTERN" ]]; then MODEL_PATTERN="$1"; else ollama_die "only one model per direct test script invocation; use scripts/ollama.sh test for multi-model"; fi; shift ;;
  esac
done

# Auto context ladder for --full / context-pressure when user did not override steps.
if [[ "$CONTEXT_STEPS_USER" -eq 0 && ( "$FULL" -eq 1 || "$MODE" == "context-pressure" || "$MODE" == "diagnostic" ) ]]; then
  mapfile -t _steps < <(python3 - <<PY "$NUM_CTX" "$MIN_CONTEXT"
import sys
base=int(float(sys.argv[1])); target=int(float(sys.argv[2]))
vals=[4096,8192,16384,32768,65536,target]
vals=sorted(set(v for v in vals if v>=base and v<=max(target, base)))
if base not in vals: vals=[base]+vals
print('\n'.join(map(str, vals)))
PY
)
  CONTEXT_STEPS="$(IFS=,; echo "${_steps[*]}")"
fi

if [[ -z "$MODEL_PATTERN" ]]; then
  usage
  echo
  ollama_status_short_common "$BASE_URL" || true
  echo
  ollama_print_available_model_commands "$BASE_URL" "ollama test"
  exit 0
fi

ollama_need_cmd jq
ollama_need_cmd python3
ollama_api_ready "$BASE_URL" 3 || ollama_die "Ollama API is not ready at $BASE_URL"
MODEL="$(ollama_resolve_model "$MODEL_PATTERN" "$BASE_URL")"
ROLE="$(ollama_model_role "$MODEL" "$BASE_URL" 2>/dev/null || echo unknown)"
if [[ "$ROUTE_ONLY" -eq 1 ]]; then
  echo "model=$MODEL role=$ROLE route=ollama-test mode=$MODE profile=$PROFILE min_context=$MIN_CONTEXT context_steps=$CONTEXT_STEPS"
  exit 0
fi

MODEL_SAFE="$(ollama_sanitize_name "$MODEL")"
RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
mkdir -p "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
SUMMARY_CSV="$RUN_DIR/summary.csv"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"

log() { ollama_log "$*"; }

log "ollama-test-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Model: $MODEL"
log "Role: $ROLE"
log "Plan: mode=$MODE profile=$PROFILE ctx=$NUM_CTX predict=$NUM_PREDICT think=$THINK keep_alive=$KEEP_ALIVE context_steps=$CONTEXT_STEPS min_context=$MIN_CONTEXT evidence_level=$EVIDENCE_LEVEL"

ollama_status_short_common "$BASE_URL" | ollama_timestamp_stream || true
ollama_capture_environment_summary "$RUN_DIR/environment-summary.md" "$RUN_DIR" "$MODEL" "$BASE_URL" || true
ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-before.json" "$RUN_DIR/ollama-ps-before.txt" || true
PRE_RUN_RESIDENT_MODELS="$(ollama_ps_model_names "$RUN_DIR/ollama-api-ps-before.json" | paste -sd ',' - || true)"
[[ -n "$PRE_RUN_RESIDENT_MODELS" ]] || PRE_RUN_RESIDENT_MODELS="none"
PRE_RUN_VRAM_PCT=""
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits >"$RUN_DIR/nvidia-smi-query-before.csv" 2>/dev/null || true
  nvidia-smi >"$RUN_DIR/nvidia-smi-before.txt" 2>/dev/null || true
  PRE_RUN_VRAM_PCT="$(awk -F, 'NR==1{u=$6+0;t=$7+0;if(t>0) printf "%.1f", u*100/t;}' "$RUN_DIR/nvidia-smi-query-before.csv" 2>/dev/null || true)"
fi
cat >"$RUN_DIR/run-metrics.json" <<EOF_METRICS
{"pre_run_vram_pct":"$PRE_RUN_VRAM_PCT","pre_run_resident_models":"$PRE_RUN_RESIDENT_MODELS","preload_wait_s":null,"preload_status":"not_run"}
EOF_METRICS

cat >"$RUN_DIR/test-plan-preview.md" <<EOF_PLAN
# Test plan preview

model: $MODEL
role: $ROLE
mode: $MODE
profile: $PROFILE
baseline_context: $NUM_CTX
prediction_length: $NUM_PREDICT
think: $THINK
context_steps: $CONTEXT_STEPS
min_context: $MIN_CONTEXT
min_context_eval: $MIN_CONTEXT_EVAL
min_context_chars: $MIN_CONTEXT_CHARS
min_context_fill: $MIN_CONTEXT_FILL

Selected lanes:
- resident-warm ADOS capability prompts for default daily comparison.
- empty-card first-load check only in --full/diagnostic/empty-card modes.
- context-pressure checks only in --full/diagnostic/context-pressure modes.
- Hermes main chat is not confirmed unless a context step >= min_context passes.

Mandatory gates:
- generation models must produce visible output for capability rows.
- thinking-only visible rows are not counted as visible-answer performance.
- context rows require prompt-fill, eval-token, and response-char gates.
EOF_PLAN

if [[ "$ROLE" == "embedding" ]]; then
  cat >"$SUMMARY_CSV" <<EOF_CSV
timestamp,test,mode,category,endpoint,result_state,sample_status,ctx,predict,prompt_tokens,eval_tokens,decode_tps_raw,visible_answer_tps,ttft_any_ms,ttft_answer_ms,load_s,total_s,response_chars,thinking_chars,thinking_only,http,done_reason,notes
$(ollama_now_iso),unsupported_generation_model,generation,preflight,/api/generate,UNSUPPORTED,UNSUPPORTED,,,,,,,,,,,,,,0,0,0,200,,embedding-only model; use ollama embed-test $MODEL
EOF_CSV
  echo "# Unsupported generation model" >"$RUN_DIR/summary.md"
  echo "Model $MODEL is embedding-only. Use: ollama embed-test $MODEL" >>"$RUN_DIR/summary.md"
  echo "Next: ollama embed-test $MODEL" >"$RUN_DIR/failure-hints.txt"
  "$SCRIPT_DIR/ollama-summarize-results.py" --run-dir "$RUN_DIR" --model "$MODEL" --role "$ROLE" --base-url "$BASE_URL" --profile "$PROFILE" --mode "$MODE" --ctx "$NUM_CTX" --keep-alive "$KEEP_ALIVE" --min-context "$MIN_CONTEXT" --min-context-eval "$MIN_CONTEXT_EVAL" --min-context-chars "$MIN_CONTEXT_CHARS" --min-context-fill "$MIN_CONTEXT_FILL" >/dev/null || true
  cat "$TERMINAL_SUMMARY" 2>/dev/null || true
  exit 2
fi

cat >"$SUMMARY_CSV" <<'EOF_CSV'
timestamp,test,mode,category,endpoint,result_state,sample_status,ctx,predict,prompt_tokens,eval_tokens,decode_tps_raw,visible_answer_tps,ttft_any_ms,ttft_answer_ms,load_s,total_s,response_chars,thinking_chars,thinking_only,http,done_reason,notes
EOF_CSV

coding_prompt='Write a complete Python solution for top_k_frequent(nums, k). Requirements: return the k most frequent integers, break ties by smaller integer first, include a short explanation, and include pytest tests. Put code in a Python code block.'
essay_prompt='Write a structured essay for a technical founder about why execution-state materialization improves AI-agent reliability. Include thesis, three arguments, one counterargument, and a practical conclusion.'
internet_prompt='You are a local Ollama model running without browser tools. Explain whether you can access live internet/current webpages right now, and give a safe answer policy for current facts.'

make_long_prompt() {
  local ctx="$1"
  python3 - <<'PY' "$ctx"
import sys
ctx=int(float(sys.argv[1]))
# Approximate a long prompt that fills most of requested context without being unbounded.
# Numbered pseudo-words resist over-compression better than repeated identical words.
words=max(1500, int(ctx*0.75))
print('This is a context-window validation document. The benchmark should summarize it after reading the whole text.')
for i in range(words):
    print(f'w{i:05d}', end=' ')
    if i and i % 32 == 0:
        print()
print('\n\nTask: summarize the document in eight precise bullets, mention the first token w00000 and the last visible token, and state whether the context was handled.')
PY
}

current_vram_pct() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | awk -F, 'NR==1{u=$1+0;t=$2+0;if(t>0) printf "%.1f", u*100/t; else print 0}'
  else echo 0; fi
}

append_row_from_metrics() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" metrics="$6" notes="$7"
  local http prompt eval raw vis ttfta ttftans loads totals resp think thinkonly done state sample ts fillpct
  http="$(jq -r '.http_code // 0' "$metrics")"
  prompt="$(jq -r '.prompt_eval_tokens // 0' "$metrics")"
  eval="$(jq -r '.eval_tokens // 0' "$metrics")"
  raw="$(jq -r 'if .decode_tps_raw==null then "" else (.decode_tps_raw|tostring) end' "$metrics")"
  vis="$(jq -r 'if .visible_answer_tps==null then "" else (.visible_answer_tps|tostring) end' "$metrics")"
  ttfta="$(jq -r 'if .ttft_any_ms==null then "" else (.ttft_any_ms|tostring) end' "$metrics")"
  ttftans="$(jq -r 'if .ttft_answer_ms==null then "" else (.ttft_answer_ms|tostring) end' "$metrics")"
  loads="$(jq -r '.load_s // 0' "$metrics")"
  totals="$(jq -r '.total_s // 0' "$metrics")"
  resp="$(jq -r '.response_chars // 0' "$metrics")"
  think="$(jq -r '.thinking_chars // 0' "$metrics")"
  thinkonly="$(jq -r 'if .thinking_only then 1 else 0 end' "$metrics")"
  done="$(jq -r '.done_reason // ""' "$metrics" | tr ',' ';')"
  ts="$(ollama_now_iso)"
  state="PASS"; sample="OK"
  if [[ "$http" -ge 400 || "$http" -eq 0 ]]; then
    state="FAIL"; sample="API_ERROR"
    local api_error
    api_error="$(jq -r '.api_error // .error_body // .error // ""' "$metrics" 2>/dev/null | tr '\n,' '  ' | sed 's/  */ /g; s/"/'"'"'/g' | cut -c1-240)"
    [[ -n "$api_error" ]] && notes="$notes api_error=$api_error"
  fi
  if [[ "$thinkonly" == "1" || ( "$resp" -eq 0 && "$think" -gt 0 ) ]]; then sample="FAIL_VISIBLE_OUTPUT"; state="INCONCLUSIVE"; fi
  if [[ "$category" == "context" && "$state" == "PASS" ]]; then
    fillpct="$(awk -v p="$prompt" -v c="$ctx" 'BEGIN{if(c>0) printf "%.4f", p/c; else print 0}')"
    if awk -v f="$fillpct" -v min="$MIN_CONTEXT_FILL" 'BEGIN{exit !(f<min)}'; then
      sample="UNDERFILLED"; state="INCONCLUSIVE"
    elif [[ "$eval" -lt "$MIN_CONTEXT_EVAL" || "$resp" -lt "$MIN_CONTEXT_CHARS" ]]; then
      sample="SHORT_CONTEXT_SAMPLE"; state="INCONCLUSIVE"
    fi
  fi
  if [[ "$resp" -lt 80 && "$category" != context && "$state" == "PASS" ]]; then sample="NEEDS_REVIEW"; fi
  if [[ "$category" == "coding" && "$state" == "PASS" ]]; then
    local text_file="$RUN_DIR/raw/${test}.text"
    jq -r '.chunk.response // ""' "$RUN_DIR/raw/${test}.ndjson" 2>/dev/null >"$text_file" || true
    if ! grep -Eq 'def +top_k_frequent|Counter|pytest|assert' "$text_file"; then sample="NEEDS_REVIEW"; fi
    if grep -q '```python' "$text_file"; then
      python3 - <<'PY' "$text_file" "$RUN_DIR/raw/${test}.pycheck" || true
import re,sys,py_compile,tempfile,os
text=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
blocks=re.findall(r'```python\n(.*?)```', text, flags=re.S)
status='NO_CODE_BLOCK'
if blocks:
    code=blocks[0]
    fd,path=tempfile.mkstemp(suffix='.py')
    os.write(fd,code.encode()); os.close(fd)
    try:
        py_compile.compile(path,doraise=True); status='PY_COMPILE_PASS'
    except Exception as e:
        status='PY_COMPILE_FAIL:'+str(e).split('\n')[0]
    os.unlink(path)
open(sys.argv[2],'w').write(status+'\n')
PY
    fi
  fi
  if [[ "$category" == "internet_access" && "$state" == "PASS" ]]; then
    local text_file="$RUN_DIR/raw/${test}.text"
    jq -r '.chunk.response // ""' "$RUN_DIR/raw/${test}.ndjson" 2>/dev/null >"$text_file" || true
    if ! grep -Eiq "(cannot|can't|do not|don't|no live|no internet|not have).*(internet|web|browse|current|live)|without.*(browser|internet)" "$text_file"; then sample="NEEDS_REVIEW"; fi
  fi
  printf '%s,%s,%s,%s,/api/generate,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ts" "$test" "$mode" "$category" "$state" "$sample" "$ctx" "$predict" "$prompt" "$eval" "$raw" "$vis" "$ttfta" "$ttftans" "$loads" "$totals" "$resp" "$think" "$thinkonly" "$http" "$done" "$(printf '%s' "$notes" | tr ',' ';')" >>"$SUMMARY_CSV"
}

run_generate_row() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" prompt="$6" notes="${7:-}"
  local payload="$PAYLOAD_DIR/${test}.json" raw="$RAW_DIR/${test}.ndjson" metrics="$RAW_DIR/${test}.metrics.json" http="$RAW_DIR/${test}.http" err="$RAW_DIR/${test}.stderr"
  log "START $test: mode=$mode category=$category model=$MODEL ctx=$ctx predict=$predict"
  if [[ "$THINK" == "none" || -z "$THINK" ]]; then
    jq -nc --arg model "$MODEL" --arg prompt "$prompt" --arg keep_alive "$KEEP_ALIVE" --argjson ctx "$ctx" --argjson predict "$predict" --argjson temp "$TEMPERATURE" \
      '{model:$model,prompt:$prompt,stream:true,keep_alive:$keep_alive,options:{num_ctx:$ctx,num_predict:$predict,temperature:$temp}}' >"$payload"
  elif [[ "$THINK" == "true" || "$THINK" == "false" ]]; then
    jq -nc --arg model "$MODEL" --arg prompt "$prompt" --arg keep_alive "$KEEP_ALIVE" --argjson think "$THINK" --argjson ctx "$ctx" --argjson predict "$predict" --argjson temp "$TEMPERATURE" \
      '{model:$model,prompt:$prompt,stream:true,keep_alive:$keep_alive,think:$think,options:{num_ctx:$ctx,num_predict:$predict,temperature:$temp}}' >"$payload"
  else
    jq -nc --arg model "$MODEL" --arg prompt "$prompt" --arg keep_alive "$KEEP_ALIVE" --arg think "$THINK" --argjson ctx "$ctx" --argjson predict "$predict" --argjson temp "$TEMPERATURE" \
      '{model:$model,prompt:$prompt,stream:true,keep_alive:$keep_alive,think:$think,options:{num_ctx:$ctx,num_predict:$predict,temperature:$temp}}' >"$payload"
  fi
  "$SCRIPT_DIR/ollama-run-generate.py" --base-url "$BASE_URL" --payload "$payload" --raw "$raw" --metrics "$metrics" --http-file "$http" --stderr-file "$err" --timeout "$TIMEOUT_SEC" || true
  append_row_from_metrics "$test" "$mode" "$category" "$ctx" "$predict" "$metrics" "$notes"
  log "DONE  $test http=$(cat "$http" 2>/dev/null || echo 0) eval=$(jq -r '.eval_tokens // 0' "$metrics") visible_tps=$(jq -r '.visible_answer_tps // ""' "$metrics") ttft=$(jq -r '.ttft_answer_ms // ""' "$metrics")"
}

skip_row() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" notes="$6"
  printf '%s,%s,%s,%s,/api/generate,SKIPPED,SKIPPED,%s,%s,,,,,,,,,,,,,,%s\n' "$(ollama_now_iso)" "$test" "$mode" "$category" "$ctx" "$predict" "$(printf '%s' "$notes" | tr ',' ';')" >>"$SUMMARY_CSV"
}

preload_model() {
  local payload="$PAYLOAD_DIR/preload.json" raw="$RAW_DIR/preload.ndjson" metrics="$RAW_DIR/preload.metrics.json" http="$RAW_DIR/preload.http" err="$RAW_DIR/preload.stderr"
  jq -nc --arg model "$MODEL" --arg keep_alive "$KEEP_ALIVE" --argjson ctx "$NUM_CTX" '{model:$model,prompt:"",stream:true,keep_alive:$keep_alive,options:{num_ctx:$ctx,num_predict:1}}' >"$payload"
  "$SCRIPT_DIR/ollama-run-generate.py" --base-url "$BASE_URL" --payload "$payload" --raw "$raw" --metrics "$metrics" --http-file "$http" --stderr-file "$err" --timeout "$TIMEOUT_SEC" >/dev/null 2>&1 || true
  cat "$http" 2>/dev/null || echo 0
}

update_run_metrics_preload() {
  local wait_s="$1" status="$2"
  python3 - <<'PY' "$RUN_DIR/run-metrics.json" "$wait_s" "$status"
import json,sys,pathlib
p=pathlib.Path(sys.argv[1])
try: obj=json.loads(p.read_text())
except Exception: obj={}
obj['preload_wait_s']=float(sys.argv[2])
obj['preload_status']=sys.argv[3]
p.write_text(json.dumps(obj,indent=2)+"\n")
PY
  cat >"$RUN_DIR/preload-state.txt" <<EOF_PRELOAD
preload_wait_s=$wait_s
preload_status=$status
EOF_PRELOAD
}

run_empty_card_lane() {
  log "LoadMode: empty-card requested; unloading resident Ollama models"
  local unloaded; unloaded="$(ollama_unload_all_resident "$BASE_URL" "$RUN_DIR" || true)"
  ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-after-empty-card-unload.json" "$RUN_DIR/ollama-ps-after-empty-card-unload.txt" || true
  cat >"$RUN_DIR/load-state.txt" <<EOF_LOAD
load_mode=empty-card
empty_card_requested=1
resident_models_before_unload=$unloaded
note=ColdVerified means model-residency preconditions were checked; it is not a disk-cache claim.
EOF_LOAD
  run_generate_row "01_empty_card_coding_load" "empty-card" "coding" "$NUM_CTX" "$NUM_PREDICT" "$coding_prompt" "first-load coding capability row"
}

run_resident_warm_lane() {
  log "ResidentWarm: preloading/verifying model with keep_alive=$KEEP_ALIVE"
  local start_ns end_ns wait_s http_status
  start_ns="$(date +%s%N)"
  http_status="$(preload_model)"
  end_ns="$(date +%s%N)"
  wait_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.3f", (e-s)/1000000000}')"
  update_run_metrics_preload "$wait_s" "http_$http_status"
  ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-before-resident-warm.json" "$RUN_DIR/ollama-ps-before-resident-warm.txt" || true
  run_generate_row "02_resident_coding_prompt" "resident-warm" "coding" "$NUM_CTX" "$NUM_PREDICT" "$coding_prompt" "warm coding prompt"
  run_generate_row "03_resident_essay_prompt" "resident-warm" "essay" "$NUM_CTX" "$NUM_PREDICT" "$essay_prompt" "warm essay prompt"
  run_generate_row "04_resident_internet_access_prompt" "resident-warm" "internet_access" "$NUM_CTX" "$NUM_PREDICT" "$internet_prompt" "warm internet-access boundary prompt"
}

run_context_pressure_lane() {
  log "ContextPressure: steps=$CONTEXT_STEPS min_context=$MIN_CONTEXT"
  local step idx=0 vram prompt prev_failed=0
  IFS=',' read -r -a steps <<< "$CONTEXT_STEPS"
  for step in "${steps[@]}"; do
    [[ -n "$step" ]] || continue
    idx=$((idx+1))
    if [[ "$prev_failed" -eq 1 && "$FORCE_CONTEXT_PRESSURE" -ne 1 ]]; then
      skip_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "skipped because lower context step failed or was inconclusive; use --force-context-pressure to override"
      continue
    fi
    vram="$(current_vram_pct)"
    if [[ "$FORCE_CONTEXT_PRESSURE" -ne 1 && "$step" -gt "$NUM_CTX" ]]; then
      if awk -v v="$vram" 'BEGIN{exit !(v>97)}'; then
        skip_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "skipped because current VRAM ${vram}% exceeds 97%; use --force-context-pressure to override"
        prev_failed=1
        continue
      fi
    fi
    prompt="$(make_long_prompt "$step")"
    run_generate_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "$prompt" "context pressure step; pre_step_vram_pct=$vram"
    # Stop higher steps if the row was not a context pass, unless forced.
    if [[ "$FORCE_CONTEXT_PRESSURE" -ne 1 ]]; then
      local last_sample
      last_sample="$(tail -1 "$SUMMARY_CSV" | awk -F, '{print $7}')"
      if [[ "$last_sample" != "OK" ]]; then prev_failed=1; fi
    fi
  done
}

case "$MODE" in
  diagnostic) run_empty_card_lane; run_resident_warm_lane; run_context_pressure_lane ;;
  quick) run_resident_warm_lane ;;
  empty-card) run_empty_card_lane ;;
  resident-warm) run_resident_warm_lane ;;
  context-pressure) run_context_pressure_lane ;;
  perf)
    run_empty_card_lane
    run_generate_row "02_perf_decode512" "perf" "throughput" "$NUM_CTX" "512" "Write a detailed deterministic benchmark paragraph about local LLM performance. Continue until the token budget is reached." "perf decode512"
    run_generate_row "03_perf_decode1024" "perf" "sustained" "$NUM_CTX" "1024" "Write a long deterministic benchmark essay about local LLM performance. Continue until the token budget is reached." "perf decode1024"
    ;;
  *) ollama_die "unknown mode: $MODE" ;;
esac

ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-after.json" "$RUN_DIR/ollama-ps-after.txt" || true
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits >"$RUN_DIR/nvidia-smi-query-after.csv" 2>/dev/null || true
  nvidia-smi >"$RUN_DIR/nvidia-smi-after.txt" 2>/dev/null || true
fi
if command -v journalctl >/dev/null 2>&1; then journalctl -u ollama.service -n 400 --no-pager >"$RUN_DIR/ollama-server-log-tail.txt" 2>/dev/null || true; fi
[[ -f "$RUN_DIR/ollama-server-log-tail.txt" ]] || : >"$RUN_DIR/ollama-server-log-tail.txt"
ollama_parse_runner_log "$RUN_DIR/ollama-server-log-tail.txt" "$RUN_DIR/runner-log-facts.md" || true

{
  echo "# ADOS capability analysis"
  echo
  echo "Model: $MODEL"
  echo "Profile: $PROFILE"
  echo
  echo "| Probe | Verdict | Evidence |"
  echo "|---|---|---|"
  while IFS=, read -r timestamp test mode category endpoint result sample ctx predict prompt_tokens eval_tokens raw_tps visible_tps ttft_any ttft_ans load total resp think thinkonly http done notes; do
    [[ "$test" == "test" ]] && continue
    [[ "$category" =~ coding|essay|internet_access ]] || continue
    echo "| $test | $sample | response_chars=$resp thinking_chars=$think visible_tps=${visible_tps:-NA} |"
  done <"$SUMMARY_CSV"
  echo
  echo "Thinking-only rows are not counted as visible-output successes. Coding rows use static code-response checks; internet rows use denial/boundary checks."
} >"$RUN_DIR/capability-analysis.md"

"$SCRIPT_DIR/ollama-summarize-results.py" --run-dir "$RUN_DIR" --model "$MODEL" --role "$ROLE" --base-url "$BASE_URL" --profile "$PROFILE" --mode "$MODE" --ctx "$NUM_CTX" --keep-alive "$KEEP_ALIVE" --min-context "$MIN_CONTEXT" --min-context-eval "$MIN_CONTEXT_EVAL" --min-context-chars "$MIN_CONTEXT_CHARS" --min-context-fill "$MIN_CONTEXT_FILL" >"$RUN_DIR/summarizer.stdout" 2>"$RUN_DIR/summarizer.stderr" || true
[[ "$PRINT_TERMINAL_SUMMARY" -eq 1 ]] && cat "$TERMINAL_SUMMARY" 2>/dev/null || true

if [[ "$EVIDENCE_LEVEL" == "compact" ]]; then
  find "$RAW_DIR" -type f \( -name '*.ndjson' -o -name '*.stderr' \) -delete 2>/dev/null || true
fi

if [[ "$ZIP_ON_EXIT" -eq 1 ]]; then
  mkdir -p "$TMP_DIR"
  ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-${MODEL_SAFE}-${RUN_ID}.zip"
  (cd "$(dirname "$RUN_DIR")" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  echo "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  log "zip: $ARCHIVE_PATH"
fi

SUMMARY_STATUS="$(awk -F': ' '/^- status:/{print $2; exit}' "$RUN_DIR/summary.md" 2>/dev/null || true)"
if [[ "$STRICT_EXIT" -eq 1 ]]; then
  if grep -q ',FAIL,' "$SUMMARY_CSV" || grep -q 'FAIL_VISIBLE_OUTPUT' "$SUMMARY_CSV"; then exit 1; fi
fi
case "$SUMMARY_STATUS" in
  TOOL_FAILURE|FAIL|NO_ROWS) exit 1 ;;
  UNSUPPORTED) exit 2 ;;
  *) exit 0 ;;
esac
