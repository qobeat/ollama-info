#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.6.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v0.6.0-health-performance-terminal-summary"

MODEL="${MODEL:-qwen3:8b}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
NUM_CTX="${NUM_CTX:-4096}"
LONG_CTX="${LONG_CTX:-8192}"
NUM_PREDICT="${NUM_PREDICT:-512}"
LONG_NUM_PREDICT="${LONG_NUM_PREDICT:-1024}"
TEMPERATURE="${TEMPERATURE:-0.2}"
KEEP_ALIVE="${KEEP_ALIVE:-30m}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
RUN_CONC="${RUN_CONC:-1}"
CONCURRENCY="${CONCURRENCY:-2}"
RUN_CPU="${RUN_CPU:-0}"
PULL_IF_MISSING="${PULL_IF_MISSING:-0}"
ENSURE_SERVER="${ENSURE_SERVER:-1}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"
PRINT_TERMINAL_SUMMARY="${PRINT_TERMINAL_SUMMARY:-1}"
THINK="${THINK:-false}"
PROMPT_PREFIX="${PROMPT_PREFIX:-}"

RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
SUMMARY_CSV="$RUN_DIR/summary.csv"
SUMMARY_MD="$RUN_DIR/summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
META="$RUN_DIR/meta.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
ARCHIVE_PATH=""

usage() {
  cat <<EOF_USAGE
ollama-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Run practical RTX 3090 + Ollama health/performance tests and save raw JSON + CSV/Markdown summaries.

Usage:
  ./ollama-test-RTX3090.sh [options]

Options:
  --model NAME          Model to test (default: $MODEL)
  --base-url URL        Ollama base URL (default: $BASE_URL)
  --out-dir DIR         Output root (default: $OUT_DIR)
  --run-id ID           Override run id
  --num-ctx N           Standard context (default: $NUM_CTX)
  --long-ctx N          Long-context probe context (default: $LONG_CTX)
  --num-predict N       Standard generation length (default: $NUM_PREDICT)
  --long-num-predict N  Sustained generation length (default: $LONG_NUM_PREDICT)
  --temperature X       Generation temperature (default: $TEMPERATURE)
  --timeout-sec N       curl max time per request (default: $TIMEOUT_SEC)
  --concurrency N       Concurrent GPU requests for parallel probe (default: $CONCURRENCY)
  --think VALUE         Ollama top-level think: false|true|none|low|medium|high (default: $THINK)
  --prompt-prefix TEXT  Optional prompt prefix; default is empty
  --run-conc / --no-conc        Enable/disable concurrency probe (default: $RUN_CONC)
  --run-cpu / --no-cpu          Enable/disable CPU-only comparison (default: $RUN_CPU)
  --pull / --no-pull            Pull model if missing (default: $PULL_IF_MISSING)
  --ensure-server / --no-ensure-server  Start/check Ollama server (default: $ENSURE_SERVER)
  --terminal-summary / --no-terminal-summary  Print <=50-line ASCII terminal summary (default: $PRINT_TERMINAL_SUMMARY)
  --zip / --no-zip      Create ~/tmp archive on exit (default: $ZIP_ON_EXIT)
  -h, --help            Show help
EOF_USAGE
}

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; printf '%s WARN: %s\n' "$(date -Is)" "$*" >>"$ERRORS_FILE" 2>/dev/null || true; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 2; }; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
script_dir() { cd -- "$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")" && pwd; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --num-ctx) NUM_CTX="${2:-}"; shift 2 ;;
    --long-ctx) LONG_CTX="${2:-}"; shift 2 ;;
    --num-predict) NUM_PREDICT="${2:-}"; shift 2 ;;
    --long-num-predict) LONG_NUM_PREDICT="${2:-}"; shift 2 ;;
    --temperature) TEMPERATURE="${2:-}"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --think) THINK="${2:-}"; shift 2 ;;
    --prompt-prefix) PROMPT_PREFIX="${2:-}"; shift 2 ;;
    --run-conc) RUN_CONC=1; shift ;;
    --no-conc) RUN_CONC=0; shift ;;
    --run-cpu) RUN_CPU=1; shift ;;
    --no-cpu) RUN_CPU=0; shift ;;
    --pull) PULL_IF_MISSING=1; shift ;;
    --no-pull) PULL_IF_MISSING=0; shift ;;
    --ensure-server) ENSURE_SERVER=1; shift ;;
    --no-ensure-server) ENSURE_SERVER=0; shift ;;
    --terminal-summary) PRINT_TERMINAL_SUMMARY=1; shift ;;
    --no-terminal-summary) PRINT_TERMINAL_SUMMARY=0; shift ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$MODEL" ]] || { echo "ERROR: model is empty" >&2; exit 2; }
