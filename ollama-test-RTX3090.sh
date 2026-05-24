#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.7.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v0.7.0-classified-longctx-soak-vram"

MODEL="${MODEL:-qwen3:8b}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
NUM_CTX="${NUM_CTX:-4096}"
LONG_CTX="${LONG_CTX:-8192}"
NUM_PREDICT="${NUM_PREDICT:-512}"
LONG_NUM_PREDICT="${LONG_NUM_PREDICT:-1024}"
LONG_PROMPT_WORDS="${LONG_PROMPT_WORDS:-3200}"
LONG_CONTEXT_MIN_FILL_PCT="${LONG_CONTEXT_MIN_FILL_PCT:-35}"
TEMPERATURE="${TEMPERATURE:-0.2}"
KEEP_ALIVE="${KEEP_ALIVE:-30m}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
RUN_CONC="${RUN_CONC:-1}"
CONCURRENCY="${CONCURRENCY:-2}"
RUN_CPU="${RUN_CPU:-0}"
SOAK_MINUTES="${SOAK_MINUTES:-0}"
SOAK_NUM_PREDICT="${SOAK_NUM_PREDICT:-512}"
RUN_VRAM_PRESSURE="${RUN_VRAM_PRESSURE:-0}"
VRAM_MODEL="${VRAM_MODEL:-}"
VRAM_CTX="${VRAM_CTX:-$LONG_CTX}"
VRAM_NUM_PREDICT="${VRAM_NUM_PREDICT:-256}"
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
CONC_AGG_CSV="$RUN_DIR/concurrency-aggregate.csv"
SOAK_SUMMARY_CSV="$RUN_DIR/soak-summary.csv"
SUMMARY_MD="$RUN_DIR/summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
META="$RUN_DIR/meta.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
ARCHIVE_PATH=""

usage() {
  cat <<EOF_USAGE
ollama-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Run RTX 3090 + Ollama health/performance tests and save raw JSON, request payloads, CSV, Markdown, and compact ASCII summaries.

Usage:
  ./ollama-test-RTX3090.sh [options]

Core options:
  --model NAME              Model to test (default: $MODEL)
  --base-url URL            Ollama base URL (default: $BASE_URL)
  --out-dir DIR             Output root (default: $OUT_DIR)
  --run-id ID               Override run id
  --num-ctx N               Standard context (default: $NUM_CTX)
  --long-ctx N              Long-context context window (default: $LONG_CTX)
  --num-predict N           Standard generation length (default: $NUM_PREDICT)
  --long-num-predict N      Sustained generation length (default: $LONG_NUM_PREDICT)
  --long-prompt-words N     Approximate words in the true long-context prompt (default: $LONG_PROMPT_WORDS)
  --temperature X           Generation temperature (default: $TEMPERATURE)
  --timeout-sec N           curl max time per request (default: $TIMEOUT_SEC)
  --concurrency N           Parallel GPU requests for concurrency probe (default: $CONCURRENCY)
  --think VALUE             Ollama top-level think: false|true|none|low|medium|high (default: $THINK)
  --prompt-prefix TEXT      Optional prompt prefix; default is empty

Optional probes:
  --run-conc / --no-conc    Enable/disable concurrency probe (default: $RUN_CONC)
  --run-cpu / --no-cpu      Enable/disable CPU-only comparison (default: $RUN_CPU)
  --soak-minutes N          Optional repeated GPU generation soak duration; 0 disables (default: $SOAK_MINUTES)
  --soak-num-predict N      Per-request generation size for soak (default: $SOAK_NUM_PREDICT)
  --run-vram-pressure       Run optional VRAM-pressure probe; requires existing --vram-model or uses --model
  --no-vram-pressure        Disable VRAM-pressure probe (default)
  --vram-model NAME         Optional larger model for VRAM-pressure probe; no auto-pull unless --pull
  --vram-ctx N              VRAM-pressure context (default: $VRAM_CTX)
  --vram-num-predict N      VRAM-pressure generation length (default: $VRAM_NUM_PREDICT)

Operational options:
  --pull / --no-pull        Pull missing model(s) (default: $PULL_IF_MISSING)
  --ensure-server / --no-ensure-server  Start/check Ollama server (default: $ENSURE_SERVER)
  --terminal-summary / --no-terminal-summary  Print <=50-line ASCII terminal summary (default: $PRINT_TERMINAL_SUMMARY)
  --zip / --no-zip          Create ~/tmp archive on exit (default: $ZIP_ON_EXIT)
  -h, --help                Show help
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
    --long-prompt-words) LONG_PROMPT_WORDS="${2:-}"; shift 2 ;;
    --temperature) TEMPERATURE="${2:-}"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --think) THINK="${2:-}"; shift 2 ;;
    --prompt-prefix) PROMPT_PREFIX="${2:-}"; shift 2 ;;
    --run-conc) RUN_CONC=1; shift ;;
    --no-conc) RUN_CONC=0; shift ;;
    --run-cpu) RUN_CPU=1; shift ;;
    --no-cpu) RUN_CPU=0; shift ;;
    --soak-minutes) SOAK_MINUTES="${2:-}"; shift 2 ;;
    --soak-num-predict) SOAK_NUM_PREDICT="${2:-}"; shift 2 ;;
    --run-vram-pressure) RUN_VRAM_PRESSURE=1; shift ;;
    --no-vram-pressure) RUN_VRAM_PRESSURE=0; shift ;;
    --vram-model) VRAM_MODEL="${2:-}"; shift 2 ;;
    --vram-ctx) VRAM_CTX="${2:-}"; shift 2 ;;
    --vram-num-predict) VRAM_NUM_PREDICT="${2:-}"; shift 2 ;;
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
for n in NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT LONG_PROMPT_WORDS TIMEOUT_SEC CONNECT_TIMEOUT_SEC CONCURRENCY SOAK_MINUTES SOAK_NUM_PREDICT VRAM_CTX VRAM_NUM_PREDICT; do
  is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }
