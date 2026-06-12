#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"

VERSION="1.11.0-final"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v1.11-final-context-gates-fast-default"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
MODEL_PATTERN=""
MODEL=""
MODE="${MODE:-resident-warm}"
PROFILE="ados"
NUM_CTX="${NUM_CTX:-4096}"
NUM_PREDICT="${NUM_PREDICT:-1024}"
QUICK_PREDICT="${QUICK_PREDICT:-512}"
TEMPERATURE="${TEMPERATURE:-0.2}"
KEEP_ALIVE="${KEEP_ALIVE:-24h}"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"
PRINT_TERMINAL_SUMMARY="${PRINT_TERMINAL_SUMMARY:-1}"
ROUTE_ONLY=0
EVIDENCE_LEVEL="${EVIDENCE_LEVEL:-standard}"
STRICT_EXIT=0
FORCE_CONTEXT_PRESSURE=0
CONTEXT_STEPS="${CONTEXT_STEPS:-4096,8192,16384}"
THINK="${THINK:-false}"
MIN_CONTEXT_EVAL_TOKENS="${MIN_CONTEXT_EVAL_TOKENS:-128}"
MIN_CONTEXT_RESPONSE_CHARS="${MIN_CONTEXT_RESPONSE_CHARS:-200}"

usage() {
  cat <<EOF_USAGE
ollama-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Usage:
  ollama-test-RTX3090.sh MODEL [options]

Default behavior:
  Runs resident-warm ADOS capability prompts for fast daily comparison. Use
  `ollama diagnose MODEL` or `--mode diagnostic` for empty-card first-load and
  safe context-pressure checks.

Options:
  --model MODEL              Model or local pattern
  --mode MODE                diagnostic|quick|empty-card|resident-warm|context-pressure|perf
  --profile PROFILE          ados|perf (default: ados)
  --num-ctx N                Baseline context (default: $NUM_CTX)
  --num-predict N            ADOS capability prediction length (default: $NUM_PREDICT)
  --quick                    Shortcut for a short resident-warm capability run
  --context-steps CSV        Context pressure steps (default: $CONTEXT_STEPS)
  --force-context-pressure   Run larger context steps even if VRAM is already critical
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
    --mode) MODE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --profile) PROFILE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-ctx) NUM_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-predict) NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --quick) MODE="quick"; NUM_PREDICT="$QUICK_PREDICT"; shift ;;
    --context-steps) CONTEXT_STEPS="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
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
  echo "model=$MODEL role=$ROLE route=ollama-test mode=$MODE profile=$PROFILE"
  exit 0
fi

MODEL_SAFE="$(ollama_sanitize_name "$MODEL")"
RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
mkdir -p "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
SUMMARY_CSV="$RUN_DIR/summary.csv"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
ARCHIVE_PATH=""

log() { ollama_log "$*"; }

log "ollama-test-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Model: $MODEL"
log "Role: $ROLE"
log "Plan: mode=$MODE profile=$PROFILE ctx=$NUM_CTX predict=$NUM_PREDICT think=$THINK keep_alive=$KEEP_ALIVE context_steps=$CONTEXT_STEPS evidence_level=$EVIDENCE_LEVEL min_context_eval=$MIN_CONTEXT_EVAL_TOKENS min_context_chars=$MIN_CONTEXT_RESPONSE_CHARS"

ollama_status_short_common "$BASE_URL" | ollama_timestamp_stream || true
ollama_capture_environment_summary "$RUN_DIR/environment-summary.md" "$RUN_DIR" "$MODEL" "$BASE_URL" || true
ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-before.json" "$RUN_DIR/ollama-ps-before.txt" || true
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits >"$RUN_DIR/nvidia-smi-query-before.csv" 2>/dev/null || true
  nvidia-smi >"$RUN_DIR/nvidia-smi-before.txt" 2>/dev/null || true
fi

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

Selected lanes:
- empty-card first-load check when mode is diagnostic, quick, or empty-card.
- resident-warm ADOS capability prompts when mode is diagnostic, quick, or resident-warm.
- safe context-pressure checks when mode is diagnostic or context-pressure.
- setting recommendation output for WSL2/systemd Ollama service.

Mandatory gates:
- generation models must produce visible output for capability rows.
- thinking-only visible rows are not counted as visible-answer performance.
- context increases are skipped when VRAM is already critical unless forced.
- context-pressure rows require eval_tokens >= $MIN_CONTEXT_EVAL_TOKENS and response_chars >= $MIN_CONTEXT_RESPONSE_CHARS; shorter rows are INCONCLUSIVE and cannot validate settings.
EOF_PLAN

if [[ "$ROLE" == "embedding" ]]; then
  cat >"$SUMMARY_CSV" <<EOF_CSV