for n in NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT TIMEOUT_SEC CONNECT_TIMEOUT_SEC CONCURRENCY; do
  is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }
done
case "$THINK" in true|false|none|low|medium|high) ;; *) echo "ERROR: --think must be false, true, none, low, medium, or high" >&2; exit 2 ;; esac
[[ "$CONCURRENCY" -ge 1 ]] || CONCURRENCY=1

RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
SUMMARY_CSV="$RUN_DIR/summary.csv"
SUMMARY_MD="$RUN_DIR/summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
META="$RUN_DIR/meta.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
mkdir -p "$RUN_DIR" "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
: >"$ERRORS_FILE"

need_cmd curl
need_cmd jq
need_cmd date
need_cmd timeout

ensure_server() {
  if curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" "$BASE_URL/api/tags" >/dev/null 2>&1; then return 0; fi
  [[ "$ENSURE_SERVER" == "1" ]] || { echo "ERROR: Ollama server is not reachable at $BASE_URL" >&2; exit 3; }
  local sd; sd="$(script_dir)"
  if [[ -x "$sd/ollama-start" ]]; then
    BASE_URL="$BASE_URL" "$sd/ollama-start" || true
  elif command -v ollama >/dev/null 2>&1; then
    mkdir -p "$HOME/log"; nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 & sleep 3
  fi
  curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" "$BASE_URL/api/tags" >/dev/null 2>&1 || {
    echo "ERROR: Ollama server still not reachable at $BASE_URL" >&2; exit 3;
  }
}

model_available() {
  curl -fsS "$BASE_URL/api/tags" | jq -e --arg m "$MODEL" '.models[]? | select(.name==$m or .model==$m)' >/dev/null
}

ensure_model() {
  if model_available; then return 0; fi
  if [[ "$PULL_IF_MISSING" == "1" ]]; then
    command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama CLI missing; cannot pull $MODEL" >&2; exit 4; }
    ollama pull "$MODEL"
    model_available || { echo "ERROR: model $MODEL still missing after pull" >&2; exit 4; }
  else
    echo "ERROR: model $MODEL not found locally. Run: ollama pull $MODEL OR rerun with --pull" >&2
    exit 4
  fi
}

write_meta() {
  {
    echo "script_name=ollama-test-RTX3090.sh"
    echo "version=$VERSION"
    echo "signature=$SCRIPT_SIGNATURE"
    echo "run_id=$RUN_ID"
    echo "run_dir=$RUN_DIR"
    echo "model=$MODEL"
    echo "base_url=$BASE_URL"
    echo "think=$THINK"
    echo "num_ctx=$NUM_CTX"
    echo "long_ctx=$LONG_CTX"
    echo "num_predict=$NUM_PREDICT"
    echo "long_num_predict=$LONG_NUM_PREDICT"
    echo "temperature=$TEMPERATURE"
    echo "keep_alive=$KEEP_ALIVE"
    echo "timeout_sec=$TIMEOUT_SEC"
    echo "run_conc=$RUN_CONC"
    echo "concurrency=$CONCURRENCY"
    echo "run_cpu=$RUN_CPU"
    echo "prompt_prefix=$PROMPT_PREFIX"
    echo
    echo "## environment"; date -Is; uname -a || true
    if command -v lsb_release >/dev/null 2>&1; then lsb_release -ds || true; fi
    echo; echo "## ollama version"; ollama --version 2>&1 || true
    echo; echo "## API tags selected model"; curl -fsS "$BASE_URL/api/tags" 2>/dev/null | jq --arg m "$MODEL" '.models[]? | select(.name==$m or .model==$m)' || true
    echo; echo "## nvidia-smi -L"; nvidia-smi -L 2>&1 || true
    echo; echo "## memory"; free -h 2>&1 || true
    echo; echo "## disk"; df -h "$HOME" 2>&1 || true
  } >"$META"
}

snapshot_before_after() {
  local label="$1"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi >"$RUN_DIR/nvidia-smi-$label.txt" 2>&1 || true
    nvidia-smi --query-gpu=timestamp,index,name,driver_version,pci.bus_id,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,utilization.memory,clocks.gr,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,pstate,fan.speed --format=csv >"$RUN_DIR/nvidia-smi-query-$label.csv" 2>&1 || true
  fi
  if command -v ollama >/dev/null 2>&1; then ollama ps >"$RUN_DIR/ollama-ps-$label.txt" 2>&1 || true; else echo "ollama CLI not found" >"$RUN_DIR/ollama-ps-$label.txt"; fi
  curl -fsS "$BASE_URL/api/ps" >"$RUN_DIR/ollama-api-ps-$label.json" 2>/dev/null || true
}