done
case "$THINK" in true|false|none|low|medium|high) ;; *) echo "ERROR: --think must be false, true, none, low, medium, or high" >&2; exit 2 ;; esac
[[ "$CONCURRENCY" -ge 1 ]] || CONCURRENCY=1
[[ "$LONG_PROMPT_WORDS" -ge 64 ]] || LONG_PROMPT_WORDS=64

RUN_DIR="$OUT_DIR/run-$RUN_ID"
RAW_DIR="$RUN_DIR/raw"
PAYLOAD_DIR="$RUN_DIR/payloads"
SUMMARY_CSV="$RUN_DIR/summary.csv"
CONC_AGG_CSV="$RUN_DIR/concurrency-aggregate.csv"
SOAK_SUMMARY_CSV="$RUN_DIR/soak-summary.csv"
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
  local model_name="$1"
  curl -fsS "$BASE_URL/api/tags" | jq -e --arg m "$model_name" '.models[]? | select(.name==$m or .model==$m)' >/dev/null
}

ensure_model() {
  local model_name="$1"
  if model_available "$model_name"; then return 0; fi
  if [[ "$PULL_IF_MISSING" == "1" ]]; then
    command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama CLI missing; cannot pull $model_name" >&2; exit 4; }
    ollama pull "$model_name"
    model_available "$model_name" || { echo "ERROR: model $model_name still missing after pull" >&2; exit 4; }
  else
    echo "ERROR: model $model_name not found locally. Run: ollama pull $model_name OR rerun with --pull" >&2
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
    echo "long_prompt_words=$LONG_PROMPT_WORDS"
    echo "long_context_min_fill_pct=$LONG_CONTEXT_MIN_FILL_PCT"
    echo "temperature=$TEMPERATURE"
    echo "keep_alive=$KEEP_ALIVE"
    echo "timeout_sec=$TIMEOUT_SEC"
    echo "run_conc=$RUN_CONC"
    echo "concurrency=$CONCURRENCY"
    echo "run_cpu=$RUN_CPU"
    echo "soak_minutes=$SOAK_MINUTES"
    echo "run_vram_pressure=$RUN_VRAM_PRESSURE"
    echo "vram_model=$VRAM_MODEL"
    echo "vram_ctx=$VRAM_CTX"
    echo "vram_num_predict=$VRAM_NUM_PREDICT"
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
    nvidia-smi -q -d POWER,TEMPERATURE,CLOCK,PERFORMANCE,PCI,MEMORY,UTILIZATION >"$RUN_DIR/nvidia-smi-q-$label.txt" 2>&1 || true
    nvidia-smi --query-gpu=timestamp,index,name,driver_version,pci.bus_id,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,utilization.memory,clocks.gr,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,pstate,fan.speed --format=csv >"$RUN_DIR/nvidia-smi-query-$label.csv" 2>&1 || true
  fi
  if command -v ollama >/dev/null 2>&1; then ollama ps >"$RUN_DIR/ollama-ps-$label.txt" 2>&1 || true; else echo "ollama CLI not found" >"$RUN_DIR/ollama-ps-$label.txt"; fi
  curl -fsS "$BASE_URL/api/ps" >"$RUN_DIR/ollama-api-ps-$label.json" 2>/dev/null || true
}