timestamp,test,mode,category,endpoint,result_state,sample_status,ctx,predict,prompt_tokens,eval_tokens,decode_tps_raw,visible_answer_tps,ttft_any_ms,ttft_answer_ms,load_s,total_s,response_chars,thinking_chars,thinking_only,http,done_reason,notes
$(ollama_now_iso),unsupported_generation_model,generation,preflight,/api/generate,UNSUPPORTED,UNSUPPORTED,,,,,,,,,,,,,,0,0,0,200,,embedding-only model; use ollama embed-test $MODEL
EOF_CSV
  echo "# Unsupported generation model" >"$RUN_DIR/summary.md"
  echo "Model $MODEL is embedding-only. Use: ollama embed-test $MODEL" >>"$RUN_DIR/summary.md"
  echo "Next: ollama embed-test $MODEL" >"$RUN_DIR/failure-hints.txt"
  "$SCRIPT_DIR/ollama-summarize-results.py" --run-dir "$RUN_DIR" --model "$MODEL" --role "$ROLE" --base-url "$BASE_URL" --profile "$PROFILE" --mode "$MODE" --ctx "$NUM_CTX" --keep-alive "$KEEP_ALIVE" >/dev/null || true
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
  local words="$1" out="This is a context pressure document. " i
  for ((i=0;i<words;i++)); do out+="alpha${i} beta${i} gamma${i} delta${i}. "; done
  out+="\nSummarize the document constraints in exactly five bullets and state whether the context was handled."
  printf '%s' "$out"
}

current_vram_pct() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | awk -F, 'NR==1{u=$1+0;t=$2+0;if(t>0) printf "%.1f", u*100/t; else print 0}'
  else echo 0; fi
}

append_row_from_metrics() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" metrics="$6" notes="$7"
  local http prompt eval raw vis ttfta ttftans loads totals resp think thinkonly done state sample ts
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
  if [[ "$thinkonly" == "1" ]]; then sample="FAIL_VISIBLE_OUTPUT"; state="INCONCLUSIVE"; fi
  if [[ "$resp" -eq 0 && "$think" -gt 0 ]]; then sample="FAIL_VISIBLE_OUTPUT"; state="INCONCLUSIVE"; fi
  if [[ "$resp" -lt 80 && "$category" != context* && "$state" == "PASS" ]]; then sample="NEEDS_REVIEW"; fi
  if [[ "$category" == "coding" && "$state" == "PASS" ]]; then
    local text_file="$RUN_DIR/raw/${test}.text"
    jq -r '.chunk.response // ""' "$RUN_DIR/raw/${test}.ndjson" 2>/dev/null >"$text_file" || true
    if ! grep -Eq 'def +top_k_frequent|Counter|pytest|assert' "$text_file"; then sample="NEEDS_REVIEW"; fi
    if grep -q '```python' "$text_file"; then
      python3 - <<'PY' "$text_file" "$RUN_DIR/raw/${test}.pycheck" || true
import re,sys,py_compile,tempfile,os
text=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
blocks=re.findall(r'```python\n(.*?)```', text, flags=re.S)
out=[]
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
  # Final v1.11 context-pressure gate: accepting a large ctx with one token is not validation.
  # Short context rows prove only request acceptance; they cannot confirm context settings or speed.
  if [[ "$category" == "context" && "$state" == "PASS" ]]; then
    if (( eval < MIN_CONTEXT_EVAL_TOKENS || resp < MIN_CONTEXT_RESPONSE_CHARS )); then
      state="INCONCLUSIVE"
      sample="SHORT_CONTEXT_SAMPLE"
      notes="$notes min_context_eval=$MIN_CONTEXT_EVAL_TOKENS min_context_chars=$MIN_CONTEXT_RESPONSE_CHARS"
      vis=""
      raw=""
    fi
  fi
  if [[ -n "$vis" && "$eval" -gt 0 && "$eval" -lt 8 ]]; then
    # Hard guard against distorted rates from tiny final-duration rows.
    vis=""
    raw=""
  fi
  printf '%s,%s,%s,%s,/api/generate,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ts" "$test" "$mode" "$category" "$state" "$sample" "$ctx" "$predict" "$prompt" "$eval" "$raw" "$vis" "$ttfta" "$ttftans" "$loads" "$totals" "$resp" "$think" "$thinkonly" "$http" "$done" "$(printf '%s' "$notes" | tr ',' ';')" >>"$SUMMARY_CSV"
}

run_generate_row() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" prompt="$6" notes="${7:-}"
  local payload="$PAYLOAD_DIR/${test}.json" raw="$RAW_DIR/${test}.ndjson" metrics="$RAW_DIR/${test}.metrics.json" http="$RAW_DIR/${test}.http" err="$RAW_DIR/${test}.stderr"
  log "START $test: mode=$mode category=$category model=$MODEL ctx=$ctx predict=$predict"
  # v1.11: serialize think as a typed JSON value. v1.10 sent "false" as a string,
  # which Ollama rejects with: invalid think value: "false".
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
  local done_eval done_vis done_ttft
  done_eval="$(jq -r '.eval_tokens // 0' "$metrics")"
  done_vis="$(jq -r '.visible_answer_tps // ""' "$metrics")"
  done_ttft="$(jq -r '.ttft_answer_ms // ""' "$metrics")"
  if [[ "$category" == "context" && "$done_eval" -lt "$MIN_CONTEXT_EVAL_TOKENS" ]]; then
    done_vis="SHORT_SAMPLE"
  fi
  log "DONE  $test http=$(cat "$http" 2>/dev/null || echo 0) eval=$done_eval visible_tps=$done_vis ttft=$done_ttft"
}