csv_header() {
  printf '%s\n' 'timestamp,test,model,num_ctx,num_predict,mode,concurrency,response_chars,thinking_chars,done_reason,total_s,load_s,prompt_eval_tokens,eval_tokens,prompt_tps,gen_tps,prompt_eval_s,eval_s,error,raw_json' >"$SUMMARY_CSV"
}

build_payload() {
  local prompt="$1" np="$2" ctx="$3" mode="$4" gpu_opts='{}' think_json='null'
  if [[ "$mode" == "CPU" ]]; then gpu_opts='{"num_gpu":0}'; fi
  case "$THINK" in
    true|false) think_json="$THINK" ;;
    low|medium|high) think_json="$(jq -Rn --arg v "$THINK" '$v')" ;;
    none) think_json='null' ;;
  esac
  jq -nc \
    --arg model "$MODEL" --arg prompt "$prompt" --arg keep "$KEEP_ALIVE" \
    --argjson np "$np" --argjson ctx "$ctx" --argjson temp "$TEMPERATURE" \
    --argjson gpu_opts "$gpu_opts" --argjson think "$think_json" \
    '{model:$model,prompt:$prompt,stream:false,keep_alive:$keep,options:({num_predict:$np,num_ctx:$ctx,temperature:$temp,seed:42} + $gpu_opts)} | if $think == null then . else . + {think:$think} end'
}