capture_dmesg_gpu_errors() {
  {
    echo "# dmesg GPU/error scan"
    echo "timestamp=$(date -Is)"
    if command -v dmesg >/dev/null 2>&1; then
      dmesg -T 2>&1 | grep -Ei 'nvrm|xid|cuda|gpu|dxg|wsl|nvidia' || true
    else
      echo "dmesg not found"
    fi
  } >"$RUN_DIR/dmesg-gpu-errors.txt"
}

csv_header() {
  printf '%s\n' 'timestamp,category,test,model,num_ctx,num_predict,mode,concurrency,request_wall_s,response_chars,thinking_chars,done_reason,total_s,load_s,prompt_eval_tokens,eval_tokens,prompt_tps,gen_tps,prompt_eval_s,eval_s,prompt_chars,prompt_words,context_fill_pct,error,raw_json,payload_json' >"$SUMMARY_CSV"
  printf '%s\n' 'timestamp,concurrency,wall_s,total_eval_tokens,total_response_chars,aggregate_gen_tps,requests_ok,requests_error,raw_glob' >"$CONC_AGG_CSV"
  printf '%s\n' 'timestamp,iterations,wall_s,total_eval_tokens,aggregate_gen_tps,errors' >"$SOAK_SUMMARY_CSV"
}

build_payload() {
  local model_name="$1" prompt="$2" np="$3" ctx="$4" mode="$5" gpu_opts='{}' think_json='null'
  if [[ "$mode" == "CPU" ]]; then gpu_opts='{"num_gpu":0}'; fi
  case "$THINK" in
    true|false) think_json="$THINK" ;;
    low|medium|high) think_json="$(jq -Rn --arg v "$THINK" '$v')" ;;
    none) think_json='null' ;;
  esac
  jq -nc \
    --arg model "$model_name" --arg prompt "$prompt" --arg keep "$KEEP_ALIVE" \
    --argjson np "$np" --argjson ctx "$ctx" --argjson temp "$TEMPERATURE" \
    --argjson gpu_opts "$gpu_opts" --argjson think "$think_json" \
    '{model:$model,prompt:$prompt,stream:false,keep_alive:$keep,options:({num_predict:$np,num_ctx:$ctx,temperature:$temp,seed:42} + $gpu_opts)} | if $think == null then . else . + {think:$think} end'
}

prompt_word_count() { awk '{n+=NF} END{print n+0}' <<<"$1"; }
append_csv_line() {
  local line="$1" lock="$RUN_DIR/summary.csv.lock" tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if (( tries > 600 )); then echo "ERROR: timeout waiting for summary.csv lock" >&2; return 1; fi
    sleep 0.05
  done
  printf '%s\n' "$line" >>"$SUMMARY_CSV"
  rmdir "$lock"
}