skip_row() {
  local test="$1" mode="$2" category="$3" ctx="$4" predict="$5" notes="$6"
  printf '%s,%s,%s,%s,/api/generate,SKIPPED,SKIPPED,%s,%s,,,,,,,,,,,,,,%s\n' "$(ollama_now_iso)" "$test" "$mode" "$category" "$ctx" "$predict" "$(printf '%s' "$notes" | tr ',' ';')" >>"$SUMMARY_CSV"
}

preload_model() {
  local payload="$PAYLOAD_DIR/preload.json" raw="$RAW_DIR/preload.ndjson" metrics="$RAW_DIR/preload.metrics.json" http="$RAW_DIR/preload.http" err="$RAW_DIR/preload.stderr"
  jq -nc --arg model "$MODEL" --arg keep_alive "$KEEP_ALIVE" --argjson ctx "$NUM_CTX" '{model:$model,prompt:"",stream:true,keep_alive:$keep_alive,options:{num_ctx:$ctx,num_predict:1}}' >"$payload"
  "$SCRIPT_DIR/ollama-run-generate.py" --base-url "$BASE_URL" --payload "$payload" --raw "$raw" --metrics "$metrics" --http-file "$http" --stderr-file "$err" --timeout "$TIMEOUT_SEC" >/dev/null 2>&1 || true
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
  preload_model
  ollama_capture_ollama_ps "$BASE_URL" "$RUN_DIR/ollama-api-ps-before-resident-warm.json" "$RUN_DIR/ollama-ps-before-resident-warm.txt" || true
  run_generate_row "02_resident_coding_prompt" "resident-warm" "coding" "$NUM_CTX" "$NUM_PREDICT" "$coding_prompt" "warm coding prompt"
  run_generate_row "03_resident_essay_prompt" "resident-warm" "essay" "$NUM_CTX" "$NUM_PREDICT" "$essay_prompt" "warm essay prompt"
  run_generate_row "04_resident_internet_access_prompt" "resident-warm" "internet_access" "$NUM_CTX" "$NUM_PREDICT" "$internet_prompt" "warm internet-access boundary prompt"
}

run_context_pressure_lane() {
  log "ContextPressure: steps=$CONTEXT_STEPS min_eval=$MIN_CONTEXT_EVAL_TOKENS min_chars=$MIN_CONTEXT_RESPONSE_CHARS"
  local step idx=0 vram prompt halted=0
  IFS=',' read -r -a steps <<< "$CONTEXT_STEPS"
  for step in "${steps[@]}"; do
    [[ -n "$step" ]] || continue
    idx=$((idx+1))
    if [[ "$halted" -eq 1 ]]; then
      skip_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "skipped because a lower context step was inconclusive; use --force-context-pressure to continue"
      continue
    fi
    vram="$(current_vram_pct)"
    if [[ "$FORCE_CONTEXT_PRESSURE" -ne 1 && "$step" -gt "$NUM_CTX" ]]; then
      if awk -v v="$vram" 'BEGIN{exit !(v>97)}'; then
        skip_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "skipped because current VRAM ${vram}% exceeds 97%; use --force-context-pressure to override"
        continue
      fi
    fi
    prompt="$(make_long_prompt $(( step / 6 )))"
    run_generate_row "1${idx}_context_${step}" "context-pressure" "context" "$step" "256" "$prompt" "context pressure step; pre_step_vram_pct=$vram"
    local metrics="$RAW_DIR/1${idx}_context_${step}.metrics.json" eval resp http
    http="$(jq -r '.http_code // 0' "$metrics" 2>/dev/null || echo 0)"
    eval="$(jq -r '.eval_tokens // 0' "$metrics" 2>/dev/null || echo 0)"
    resp="$(jq -r '.response_chars // 0' "$metrics" 2>/dev/null || echo 0)"
    if [[ "$http" -ge 400 || "$eval" -lt "$MIN_CONTEXT_EVAL_TOKENS" || "$resp" -lt "$MIN_CONTEXT_RESPONSE_CHARS" ]]; then
      halted=1
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

# Capability analysis surface.
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

"$SCRIPT_DIR/ollama-summarize-results.py" --run-dir "$RUN_DIR" --model "$MODEL" --role "$ROLE" --base-url "$BASE_URL" --profile "$PROFILE" --mode "$MODE" --ctx "$NUM_CTX" --keep-alive "$KEEP_ALIVE" >"$RUN_DIR/summarizer.stdout" 2>"$RUN_DIR/summarizer.stderr" || true
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