append_summary_from_json() {
  local test_name="$1" mode="$2" conc="$3" np="$4" ctx="$5" raw_file="$6" err_msg="${7:-}"
  if [[ -n "$err_msg" ]]; then
    jq -rn --arg ts "$(date -Is)" --arg test "$test_name" --arg model "$MODEL" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg err "$err_msg" --arg raw "$raw_file" \
      '[$ts,$test,$model,$ctx,$np,$mode,$conc,"","","","","","","","","","","",$err,$raw] | @csv' >>"$SUMMARY_CSV"
    return 0
  fi
  jq -r --arg ts "$(date -Is)" --arg test "$test_name" --arg model "$MODEL" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg raw "$raw_file" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    [$ts,$test,$model,$ctx,$np,$mode,$conc,((.response // "")|length),((.thinking // "")|length),(.done_reason // ""),(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),(.eval_count//""),(tps(.prompt_eval_count;.prompt_eval_duration)//""),(tps(.eval_count;.eval_duration)//""),(sec(.prompt_eval_duration)//""),(sec(.eval_duration)//""),"",$raw] | @csv' "$raw_file" >>"$SUMMARY_CSV"
}

run_generate() {
  local test_name="$1" mode="$2" conc="$3" np="$4" ctx="$5" prompt="$6" step_label="${7:-?}"
  local payload_file="$PAYLOAD_DIR/$test_name.json" raw_file="$RAW_DIR/$test_name.json" stderr_file="$RAW_DIR/$test_name.stderr" rc=0
  build_payload "$prompt" "$np" "$ctx" "$mode" >"$payload_file"
  log "START [$step_label/$PLANNED_TESTS] $test_name: mode=$mode ctx=$ctx predict=$np conc=$conc"
  if ! timeout -k 10s "$TIMEOUT_SEC" curl -sS --fail-with-body --connect-timeout "$CONNECT_TIMEOUT_SEC" --max-time "$TIMEOUT_SEC" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" "$BASE_URL/api/generate" >"$raw_file" 2>"$stderr_file"; then
    rc=$?; warn "$test_name failed rc=$rc stderr=$(tr '\n' ' ' <"$stderr_file" | cut -c1-300)"; append_summary_from_json "$test_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "curl_failed_rc_$rc"; return 0
  fi
  if ! jq -e . "$raw_file" >/dev/null 2>&1; then warn "$test_name returned non-JSON"; append_summary_from_json "$test_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "non_json_response"; return 0; fi
  append_summary_from_json "$test_name" "$mode" "$conc" "$np" "$ctx" "$raw_file"
  jq -r --arg step "$step_label" --arg planned "$PLANNED_TESTS" '"DONE  [\($step)/\($planned)] done_reason=" + (.done_reason // "") + " eval_tokens=" + ((.eval_count // 0)|tostring) + " gen_tps=" + (if (.eval_duration // 0) > 0 then (((.eval_count / (.eval_duration/1000000000))*100|round/100)|tostring) else "n/a" end) + " response_chars=" + (((.response // "")|length)|tostring) + " thinking_chars=" + (((.thinking // "")|length)|tostring)' "$raw_file" || true
}

make_summary_md() {
  {
    echo "# RTX 3090 Ollama Test Summary"; echo
    echo "## Run metadata"
    echo "- script_version: $VERSION"
    echo "- signature: $SCRIPT_SIGNATURE"
    echo "- run_id: $RUN_ID"
    echo "- model: $MODEL"
    echo "- base_url: $BASE_URL"
    echo "- think: $THINK"
    echo "- run_dir: $RUN_DIR"
    echo "- archive: ${ARCHIVE_PATH:-pending}"; echo
    echo "## Test results"; echo
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {test=unq($(h["test"])); mode=unq($(h["mode"])); ctx=unq($(h["num_ctx"])); np=unq($(h["num_predict"])); reason=unq($(h["done_reason"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"])); eval=unq($(h["eval_tokens"])); resp=unq($(h["response_chars"])); think=unq($(h["thinking_chars"])); total=unq($(h["total_s"])); if(NR==2){print "| Test | Mode | Ctx | Predict | Eval tokens | Gen tok/s | Total s | Response chars | Thinking chars | Done | Error |"; print "|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|"}; if(gen!="") gen=sprintf("%.2f", gen); if(total!="") total=sprintf("%.2f", total); printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", test, mode, ctx, np, eval, gen, total, resp, think, reason, err}' "$SUMMARY_CSV"
    echo; echo "## Automatic interpretation"; echo
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {rows++; mode=unq($(h["mode"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; load=unq($(h["load_s"]))+0; if(err!="") errors++; if(mode=="GPU"&&gen>0){gpu_n++; gpu_sum+=gen; if(gpu_n==1||gen>gpu_max)gpu_max=gen; if(gpu_n==1||gen<gpu_min)gpu_min=gen}; if(resp==0&&think>0) thinking_only++; if(load>max_load) max_load=load}
      END{if(gpu_n>0) printf "- GPU generation speed: avg %.2f tok/s, min %.2f, max %.2f across %d GPU rows.\n", gpu_sum/gpu_n, gpu_min, gpu_max, gpu_n; else print "- GPU generation speed: no valid GPU rows."; printf "- Errors recorded: %d.\n", errors; printf "- Thinking-only responses: %d.\n", thinking_only; printf "- Max model/context load time: %.2f sec.\n", max_load}' "$SUMMARY_CSV"
    echo; echo "## Ollama loaded models after test"; echo '```text'; cat "$RUN_DIR/ollama-ps-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## NVIDIA snapshot after test"; echo '```text'; cat "$RUN_DIR/nvidia-smi-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## Files"; echo "- terminal summary: $TERMINAL_SUMMARY"; echo "- CSV: $SUMMARY_CSV"; echo "- raw JSON: $RAW_DIR"; echo "- payload JSON: $PAYLOAD_DIR"; echo "- meta: $META"
  } >"$SUMMARY_MD"
}

make_terminal_summary() {
  {
    echo "============================================================"
    echo "RTX3090 OLLAMA TEST SUMMARY"
    echo "Run ID  : $RUN_ID"
    echo "Model   : $MODEL"
    echo "API     : $BASE_URL"
    echo "Think   : $THINK"
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {rows++; mode=unq($(h["mode"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; total=unq($(h["total_s"]))+0; load=unq($(h["load_s"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; if(err!="") errors++; if(mode=="GPU"&&gen>0){gpu_n++; gpu_sum+=gen; if(gpu_n==1||gen>gpu_max)gpu_max=gen; if(gpu_n==1||gen<gpu_min)gpu_min=gen}; if(resp>0) visible++; if(resp==0&&think>0) think_only++; if(load>max_load) max_load=load; if(total>max_total) max_total=total}
      END{status=(errors>0?"FAIL":(think_only>0?"PASS_WITH_WARNINGS":"PASS")); printf "Status  : %s\n", status; if(gpu_n>0) printf "Perf    : GPU avg %.2f tok/s, min %.2f, max %.2f, rows %d\n", gpu_sum/gpu_n, gpu_min, gpu_max, gpu_n; else print "Perf    : no valid GPU rows"; printf "Quality : visible rows %d/%d; thinking-only rows %d\n", visible, rows, think_only; printf "Timing  : max total %.2fs; max load %.2fs\n", max_total, max_load; printf "Errors  : %d\n", errors}' "$SUMMARY_CSV"
    echo "Tests:"
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {test=unq($(h["test"])); mode=unq($(h["mode"])); ctx=unq($(h["num_ctx"])); np=unq($(h["num_predict"])); gen=unq($(h["gen_tps"])); total=unq($(h["total_s"])); resp=unq($(h["response_chars"])); think=unq($(h["thinking_chars"])); done=unq($(h["done_reason"])); if(gen!="") gen=sprintf("%.2f", gen); if(total!="") total=sprintf("%.2f", total); printf "  %-18s %3s ctx=%-5s pred=%-5s gen=%6s t/s total=%7ss resp=%-4s think=%-5s %s\n", test, mode, ctx, np, gen, total, resp, think, done}' "$SUMMARY_CSV"
    echo "Files:"; echo "  run : $RUN_DIR"; echo "  md  : $SUMMARY_MD"; echo "  csv : $SUMMARY_CSV"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then echo "  zip : $ARCHIVE_PATH"; fi
    echo "============================================================"
  } >"$TERMINAL_SUMMARY"
}

make_archive() {
  [[ "$ZIP_ON_EXIT" == "1" ]] || return 0
  mkdir -p "$TMP_DIR"; ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; rm -f "$ARCHIVE_PATH"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  if command -v zip >/dev/null 2>&1; then (cd "$OUT_DIR" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")"); elif command -v python3 >/dev/null 2>&1; then (cd "$OUT_DIR" && python3 -m zipfile -c "$ARCHIVE_PATH" "$(basename "$RUN_DIR")"); else warn "zip and python3 are missing; cannot create archive"; fi
}

with_prefix() { if [[ -n "$PROMPT_PREFIX" ]]; then printf '%s\n%s' "$PROMPT_PREFIX" "$1"; else printf '%s' "$1"; fi; }

csv_header
ensure_server
ensure_model
write_meta
snapshot_before_after before

log "ollama-test-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Model: $MODEL"
log "Base URL: $BASE_URL"

base_prompt="$(with_prefix "Write a concise technical answer about GPU offload for local LLM inference. Use clear bullet points. Do not include hidden reasoning.")"
sanity_prompt="$(with_prefix "Return exactly this text and nothing else: RTX 3090 Ollama test OK")"
long_prompt="$(with_prefix "Write a technical diagnostic memo about RTX 3090 local LLM inference in WSL2. Cover VRAM, CUDA offload, PCIe, thermals, power, prompt throughput, generation throughput, model loading, and failure signals.")"

PLANNED_TESTS=4
if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then PLANNED_TESTS=$((PLANNED_TESTS + CONCURRENCY)); fi
if [[ "$RUN_CPU" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
TEST_STEP=0
log "Test plan: model=$MODEL think=$THINK tests=$PLANNED_TESTS ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU"
TEST_STEP=$((TEST_STEP + 1)); run_generate "01_sanity_gpu" "GPU" "1" 128 "$NUM_CTX" "$sanity_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "02_throughput_gpu" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$base_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "03_sustained_gpu" "GPU" "1" "$LONG_NUM_PREDICT" "$NUM_CTX" "$long_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "04_longctx_gpu" "GPU" "1" "$NUM_PREDICT" "$LONG_CTX" "$long_prompt" "$TEST_STEP"

if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then
  log "START concurrency probe: $CONCURRENCY parallel GPU requests"
  pids=()
  for i in $(seq 1 "$CONCURRENCY"); do
    TEST_STEP=$((TEST_STEP + 1))
    run_generate "05_conc${CONCURRENCY}_req${i}" "GPU" "$CONCURRENCY" "$NUM_PREDICT" "$NUM_CTX" "$base_prompt" "$TEST_STEP" &
    pids+=("$!")
  done
  wait "${pids[@]}" || true
  log "DONE concurrency probe"
fi

if [[ "$RUN_CPU" == "1" ]]; then
  TEST_STEP=$((TEST_STEP + 1)); run_generate "06_cpu_reference" "CPU" "1" 128 "$NUM_CTX" "$base_prompt" "$TEST_STEP"
fi

snapshot_before_after after
if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
make_summary_md
make_terminal_summary
make_archive

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then cat "$TERMINAL_SUMMARY"; else log "Summary: $SUMMARY_MD"; log "CSV:     $SUMMARY_CSV"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:     $ARCHIVE_PATH"; fi; log "Run dir: $RUN_DIR"; fi