append_summary_from_json() {
  local category="$1" test_name="$2" model_name="$3" mode="$4" conc="$5" np="$6" ctx="$7" raw_file="$8" payload_file="$9" wall_s="${10}" prompt_chars="${11}" prompt_words="${12}" err_msg="${13:-}"
  local line
  if [[ -n "$err_msg" ]]; then
    line="$(jq -rn --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg err "$err_msg" --arg raw "$raw_file" --arg payload "$payload_file" \
      '[$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,"","","","","","","","","","","",$pc,$pw,"",$err,$raw,$payload] | @csv')"
    append_csv_line "$line"
    return 0
  fi
  line="$(jq -r --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg raw "$raw_file" --arg payload "$payload_file" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    def fill(tokens; ctx): if tokens == null or ctx == null or (ctx|tonumber)==0 then null else (100 * (tokens|tonumber) / (ctx|tonumber)) end;
    [$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,((.response // "")|length),((.thinking // "")|length),(.done_reason // ""),(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),(.eval_count//""),(tps(.prompt_eval_count;.prompt_eval_duration)//""),(tps(.eval_count;.eval_duration)//""),(sec(.prompt_eval_duration)//""),(sec(.eval_duration)//""),$pc,$pw,(fill(.prompt_eval_count;$ctx)//""),"",$raw,$payload] | @csv' "$raw_file")"
  append_csv_line "$line"
}

run_generate() {
  local category="$1" test_name="$2" model_name="$3" mode="$4" conc="$5" np="$6" ctx="$7" prompt="$8" step_label="${9:-?}"
  local payload_file="$PAYLOAD_DIR/$test_name.json" raw_file="$RAW_DIR/$test_name.json" stderr_file="$RAW_DIR/$test_name.stderr" rc=0 start_ns end_ns wall_s prompt_chars prompt_words
  prompt_chars="${#prompt}"
  prompt_words="$(prompt_word_count "$prompt")"
  build_payload "$model_name" "$prompt" "$np" "$ctx" "$mode" >"$payload_file"
  log "START [$step_label/$PLANNED_TESTS] $test_name: category=$category model=$model_name mode=$mode ctx=$ctx predict=$np conc=$conc prompt_words=$prompt_words"
  start_ns="$(date +%s%N)"
  set +e
  timeout -k 10s "$TIMEOUT_SEC" curl -sS --fail-with-body --connect-timeout "$CONNECT_TIMEOUT_SEC" --max-time "$TIMEOUT_SEC" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" "$BASE_URL/api/generate" >"$raw_file" 2>"$stderr_file"
  rc=$?
  set -e
  end_ns="$(date +%s%N)"
  wall_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.6f", (e-s)/1000000000}')"
  if [[ "$rc" -ne 0 ]]; then
    warn "$test_name failed rc=$rc stderr=$(tr '\n' ' ' <"$stderr_file" | cut -c1-300)"
    append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "curl_failed_rc_$rc"
    return 0
  fi
  if ! jq -e . "$raw_file" >/dev/null 2>&1; then
    warn "$test_name returned non-JSON"
    append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "non_json_response"
    return 0
  fi
  append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words"
  jq -r --arg step "$step_label" --arg planned "$PLANNED_TESTS" --arg wall "$wall_s" '"DONE  [\($step)/\($planned)] done_reason=" + (.done_reason // "") + " prompt_tokens=" + ((.prompt_eval_count // 0)|tostring) + " eval_tokens=" + ((.eval_count // 0)|tostring) + " gen_tps=" + (if (.eval_duration // 0) > 0 then (((.eval_count / (.eval_duration/1000000000))*100|round/100)|tostring) else "n/a" end) + " wall_s=" + $wall + " response_chars=" + (((.response // "")|length)|tostring) + " thinking_chars=" + (((.thinking // "")|length)|tostring)' "$raw_file" || true
}

with_prefix() { if [[ -n "$PROMPT_PREFIX" ]]; then printf '%s\n%s' "$PROMPT_PREFIX" "$1"; else printf '%s' "$1"; fi; }

make_long_prompt() {
  local target_words="$1" i=1
  printf '%s\n' "You are evaluating a true long-context local LLM inference run on RTX 3090 in WSL2. Read the diagnostic facts and then produce a concise technical summary. Do not include hidden reasoning."
  while (( i <= target_words )); do
    printf 'fact%05d RTX3090 Ollama WSL2 CUDA VRAM power thermals PCIe clocks prompt throughput generation telemetry stability evidence. ' "$i"
    i=$((i + 16))
  done
  printf '\nNow summarize the evidence, identify bottlenecks, and state whether the run is healthy.\n'
}

make_concurrency_aggregate() {
  local conc="$1" start_ns="$2" end_ns="$3" pattern="$4" wall_s total_eval total_resp ok_count err_count agg_tps files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$RAW_DIR" -maxdepth 1 -type f -name "$pattern" | sort)
  wall_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.6f", (e-s)/1000000000}')"
  if (( ${#files[@]} > 0 )); then
    total_eval="$(jq -s '[.[] | .eval_count // 0] | add // 0' "${files[@]}" 2>/dev/null || echo 0)"
    total_resp="$(jq -s '[.[] | (.response // "" | length)] | add // 0' "${files[@]}" 2>/dev/null || echo 0)"
    ok_count="$(jq -s '[.[] | select(.eval_count != null)] | length' "${files[@]}" 2>/dev/null || echo 0)"
  else
    total_eval=0; total_resp=0; ok_count=0
  fi
  err_count=$((conc - ok_count)); [[ "$err_count" -ge 0 ]] || err_count=0
  agg_tps="$(awk -v t="$total_eval" -v s="$wall_s" 'BEGIN{if(s>0) printf "%.4f", t/s; else print ""}')"
  jq -rn --arg ts "$(date -Is)" --arg conc "$conc" --arg wall "$wall_s" --arg total "$total_eval" --arg resp "$total_resp" --arg agg "$agg_tps" --arg ok "$ok_count" --arg err "$err_count" --arg pat "$pattern" \
    '[$ts,$conc,$wall,$total,$resp,$agg,$ok,$err,$pat] | @csv' >>"$CONC_AGG_CSV"
}

run_soak() {
  local deadline iter=0 errors=0 start_ns end_ns total_eval=0 wall_s agg_tps prompt
  [[ "$SOAK_MINUTES" -gt 0 ]] || return 0
  log "START soak probe: ${SOAK_MINUTES} minute(s), predict=$SOAK_NUM_PREDICT"
  prompt="$(with_prefix "Sustained RTX 3090 Ollama soak probe. Produce a compact but non-trivial technical paragraph about GPU inference telemetry.")"
  start_ns="$(date +%s%N)"
  deadline=$(( $(date +%s) + SOAK_MINUTES * 60 ))
  while (( $(date +%s) < deadline )); do
    iter=$((iter + 1))
    run_generate "soak" "07_soak_gpu_${iter}" "$MODEL" "GPU" "1" "$SOAK_NUM_PREDICT" "$NUM_CTX" "$prompt" "SOAK"
    if jq -e '.eval_count' "$RAW_DIR/07_soak_gpu_${iter}.json" >/dev/null 2>&1; then
      total_eval=$(( total_eval + $(jq -r '.eval_count // 0' "$RAW_DIR/07_soak_gpu_${iter}.json") ))
    else
      errors=$((errors + 1))
    fi
  done
  end_ns="$(date +%s%N)"
  wall_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.6f", (e-s)/1000000000}')"
  agg_tps="$(awk -v t="$total_eval" -v s="$wall_s" 'BEGIN{if(s>0) printf "%.4f", t/s; else print ""}')"
  jq -rn --arg ts "$(date -Is)" --arg i "$iter" --arg wall "$wall_s" --arg total "$total_eval" --arg agg "$agg_tps" --arg err "$errors" '[$ts,$i,$wall,$total,$agg,$err] | @csv' >>"$SOAK_SUMMARY_CSV"
  log "DONE soak probe iterations=$iter aggregate_gen_tps=$agg_tps errors=$errors wall_s=$wall_s"
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
    echo "## Classified metrics"; echo
    awk -F',' -v minfill="$LONG_CONTEXT_MIN_FILL_PCT" '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {rows++; cat=unq($(h["category"])); mode=unq($(h["mode"])); conc=unq($(h["concurrency"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; load=unq($(h["load_s"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; pe=unq($(h["prompt_eval_tokens"]))+0; ctx=unq($(h["num_ctx"]))+0; fill=unq($(h["context_fill_pct"]))+0; if(err!="")errors++; if(resp>0)visible++; if(resp==0&&think>0)thinkonly++; if(cat=="sanity" && load>cold) cold=load; if(mode=="GPU"&&conc==1&&err==""&&(cat=="throughput"||cat=="sustained")&&gen>0){warmn++; warmsum+=gen}; if(cat=="longctx"){longgen=gen; longpe=pe; longctx=ctx; longfill=fill}}
      END{printf "- status_basis: rows=%d errors=%d visible=%d thinking_only=%d\n", rows, errors, visible, thinkonly; if(warmn>0) printf "- warm_single_gpu_tps_avg: %.2f across %d rows\n", warmsum/warmn, warmn; printf "- cold_load_s: %.2f\n", cold; printf "- long_context: prompt_eval_tokens=%d ctx=%d fill=%.1f%% gen_tps=%.2f verdict=%s\n", longpe, longctx, longfill, longgen, (longfill>=minfill?"OK":"UNDERFILLED")}' "$SUMMARY_CSV"
    if [[ -s "$CONC_AGG_CSV" ]]; then echo; echo "## Concurrency aggregate"; echo '```csv'; cat "$CONC_AGG_CSV"; echo '```'; fi
    if [[ -s "$SOAK_SUMMARY_CSV" ]]; then echo; echo "## Soak aggregate"; echo '```csv'; cat "$SOAK_SUMMARY_CSV"; echo '```'; fi
    echo; echo "## Test results"; echo
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {test=unq($(h["test"])); cat=unq($(h["category"])); mode=unq($(h["mode"])); ctx=unq($(h["num_ctx"])); np=unq($(h["num_predict"])); reason=unq($(h["done_reason"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"])); eval=unq($(h["eval_tokens"])); prompt=unq($(h["prompt_eval_tokens"])); fill=unq($(h["context_fill_pct"])); total=unq($(h["total_s"])); if(NR==2){print "| Test | Category | Mode | Ctx | Predict | Prompt tok | Fill % | Eval tok | Gen tok/s | Total s | Done | Error |"; print "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|"}; if(gen!="") gen=sprintf("%.2f", gen); if(total!="") total=sprintf("%.2f", total); if(fill!="") fill=sprintf("%.1f", fill); printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", test, cat, mode, ctx, np, prompt, fill, eval, gen, total, reason, err}' "$SUMMARY_CSV"
    echo; echo "## Ollama loaded models after test"; echo '```text'; cat "$RUN_DIR/ollama-ps-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## NVIDIA snapshot after test"; echo '```text'; cat "$RUN_DIR/nvidia-smi-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## dmesg GPU/error scan"; echo '```text'; cat "$RUN_DIR/dmesg-gpu-errors.txt" 2>/dev/null || true; echo '```'
    echo; echo "## Files"; echo "- terminal summary: $TERMINAL_SUMMARY"; echo "- CSV: $SUMMARY_CSV"; echo "- concurrency aggregate CSV: $CONC_AGG_CSV"; echo "- soak summary CSV: $SOAK_SUMMARY_CSV"; echo "- raw JSON: $RAW_DIR"; echo "- payload JSON: $PAYLOAD_DIR"; echo "- meta: $META"
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
    awk -F',' -v minfill="$LONG_CONTEXT_MIN_FILL_PCT" '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {rows++; cat=unq($(h["category"])); mode=unq($(h["mode"])); conc=unq($(h["concurrency"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; total=unq($(h["total_s"]))+0; load=unq($(h["load_s"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; pe=unq($(h["prompt_eval_tokens"]))+0; ctx=unq($(h["num_ctx"]))+0; fill=unq($(h["context_fill_pct"]))+0; if(err!="") errors++; if(resp>0) visible++; if(resp==0&&think>0) think_only++; if(cat=="sanity" && load>cold_load)cold_load=load; if(mode=="GPU"&&conc==1&&err==""&&(cat=="throughput"||cat=="sustained")&&gen>0){warm_n++; warm_sum+=gen; if(warm_n==1||gen>warm_max)warm_max=gen; if(warm_n==1||gen<warm_min)warm_min=gen}; if(cat=="longctx"){long_gen=gen; long_fill=fill; long_pe=pe; long_ctx=ctx}; if(total>max_total)max_total=total}
      END{status=(errors>0?"FAIL":((think_only>0||long_fill<minfill)?"PASS_WITH_WARNINGS":"PASS")); printf "Status  : %s\n", status; if(warm_n>0) printf "Warm    : single GPU %.2f tok/s avg (%.2f-%.2f), rows %d\n", warm_sum/warm_n, warm_min, warm_max, warm_n; else print "Warm    : no valid warm single GPU rows"; printf "Cold    : first-load %.2fs; max total %.2fs\n", cold_load, max_total; printf "LongCtx : prompt_tokens=%d ctx=%d fill=%.1f%% gen=%.2f tok/s %s\n", long_pe, long_ctx, long_fill, long_gen, (long_fill>=minfill?"OK":"UNDERFILLED"); printf "Output  : visible rows %d/%d; thinking-only %d; errors %d\n", visible, rows, think_only, errors}' "$SUMMARY_CSV"
    if [[ -s "$CONC_AGG_CSV" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Conc    : x%s aggregate %.2f tok/s over %.2fs; ok=%s err=%s\n", unq($2), unq($6)+0, unq($3)+0, unq($7), unq($8)}' "$CONC_AGG_CSV"
    fi
    if [[ -s "$SOAK_SUMMARY_CSV" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Soak    : iterations=%s aggregate %.2f tok/s over %.1fs; errors=%s\n", unq($2), unq($5)+0, unq($3)+0, unq($6)}' "$SOAK_SUMMARY_CSV"
    fi
    echo "Tests:"
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      NR<=13{test=unq($(h["test"])); cat=unq($(h["category"])); mode=unq($(h["mode"])); ctx=unq($(h["num_ctx"])); gen=unq($(h["gen_tps"])); prompt=unq($(h["prompt_eval_tokens"])); done=unq($(h["done_reason"])); if(gen!="") gen=sprintf("%.2f", gen); printf "  %-18s %-10s %3s ctx=%-5s prompt=%-5s gen=%6s %s\n", test, cat, mode, ctx, prompt, gen, done}
      NR==14{print "  ... additional rows omitted from terminal summary; see summary.csv"}' "$SUMMARY_CSV"
    echo "Files:"; echo "  run : $RUN_DIR"; echo "  md  : $SUMMARY_MD"; echo "  csv : $SUMMARY_CSV"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then echo "  zip : $ARCHIVE_PATH"; fi
    echo "============================================================"
  } >"$TERMINAL_SUMMARY"
}

make_archive() {
  [[ "$ZIP_ON_EXIT" == "1" ]] || return 0
  mkdir -p "$TMP_DIR"
  ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"
  rm -f "$ARCHIVE_PATH"
  printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  if command -v zip >/dev/null 2>&1; then
    (cd "$OUT_DIR" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  else
    warn "zip is missing; cannot create archive"
  fi
}

csv_header
ensure_server
ensure_model "$MODEL"
if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then ensure_model "${VRAM_MODEL:-$MODEL}"; fi
write_meta
snapshot_before_after before

log "ollama-test-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Model: $MODEL"
log "Base URL: $BASE_URL"

base_prompt="$(with_prefix "Write a concise technical answer about GPU offload for local LLM inference. Use clear bullet points. Do not include hidden reasoning.")"
sanity_prompt="$(with_prefix "Return exactly this text and nothing else: RTX 3090 Ollama test OK")"
sustained_prompt="$(with_prefix "Write a technical diagnostic memo about RTX 3090 local LLM inference in WSL2. Cover VRAM, CUDA offload, PCIe, thermals, power, prompt throughput, generation throughput, model loading, and failure signals.")"
long_prompt="$(with_prefix "$(make_long_prompt "$LONG_PROMPT_WORDS")")"
vram_prompt="$(with_prefix "VRAM pressure probe. Produce a concise technical response while the selected model/context allocates GPU memory.")"

PLANNED_TESTS=4
if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then PLANNED_TESTS=$((PLANNED_TESTS + CONCURRENCY)); fi
if [[ "$RUN_CPU" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
TEST_STEP=0
log "Test plan: model=$MODEL think=$THINK tests=$PLANNED_TESTS ctx=$NUM_CTX long_ctx=$LONG_CTX long_prompt_words=$LONG_PROMPT_WORDS predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU soak_minutes=$SOAK_MINUTES run_vram_pressure=$RUN_VRAM_PRESSURE"
TEST_STEP=$((TEST_STEP + 1)); run_generate "sanity" "01_sanity_gpu" "$MODEL" "GPU" "1" 128 "$NUM_CTX" "$sanity_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "throughput" "02_throughput_gpu" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$base_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "sustained" "03_sustained_gpu" "$MODEL" "GPU" "1" "$LONG_NUM_PREDICT" "$NUM_CTX" "$sustained_prompt" "$TEST_STEP"
TEST_STEP=$((TEST_STEP + 1)); run_generate "longctx" "04_longctx_gpu" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$LONG_CTX" "$long_prompt" "$TEST_STEP"

if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then
  log "START concurrency probe: $CONCURRENCY parallel GPU requests"
  pids=()
  conc_start_ns="$(date +%s%N)"
  for i in $(seq 1 "$CONCURRENCY"); do
    TEST_STEP=$((TEST_STEP + 1))
    run_generate "concurrency" "05_conc${CONCURRENCY}_req${i}" "$MODEL" "GPU" "$CONCURRENCY" "$NUM_PREDICT" "$NUM_CTX" "$base_prompt" "$TEST_STEP" &
    pids+=("$!")
  done
  wait "${pids[@]}" || true
  conc_end_ns="$(date +%s%N)"
  make_concurrency_aggregate "$CONCURRENCY" "$conc_start_ns" "$conc_end_ns" "05_conc${CONCURRENCY}_req*.json"
  log "DONE concurrency probe"
fi

if [[ "$RUN_CPU" == "1" ]]; then
  TEST_STEP=$((TEST_STEP + 1)); run_generate "cpu_reference" "06_cpu_reference" "$MODEL" "CPU" "1" 128 "$NUM_CTX" "$base_prompt" "$TEST_STEP"
fi

if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then
  TEST_STEP=$((TEST_STEP + 1)); run_generate "vram_pressure" "08_vram_pressure" "${VRAM_MODEL:-$MODEL}" "GPU" "1" "$VRAM_NUM_PREDICT" "$VRAM_CTX" "$vram_prompt" "$TEST_STEP"
fi

run_soak
snapshot_before_after after
capture_dmesg_gpu_errors
if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
make_summary_md
make_terminal_summary
make_archive

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then cat "$TERMINAL_SUMMARY"; else log "Summary: $SUMMARY_MD"; log "CSV:     $SUMMARY_CSV"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:     $ARCHIVE_PATH"; fi; log "Run dir: $RUN_DIR"; fi
ERROR_COUNT="$(awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s} NR==1{for(i=1;i<=NF;i++)h[unq($i)]=i; next} {if(unq($(h["error"]))!="")e++} END{print e+0}' "$SUMMARY_CSV")"
if [[ "$ERROR_COUNT" -gt 0 ]]; then exit 1; fi
