#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.9"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v1.9-compact-multimodel-readme"

MODEL="${MODEL:-}"
MODEL_PATTERN="${MODEL_PATTERN:-}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
NUM_CTX="${NUM_CTX:-4096}"
LONG_CTX="${LONG_CTX:-8192}"
NUM_PREDICT="${NUM_PREDICT:-512}"
LONG_NUM_PREDICT="${LONG_NUM_PREDICT:-1024}"
LONG_PROMPT_WORDS="${LONG_PROMPT_WORDS:-3200}"
LONG_CONTEXT_MIN_FILL_PCT="${LONG_CONTEXT_MIN_FILL_PCT:-65}"
DECODE512_MIN_EVAL_TOKENS="${DECODE512_MIN_EVAL_TOKENS:-384}"
DECODE1024_MIN_EVAL_TOKENS="${DECODE1024_MIN_EVAL_TOKENS:-900}"
LONGCTX_MIN_EVAL_TOKENS="${LONGCTX_MIN_EVAL_TOKENS:-256}"
TEMPERATURE="${TEMPERATURE:-0.2}"
KEEP_ALIVE="${KEEP_ALIVE:-30m}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
RUN_CONC="${RUN_CONC:-0}"
CONCURRENCY="${CONCURRENCY:-1}"
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
SERVER_LOG_LINES="${SERVER_LOG_LINES:-240}"
CAPTURE_WSL_DIAGNOSTICS="${CAPTURE_WSL_DIAGNOSTICS:-1}"
EMBEDDING_MODE="${EMBEDDING_MODE:-0}"
FULL_MODEL_SHOW="${FULL_MODEL_SHOW:-0}"
MODEL_ROLE="${MODEL_ROLE:-unknown}"
STREAM_GENERATION="${STREAM_GENERATION:-1}"
LOAD_MODE="${LOAD_MODE:-empty-card}"
TEST_PROFILE="${TEST_PROFILE:-ados}"
EMPTY_CARD_REQUESTED="0"
EMPTY_CARD_VERIFIED="0"
COLD_VERIFIED="0"
MODEL_RESIDENT_BEFORE="unknown"

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
FAILURE_HINTS="$RUN_DIR/failure-hints.txt"
SERVER_LOG_TAIL="$RUN_DIR/ollama-server-log-tail.txt"
WSL_DIAG="$RUN_DIR/wsl-diagnostics.txt"
API_VERSION_FILE="$RUN_DIR/ollama-api-version.json"
API_TAGS_FILE="$RUN_DIR/ollama-api-tags.json"
API_SHOW_FILE="$RUN_DIR/ollama-api-show-model.json"
API_SHOW_RAW_FILE="$RUN_DIR/ollama-api-show-model-raw.json"
API_SHOW_FULL_FILE="$RUN_DIR/ollama-api-show-model-full.json"
MODEL_CAPABILITY_FILE="$RUN_DIR/model-capability.json"
LOAD_STATE_FILE="$RUN_DIR/load-state.txt"
CAPABILITY_ANALYSIS="$RUN_DIR/capability-analysis.md"
DMESG_CURSOR_FILE="$RUN_DIR/dmesg-start-line-count.txt"
OLLAMA_SHOW_FILE="$RUN_DIR/ollama-show-model.txt"

usage() {
  cat <<EOF_USAGE
ollama-test-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Run RTX 3090 + Ollama health/performance tests and save raw JSON, request payloads, CSV, Markdown, and compact ASCII summaries.

Usage:
  ./ollama-test-RTX3090.sh MODEL_PATTERN [options]
  ./ollama-test-RTX3090.sh --model MODEL_PATTERN [options]
  ./ollama-test-RTX3090.sh --help

Short example:
  ./ollama-test-RTX3090.sh qwen3.6

Model selection:
  MODEL_PATTERN is resolved against locally available Ollama model names from /api/tags.
  Matching order is exact full name, exact base name before ':', then unique case-insensitive substring.
  Example: qwen3.6 resolves to qwen3.6:35b when that is the only local match.
  With no MODEL_PATTERN, the script prints a short dashboard, status, available models, and run commands.
  With no/ambiguous match, it prints matching/available model run commands only.
  Full help is shown only with -h or --help.

Core options:
  --model PATTERN           Model name or pattern to resolve locally
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
  --embedding               Run /api/embed benchmark mode instead of /api/generate
  --profile PROFILE          ados|perf|legacy-perf; default ados runs 3 capability prompts
  --stream / --no-stream     Enable/disable streaming generation instrumentation for TTFT (default: $STREAM_GENERATION)
  --load-mode MODE           empty-card|observed|warm|unload-model|restart-ollama; default empty-card unloads all resident Ollama models before testing
  --prompt-prefix TEXT      Optional prompt prefix; default is empty
  --server-log-lines N      Capture last N Ollama server log lines when available (default: $SERVER_LOG_LINES)
  --no-wsl-diagnostics      Skip WSL/Windows-side configuration snapshots
  --full-model-show         Also archive full verbose /api/show output; default stores slim metadata only

Optional probes:
  --stress                  Enable common RTX stress profile: --run-conc --concurrency 2
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
  --pull / --no-pull        Pull missing exact model after resolution (default: $PULL_IF_MISSING)
  --ensure-server / --no-ensure-server  Accepted for compatibility; test still requires reachable Ollama API
  --terminal-summary / --no-terminal-summary  Print <=50-line ASCII terminal summary (default: $PRINT_TERMINAL_SUMMARY)
  --zip / --no-zip          Create ~/tmp archive on exit (default: $ZIP_ON_EXIT)
  -h, --help                Show help
EOF_USAGE
}

short_usage() {
  cat <<EOF_SHORT
ollama-test-RTX3090.sh v$VERSION
Usage: $(script_display_cmd) <model-pattern> [options]
Example: $(script_display_cmd) qwen3.6
Baseline run: $(script_display_cmd) qwen3.6
Stress run:   $(script_display_cmd) qwen3.6 --stress
Defaults: profile=$TEST_PROFILE ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT concurrency=$CONCURRENCY think=$THINK embedding=$EMBEDDING_MODE stream=$STREAM_GENERATION load_mode=$LOAD_MODE
Use -h for full options.
EOF_SHORT
}

show_no_args_screen() {
  short_usage
  echo
  ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true
  echo
  if ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
    ollama_print_available_model_commands "$BASE_URL" "$(script_display_cmd)" "$CONNECT_TIMEOUT_SEC"
  else
    ollama_print_start_hint "$BASE_URL"
  fi
}

require_ollama_ready() {
  { ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true; } | timestamp_stream
  if ! ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
    { echo; ollama_print_start_hint "$BASE_URL"; } | timestamp_stream
    exit 3
  fi
}

log() { ollama_log "$*"; }
warn() { ollama_warn_to_file "$ERRORS_FILE" "$*"; }
need_cmd() { ollama_need_cmd "$1" || exit 2; }
is_uint() { ollama_is_uint "$1"; }
print_file_plain() { ollama_print_file_plain "$1"; }
timestamp_stream() { ollama_timestamp_stream; }
script_dir() { printf '%s
' "$SCRIPT_DIR"; }
script_display_cmd() { ollama_display_cmd "$0"; }

ORIGINAL_ARGC=$#
NO_MODEL_ARGS=0
[[ "$ORIGINAL_ARGC" -eq 0 ]] && NO_MODEL_ARGS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-ctx) NUM_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --long-ctx) LONG_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --num-predict) NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --long-num-predict) LONG_NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --long-prompt-words) LONG_PROMPT_WORDS="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --temperature) TEMPERATURE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --concurrency) CONCURRENCY="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --think) THINK="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --embedding|--embed) EMBEDDING_MODE=1; shift ;;
    --no-embedding|--no-embed) EMBEDDING_MODE=0; shift ;;
    --profile) TEST_PROFILE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --stream) STREAM_GENERATION=1; shift ;;
    --no-stream) STREAM_GENERATION=0; shift ;;
    --load-mode) LOAD_MODE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --prompt-prefix) PROMPT_PREFIX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --server-log-lines) SERVER_LOG_LINES="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --wsl-diagnostics) CAPTURE_WSL_DIAGNOSTICS=1; shift ;;
    --no-wsl-diagnostics) CAPTURE_WSL_DIAGNOSTICS=0; shift ;;
    --full-model-show) FULL_MODEL_SHOW=1; shift ;;
    --no-full-model-show) FULL_MODEL_SHOW=0; shift ;;
    --stress) RUN_CONC=1; [[ "$CONCURRENCY" -lt 2 ]] && CONCURRENCY=2; shift ;;
    --run-conc) RUN_CONC=1; shift ;;
    --no-conc) RUN_CONC=0; shift ;;
    --run-cpu) RUN_CPU=1; shift ;;
    --no-cpu) RUN_CPU=0; shift ;;
    --soak-minutes) SOAK_MINUTES="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --soak-num-predict) SOAK_NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --run-vram-pressure) RUN_VRAM_PRESSURE=1; shift ;;
    --no-vram-pressure) RUN_VRAM_PRESSURE=0; shift ;;
    --vram-model) VRAM_MODEL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --vram-ctx) VRAM_CTX="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --vram-num-predict) VRAM_NUM_PREDICT="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --pull) PULL_IF_MISSING=1; shift ;;
    --no-pull) PULL_IF_MISSING=0; shift ;;
    --ensure-server) ENSURE_SERVER=1; shift ;;
    --no-ensure-server) ENSURE_SERVER=0; shift ;;
    --terminal-summary) PRINT_TERMINAL_SUMMARY=1; shift ;;
    --no-terminal-summary) PRINT_TERMINAL_SUMMARY=0; shift ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "ERROR: unknown argument: $1" >&2; short_usage >&2; exit 2 ;;
    *)
      if [[ -z "$MODEL" ]]; then MODEL="$1"; shift; else echo "ERROR: unexpected extra positional argument: $1" >&2; short_usage >&2; exit 2; fi
      ;;
  esac
done

for n in NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT LONG_PROMPT_WORDS TIMEOUT_SEC CONNECT_TIMEOUT_SEC CONCURRENCY SOAK_MINUTES SOAK_NUM_PREDICT VRAM_CTX VRAM_NUM_PREDICT SERVER_LOG_LINES DECODE512_MIN_EVAL_TOKENS DECODE1024_MIN_EVAL_TOKENS LONGCTX_MIN_EVAL_TOKENS; do
  is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }
done
case "$THINK" in true|false|none|low|medium|high) ;; *) echo "ERROR: --think must be false, true, none, low, medium, or high" >&2; exit 2 ;; esac
case "$LOAD_MODE" in empty-card|observed|warm|unload-model|restart-ollama) ;; *) echo "ERROR: --load-mode must be empty-card, observed, warm, unload-model, or restart-ollama" >&2; exit 2 ;; esac
case "$TEST_PROFILE" in ados|perf|legacy-perf) ;; *) echo "ERROR: --profile must be ados, perf, or legacy-perf" >&2; exit 2 ;; esac
case "$STREAM_GENERATION" in 0|1) ;; *) echo "ERROR: --stream/--no-stream must resolve to 0 or 1" >&2; exit 2 ;; esac
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
FAILURE_HINTS="$RUN_DIR/failure-hints.txt"
SERVER_LOG_TAIL="$RUN_DIR/ollama-server-log-tail.txt"
WSL_DIAG="$RUN_DIR/wsl-diagnostics.txt"
API_VERSION_FILE="$RUN_DIR/ollama-api-version.json"
API_TAGS_FILE="$RUN_DIR/ollama-api-tags.json"
API_SHOW_FILE="$RUN_DIR/ollama-api-show-model.json"
API_SHOW_RAW_FILE="$RUN_DIR/ollama-api-show-model-raw.json"
API_SHOW_FULL_FILE="$RUN_DIR/ollama-api-show-model-full.json"
MODEL_CAPABILITY_FILE="$RUN_DIR/model-capability.json"
LOAD_STATE_FILE="$RUN_DIR/load-state.txt"
CAPABILITY_ANALYSIS="$RUN_DIR/capability-analysis.md"
DMESG_CURSOR_FILE="$RUN_DIR/dmesg-start-line-count.txt"
OLLAMA_SHOW_FILE="$RUN_DIR/ollama-show-model.txt"
mkdir -p "$RUN_DIR" "$RAW_DIR" "$PAYLOAD_DIR" "$TMP_DIR"
: >"$ERRORS_FILE"

SD="$SCRIPT_DIR"

need_cmd curl
need_cmd jq
need_cmd date

# Preflight never starts Ollama. It reports status and prints the exact start command instead.
ensure_server() {
  if [[ "$ENSURE_SERVER" == "0" ]]; then
    if ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then return 0; fi
  fi
  require_ollama_ready
}

select_or_explain_model() {
  local pattern="$1" resolved rc matches
  if [[ -z "$pattern" ]]; then
    echo "ERROR: model pattern is required." >&2
    show_no_args_screen >&2
    exit 2
  fi
  set +e
  resolved="$(ollama_resolve_model_common "$pattern" "$BASE_URL" "$CONNECT_TIMEOUT_SEC")"
  rc=$?
  set -e
  if [[ "$rc" == "0" && -n "$resolved" ]]; then
    MODEL="$resolved"
    MODEL_PATTERN="$pattern"
    return 0
  fi
  if [[ "$rc" == "5" ]]; then
    matches="$resolved"
    echo "ERROR: model pattern '$pattern' is ambiguous. Use one exact model name:" >&2
    ollama_print_model_commands "$(script_display_cmd)" "$matches" "  - " >&2
    echo "Use -h for full options." >&2
    exit 5
  fi
  echo "ERROR: no local Ollama model matched pattern '$pattern'." >&2
  ollama_print_available_model_commands "$BASE_URL" "$(script_display_cmd)" "$CONNECT_TIMEOUT_SEC" >&2 || true
  echo "Use -h for full options." >&2
  exit 4
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
    echo "requested_model=${MODEL_PATTERN:-$MODEL}"
    echo "resolved_model=$MODEL"
    echo "base_url=$BASE_URL"
    echo "think=$THINK"
    echo "embedding_mode=$EMBEDDING_MODE"
    echo "full_model_show=$FULL_MODEL_SHOW"
    echo "model_role=$MODEL_ROLE"
    echo "stream_generation=$STREAM_GENERATION"
    echo "load_mode=$LOAD_MODE"
    echo "test_profile=$TEST_PROFILE"
    echo "empty_card_requested=$EMPTY_CARD_REQUESTED"
    echo "empty_card_verified=$EMPTY_CARD_VERIFIED"
    echo "cold_verified=$COLD_VERIFIED"
    echo "model_resident_before=$MODEL_RESIDENT_BEFORE"
    echo "num_ctx=$NUM_CTX"
    echo "long_ctx=$LONG_CTX"
    echo "num_predict=$NUM_PREDICT"
    echo "long_num_predict=$LONG_NUM_PREDICT"
    echo "long_prompt_words=$LONG_PROMPT_WORDS"
    echo "long_context_min_fill_pct=$LONG_CONTEXT_MIN_FILL_PCT"
    echo "decode512_min_eval_tokens=$DECODE512_MIN_EVAL_TOKENS"
    echo "decode1024_min_eval_tokens=$DECODE1024_MIN_EVAL_TOKENS"
    echo "longctx_min_eval_tokens=$LONGCTX_MIN_EVAL_TOKENS"
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
    echo "server_log_lines=$SERVER_LOG_LINES"
    echo "capture_wsl_diagnostics=$CAPTURE_WSL_DIAGNOSTICS"
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
    nvidia-smi -q -d CLOCK,POWER,TEMPERATURE,PERFORMANCE,PCIE,MEMORY,UTILIZATION >"$RUN_DIR/nvidia-smi-q-$label.txt" 2>&1 || nvidia-smi -q -d POWER,TEMPERATURE,CLOCK,PERFORMANCE,PCI,MEMORY,UTILIZATION >"$RUN_DIR/nvidia-smi-q-$label.txt" 2>&1 || true
    nvidia-smi --query-gpu=timestamp,index,name,driver_version,pci.bus_id,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,utilization.memory,clocks.gr,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,pstate,fan.speed --format=csv >"$RUN_DIR/nvidia-smi-query-$label.csv" 2>&1 || true
  fi
  if command -v ollama >/dev/null 2>&1; then ollama ps >"$RUN_DIR/ollama-ps-$label.txt" 2>&1 || true; else echo "ollama CLI not found" >"$RUN_DIR/ollama-ps-$label.txt"; fi
  curl -fsS "$BASE_URL/api/ps" >"$RUN_DIR/ollama-api-ps-$label.json" 2>/dev/null || true
}

capture_dmesg_cursor() {
  if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | wc -l >"$DMESG_CURSOR_FILE" 2>/dev/null || echo 0 >"$DMESG_CURSOR_FILE"
  else
    echo 0 >"$DMESG_CURSOR_FILE"
  fi
}

capture_dmesg_gpu_errors() {
  local start_line=0 total_lines=0 next_line=1 tmp_all="$RUN_DIR/dmesg-current.txt" tmp_new="$RUN_DIR/dmesg-new-during-run.txt"
  {
    echo "# dmesg GPU/error scan"
    echo "timestamp=$(date -Is)"
    echo
    if ! command -v dmesg >/dev/null 2>&1; then
      echo "dmesg not found"
      return 0
    fi
    dmesg 2>"$RUN_DIR/dmesg.stderr" >"$tmp_all" || { echo "dmesg unavailable; see dmesg.stderr"; return 0; }
    start_line="$(cat "$DMESG_CURSOR_FILE" 2>/dev/null || echo 0)"
    [[ "$start_line" =~ ^[0-9]+$ ]] || start_line=0
    total_lines="$(wc -l <"$tmp_all" 2>/dev/null | tr -dc '0-9')"
    [[ "$total_lines" =~ ^[0-9]+$ ]] || total_lines=0
    next_line=$((start_line + 1))
    echo "## new during this run"
    if (( total_lines >= next_line )); then
      tail -n +"$next_line" "$tmp_all" >"$tmp_new" 2>/dev/null || : >"$tmp_new"
      if grep -Eiq 'nvrm|xid|cuda|gpu|dxg|wsl|nvidia' "$tmp_new"; then
        grep -Ei 'nvrm|xid|cuda|gpu|dxg|wsl|nvidia' "$tmp_new" || true
      else
        echo "none"
      fi
    else
      echo "none"
    fi
    echo
    echo "## historical since boot"
    grep -Ei 'nvrm|xid|cuda|gpu|dxg|wsl|nvidia' "$tmp_all" || true
  } >"$RUN_DIR/dmesg-gpu-errors.txt"
}


capture_wsl_diagnostics() {
  [[ "$CAPTURE_WSL_DIAGNOSTICS" == "1" ]] || { echo "WSL diagnostics disabled" >"$WSL_DIAG"; return 0; }
  {
    echo "# WSL / Windows diagnostics"
    echo "timestamp=$(date -Is)"
    echo
    echo "## Linux kernel"
    uname -a 2>&1 || true
    cat /proc/version 2>/dev/null || true
    echo
    echo "## Ollama model storage and filesystem"
    df -T "$HOME/.ollama" 2>&1 || df -T "$HOME" 2>&1 || true
    du -sh "$HOME/.ollama/models" 2>&1 || true
    echo
    echo "## Mounts relevant to WSL/model storage"
    mount | grep -E ' / |/mnt/c|drvfs|\.ollama' 2>/dev/null || mount 2>&1 | head -80 || true
    echo
    echo "## Block devices"
    lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS 2>&1 || true
    echo
    echo "## kernel command line"
    cat /proc/cmdline 2>/dev/null || true
    echo
    echo "## /etc/wsl.conf"
    if [[ -f /etc/wsl.conf ]]; then sed -n '1,220p' /etc/wsl.conf; else echo "not present"; fi
    echo
    echo "## WSL GPU path"
    ls -l /usr/lib/wsl/lib/nvidia-smi 2>&1 || true
    command -v nvidia-smi 2>&1 || true
    echo
    echo "## WSL commands from Windows interop"
    if command -v wsl.exe >/dev/null 2>&1; then
      wsl.exe --version 2>&1 | tr -d '\r' || true
      echo
      wsl.exe --status 2>&1 | tr -d '\r' || true
      echo
      wsl.exe --list --verbose 2>&1 | tr -d '\r' || true
    else
      echo "wsl.exe not available from this WSL session"
    fi
    echo
    echo "## Windows user .wslconfig"
    local upath=""
    if command -v powershell.exe >/dev/null 2>&1; then
      upath="$(powershell.exe -NoProfile -Command '$env:USERPROFILE' 2>/dev/null | tr -d '\r' | tail -1)"
    elif command -v cmd.exe >/dev/null 2>&1; then
      upath="$(cmd.exe /C echo %USERPROFILE% 2>/dev/null | tr -d '\r' | tail -1)"
    fi
    if [[ -n "$upath" ]] && command -v wslpath >/dev/null 2>&1; then
      local ulinux
      ulinux="$(wslpath -u "$upath" 2>/dev/null || true)"
      echo "windows_userprofile=$upath"
      echo "wsl_userprofile=$ulinux"
      if [[ -n "$ulinux" && -f "$ulinux/.wslconfig" ]]; then
        sed -n '1,220p' "$ulinux/.wslconfig"
      else
        echo ".wslconfig not found at resolved user profile"
      fi
    else
      echo "unable to resolve Windows user profile"
    fi
  } >"$WSL_DIAG" 2>&1 || true
}

capture_ollama_server_log_tail() {
  {
    echo "# Ollama server log tail"
    echo "timestamp=$(date -Is)"
    echo "lines=$SERVER_LOG_LINES"
    echo
    echo "## running Ollama processes"
    pgrep -a -f 'ollama( serve| runner| pull|$)' 2>/dev/null || true
    echo
    if command -v systemctl >/dev/null 2>&1; then
      echo "## systemctl status ollama.service"
      systemctl status ollama.service --no-pager 2>&1 | tail -n "$SERVER_LOG_LINES" || true
      echo
    fi
    if command -v journalctl >/dev/null 2>&1; then
      echo "## journalctl -u ollama.service"
      journalctl -u ollama.service --no-pager -n "$SERVER_LOG_LINES" 2>&1 || true
      echo
      echo "## journalctl --user -u ollama.service"
      journalctl --user -u ollama.service --no-pager -n "$SERVER_LOG_LINES" 2>&1 || true
      echo
    fi
    echo "## common log files"
    local f
    for f in "$HOME/log/ollama-serve.log" "$HOME/.ollama/logs/server.log" "/var/log/ollama.log"; do
      echo "--- $f"
      if [[ -f "$f" ]]; then tail -n "$SERVER_LOG_LINES" "$f" 2>&1 || true; else echo "not found"; fi
      echo
    done
  } >"$SERVER_LOG_TAIL" 2>&1 || true
}

collect_preflight_diagnostics() {
  curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" "$BASE_URL/api/version" >"$API_VERSION_FILE" 2>"$RUN_DIR/ollama-api-version.stderr" || true
  curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" "$BASE_URL/api/tags" >"$API_TAGS_FILE" 2>"$RUN_DIR/ollama-api-tags.stderr" || true
  jq -nc --arg model "$MODEL" '{model:$model, verbose:false}' >"$RUN_DIR/ollama-api-show-request.json"
  curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" -H 'Content-Type: application/json' -d "@$RUN_DIR/ollama-api-show-request.json" "$BASE_URL/api/show" >"$API_SHOW_RAW_FILE" 2>"$RUN_DIR/ollama-api-show-model.stderr" || true
  if [[ -s "$API_SHOW_RAW_FILE" ]] && jq -e . "$API_SHOW_RAW_FILE" >/dev/null 2>&1; then
    ollama_model_show_slim "$MODEL" <"$API_SHOW_RAW_FILE" >"$API_SHOW_FILE" 2>/dev/null || cp "$API_SHOW_RAW_FILE" "$API_SHOW_FILE"
    MODEL_ROLE="$(ollama_model_role_from_show_json <"$API_SHOW_RAW_FILE" 2>/dev/null || printf 'unknown')"
    jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" --slurpfile show "$API_SHOW_FILE" '{model:$model, role:$role, slim_show:($show[0] // {})}' >"$MODEL_CAPABILITY_FILE" 2>/dev/null || true
  else
    MODEL_ROLE="unknown"
    jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" '{model:$model, role:$role, slim_show:{}}' >"$MODEL_CAPABILITY_FILE" 2>/dev/null || true
  fi
  if [[ "$FULL_MODEL_SHOW" == "1" ]]; then
    jq -nc --arg model "$MODEL" '{model:$model, verbose:true}' >"$RUN_DIR/ollama-api-show-full-request.json"
    curl -fsS --connect-timeout "$CONNECT_TIMEOUT_SEC" -H 'Content-Type: application/json' -d "@$RUN_DIR/ollama-api-show-full-request.json" "$BASE_URL/api/show" >"$API_SHOW_FULL_FILE" 2>"$RUN_DIR/ollama-api-show-model-full.stderr" || true
  fi
  if command -v ollama >/dev/null 2>&1; then
    {
      echo "# ollama show $MODEL"
      ollama show "$MODEL" 2>&1 || true
      echo
      echo "# ollama show --modelfile $MODEL"
      ollama show --modelfile "$MODEL" 2>&1 || true
      echo
      echo "# ollama list"
      ollama list 2>&1 || true
    } >"$OLLAMA_SHOW_FILE" 2>&1 || true
  fi
  capture_wsl_diagnostics || true
}

extract_blob_path_from_text() {
  grep -oE '/[^[:space:]"'"'"']*sha256-[0-9a-f]{32,64}' <<<"$1" | head -1 || true
}

model_size_gib() {
  if [[ -s "$API_TAGS_FILE" ]]; then
    jq -r --arg m "$MODEL" '.models[]? | select(.name==$m or .model==$m) | (.size // empty)' "$API_TAGS_FILE" 2>/dev/null \
      | awk 'NF{printf "%.2f", $1/1024/1024/1024; exit}'
  fi
}

free_vram_before_gib() {
  local f="$RUN_DIR/nvidia-smi-query-before.csv"
  [[ -s "$f" ]] || return 0
  awk -F',' '
    function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
    NR==1{for(i=1;i<=NF;i++) h[trim($i)]=i; next}
    NR==2{used=trim($(h["memory.used [MiB]"])); total=trim($(h["memory.total [MiB]"])); if(total>0){printf "%.2f", (total-used)/1024}; exit}' "$f" 2>/dev/null || true
}

make_failure_hints() {
  local first_body="" first_class="" body class f count=0 unsupported_count=0 blob model_gib free_gib
  {
    echo "# RTX 3090 Ollama failure hints"
    echo "timestamp=$(date -Is)"
    echo "requested_model=${MODEL_PATTERN:-$MODEL}"
    echo "resolved_model=$MODEL"
    echo "base_url=$BASE_URL"
    echo
  } >"$FAILURE_HINTS"
  shopt -s nullglob
  for f in "$RAW_DIR"/*.json; do
    [[ -e "$f" ]] || continue
    case "$(basename "$f")" in *.stream-metrics.json) continue ;; esac
    [[ -e "${f%.json}.http" ]] || continue
    if jq -e '(.result_state? == "UNSUPPORTED") or ((.error? // "") | test("embedding-only|does not support generate"; "i"))' "$f" >/dev/null 2>&1; then unsupported_count=$((unsupported_count + 1)); continue; fi
    raw_response_is_error "$f" "${f%.json}.http" || continue
    body="$(error_body_from_raw "$f" "${f%.json}.stderr")"
    [[ -n "$body" ]] || body="http=$(cat "${f%.json}.http" 2>/dev/null || printf 000) raw=$(head -c 500 "$f" 2>/dev/null | tr '\n' ' ')"
    local_http="$(tr -dc '0-9' <"${f%.json}.http" 2>/dev/null | tail -c 3)"; [[ -n "$local_http" ]] || local_http=000
    class="$(classify_failure 0 "$local_http" "$body" "${f%.json}.stderr")"
    if [[ -z "$first_body" ]]; then first_body="$body"; first_class="$class"; fi
    count=$((count + 1))
  done
  shopt -u nullglob
  if [[ "$unsupported_count" -gt 0 ]]; then
    {
      echo "primary_error_class=unsupported_generate_for_embedding_model"
      echo "api_error_rows=0"
      echo "first_api_error=model $MODEL is embedding-only for generation mode"
      echo "likely_cause=selected model is embedding-only and does not support /api/generate."
      echo "next_action=use a generation model with ollama test, or run embedding mode with: ollama embed-test $MODEL"
    } >>"$FAILURE_HINTS"
    return 0
  fi
  if [[ "$count" -eq 0 ]]; then
    {
      echo "primary_error_class=none"
      echo "api_error_rows=0"
      echo "first_api_error="
      echo "likely_cause=no API error bodies found"
      echo "next_action=review summary.csv and raw JSON for non-error anomalies"
    } >>"$FAILURE_HINTS"
    return 0
  fi
  {
    echo "primary_error_class=$first_class"
    echo "api_error_rows=$count"
    echo "first_api_error=$(printf '%s' "$first_body" | tr '\n' ' ' | cut -c1-900)"
    blob="$(extract_blob_path_from_text "$first_body")"
    if [[ -n "$blob" ]]; then
      echo "referenced_blob=$blob"
      echo "blob_stat_command=stat '$blob' && sha256sum '$blob'"
    fi
    model_gib="$(model_size_gib || true)"
    free_gib="$(free_vram_before_gib || true)"
    [[ -n "$model_gib" ]] && echo "model_size_gib=$model_gib"
    [[ -n "$free_gib" ]] && echo "free_vram_before_gib=$free_gib"
    case "$first_class" in
      model_load_error|model_file_or_manifest_error)
        echo "likely_cause=Ollama accepted the model manifest but the runner could not open/load a referenced blob; most likely corrupt/incomplete model storage, permission mismatch, or an edge-of-VRAM load path."
        echo "next_action=stop concurrent ollama pulls, inspect the referenced blob path, capture ollama-server-log-tail.txt, then recreate or repull the model before rerunning the benchmark."
        ;;
      unsupported_generate_for_embedding_model)
        echo "likely_cause=selected model is embedding-only and does not support /api/generate."
        echo "next_action=use a generation model with ollama test, or run embedding mode with: ollama embed-test ${MODEL}"
        ;;
      embedding_empty_response)
        echo "likely_cause=/api/embed returned JSON but no embedding vectors or vector dimension was detected."
        echo "next_action=inspect raw/*.json and rerun with a known embedding model such as bge-m3."
        ;;
      memory_allocation_error)
        echo "likely_cause=model/context/concurrency combination exceeded available VRAM or host memory."
        echo "next_action=reduce context/concurrency, free display/WSLg VRAM, enable Flash Attention/KV-cache testing, or use a smaller quant/model."
        ;;
      request_timeout|curl_transport_error)
        echo "likely_cause=Ollama API transport or server availability issue."
        echo "next_action=check Ollama service status, server logs, WSL networking/DNS, and retry with a tiny model."
        ;;
      *)
        echo "likely_cause=unclassified Ollama/API failure; inspect raw/*.json, raw/*.stderr, and server logs."
        echo "next_action=rerun with --server-log-lines 500 and include the generated archive."
        ;;
    esac
    if pgrep -f 'ollama pull' >/dev/null 2>&1; then
      echo "concurrent_pull_observed_now=yes"
      echo "concurrent_pull_note=Avoid benchmarking while ollama pull is running; it can contend for model-store IO and mutate model blobs/manifests."
    fi
  } >>"$FAILURE_HINTS"
}

csv_header() {
  printf '%s
' 'timestamp,category,test,model,num_ctx,num_predict,mode,concurrency,request_wall_s,response_chars,thinking_chars,done_reason,total_s,load_s,prompt_eval_tokens,eval_tokens,prompt_tps,gen_tps,prompt_eval_s,eval_s,prompt_chars,prompt_words,context_fill_pct,error,http_code,error_class,error_body,raw_json,payload_json,endpoint,vector_count,vector_dim,embedding_tps,ttft_any_ms,ttft_thinking_ms,ttft_answer_ms,time_to_100_tokens_ms,end_to_end_500_ms,decode_tps_raw,visible_answer_tps,thinking_only,sample_status,result_state' >"$SUMMARY_CSV"
  printf '%s
' 'timestamp,concurrency,wall_s,total_eval_tokens,total_response_chars,aggregate_gen_tps,requests_ok,requests_error,raw_glob' >"$CONC_AGG_CSV"
  printf '%s
' 'timestamp,iterations,wall_s,total_eval_tokens,aggregate_gen_tps,errors' >"$SOAK_SUMMARY_CSV"
}

build_payload() {
  local model_name="$1" prompt="$2" np="$3" ctx="$4" mode="$5" gpu_opts='{}' think_json='null' stream_json="$STREAM_GENERATION"
  if [[ "$mode" == "CPU" ]]; then gpu_opts='{"num_gpu":0}'; fi
  [[ "$stream_json" == "1" ]] && stream_json=true || stream_json=false
  case "$THINK" in
    true|false) think_json="$THINK" ;;
    low|medium|high) think_json="$(jq -Rn --arg v "$THINK" '$v')" ;;
    none) think_json='null' ;;
  esac
  jq -nc \
    --arg model "$model_name" --arg prompt "$prompt" --arg keep "$KEEP_ALIVE" \
    --argjson np "$np" --argjson ctx "$ctx" --argjson temp "$TEMPERATURE" \
    --argjson gpu_opts "$gpu_opts" --argjson think "$think_json" --argjson stream "$stream_json" \
    '{model:$model,prompt:$prompt,stream:$stream,keep_alive:$keep,options:({num_predict:$np,num_ctx:$ctx,temperature:$temp,seed:42} + $gpu_opts)} | if $think == null then . else . + {think:$think} end'
}

prompt_word_count() { awk '{n+=NF} END{print n+0}' <<<"$1"; }

ollama_curl_generate_stream() {
  local timeout_sec="$1" connect_timeout_sec="$2" payload_file="$3" stream_file="$4" http_file="$5" stderr_file="$6" base_url="$7" start_ns="$8" metrics_file="$9"
  local first_any_file="$metrics_file.first_any_ns" first_thinking_file="$metrics_file.first_thinking_ns" first_answer_file="$metrics_file.first_answer_ns" rc
  : >"$stream_file"; : >"$http_file"; : >"$stderr_file"; rm -f "$first_any_file" "$first_thinking_file" "$first_answer_file" "$metrics_file"
  set +e
  {
    if command -v timeout >/dev/null 2>&1; then
      timeout -k 10s "$timeout_sec" curl -sS --no-buffer --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/x-ndjson, application/json' -d "@$payload_file" --write-out '\n__OLLAMA_HTTP_CODE__:%{http_code}\n' "$base_url/api/generate"
    else
      curl -sS --no-buffer --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/x-ndjson, application/json' -d "@$payload_file" --write-out '\n__OLLAMA_HTTP_CODE__:%{http_code}\n' "$base_url/api/generate"
    fi
  } 2>"$stderr_file" | while IFS= read -r line; do
    local ns
    [[ -n "$line" ]] || continue
    ns="$(date +%s%N)"
    case "$line" in
      __OLLAMA_HTTP_CODE__:*) printf '%s' "${line#__OLLAMA_HTTP_CODE__:}" >"$http_file" ;;
      *)
        printf '%s\n' "$line" >>"$stream_file"
        [[ -s "$first_any_file" ]] || printf '%s\n' "$ns" >"$first_any_file"
        if [[ ! -s "$first_answer_file" ]] && jq -e '((.response? // "") | length) > 0' <<<"$line" >/dev/null 2>&1; then printf '%s\n' "$ns" >"$first_answer_file"; fi
        if [[ ! -s "$first_thinking_file" ]] && jq -e '((.thinking? // "") | length) > 0' <<<"$line" >/dev/null 2>&1; then printf '%s\n' "$ns" >"$first_thinking_file"; fi
        ;;
    esac
  done
  rc=${PIPESTATUS[0]}
  set -e
  local any_ns thinking_ns answer_ns any_ms thinking_ms answer_ms
  any_ns="$(cat "$first_any_file" 2>/dev/null || true)"; thinking_ns="$(cat "$first_thinking_file" 2>/dev/null || true)"; answer_ns="$(cat "$first_answer_file" 2>/dev/null || true)"
  any_ms="$(awk -v s="$start_ns" -v n="${any_ns:-0}" 'BEGIN{if(n>0) printf "%.3f", (n-s)/1000000; else print ""}')"
  thinking_ms="$(awk -v s="$start_ns" -v n="${thinking_ns:-0}" 'BEGIN{if(n>0) printf "%.3f", (n-s)/1000000; else print ""}')"
  answer_ms="$(awk -v s="$start_ns" -v n="${answer_ns:-0}" 'BEGIN{if(n>0) printf "%.3f", (n-s)/1000000; else print ""}')"
  jq -n --arg any "$any_ms" --arg thinking "$thinking_ms" --arg answer "$answer_ms" \
    '{ttft_any_ms: (if $any=="" then null else ($any|tonumber) end), ttft_thinking_ms: (if $thinking=="" then null else ($thinking|tonumber) end), ttft_answer_ms: (if $answer=="" then null else ($answer|tonumber) end)}' >"$metrics_file" 2>/dev/null || true
  # Sidecar timestamp files are implementation scratch; stream-metrics JSON is the durable output.
  rm -f "$first_any_file" "$first_thinking_file" "$first_answer_file" 2>/dev/null || true
  return "$rc"
}

ollama_stream_to_final_json() {
  local stream_file="$1" raw_file="$2" metrics_file="$3"
  if [[ -s "$stream_file" ]] && jq -s --slurpfile metrics "$metrics_file" '
      (map(select(type=="object"))) as $rows |
      if ($rows|length) == 0 then {error:"empty streaming response", _stream_metrics:($metrics[0] // {})}
      else
        (([$rows[] | select(.done == true)] | last) // ($rows[-1] // {})) as $final |
        $final + {
          response: ($rows | map(.response? // "") | join("")),
          thinking: ($rows | map(.thinking? // "") | join("")),
          _stream_metrics: ($metrics[0] // {})
        }
      end' "$stream_file" >"$raw_file" 2>"$raw_file.jqstderr"; then
    return 0
  fi
  if [[ -s "$stream_file" ]]; then
    cp "$stream_file" "$raw_file"
  else
    jq -n --slurpfile metrics "$metrics_file" '{error:"empty streaming response", _stream_metrics:($metrics[0] // {})}' >"$raw_file" 2>/dev/null || : >"$raw_file"
  fi
}

model_resident_in_file() {
  local file="$1" model_name="$2"
  [[ -s "$file" ]] || return 1
  if [[ "$file" == *.json ]]; then
    jq -e --arg m "$model_name" '(.models // [])[]? | select((.name // .model // "") == $m or (.model // "") == $m)' "$file" >/dev/null 2>&1 && return 0
  fi
  grep -F -- "$model_name" "$file" >/dev/null 2>&1
}

loaded_model_names_from_file() {
  local file="${1:-}"
  [[ -s "$file" ]] || return 0
  if [[ "$file" == *.json ]]; then
    jq -r '(.models // [])[]? | (.name // .model // empty)' "$file" 2>/dev/null | sed '/^$/d' || true
  else
    awk 'NR>1 && $1!="NAME" && $1!="" {print $1}' "$file" 2>/dev/null || true
  fi
}

loaded_model_names_before() {
  local names=""
  names="$(loaded_model_names_from_file "$RUN_DIR/ollama-api-ps-before.json" | sort -u | tr '
' ',' | sed 's/,$//')"
  if [[ -z "$names" ]]; then
    names="$(loaded_model_names_from_file "$RUN_DIR/ollama-ps-before.txt" | sort -u | tr '
' ',' | sed 's/,$//')"
  fi
  printf '%s
' "$names"
}

loaded_model_names_for_prefix() {
  local prefix="$1" names=""
  names="$(loaded_model_names_from_file "$RUN_DIR/ollama-api-ps-$prefix.json" | sort -u | tr '
' ',' | sed 's/,$//')"
  if [[ -z "$names" ]]; then
    names="$(loaded_model_names_from_file "$RUN_DIR/ollama-ps-$prefix.txt" | sort -u | tr '
' ',' | sed 's/,$//')"
  fi
  printf '%s
' "$names"
}

count_csv_names() {
  local csv="${1:-}"
  [[ -n "$csv" ]] || { echo 0; return 0; }
  awk -F',' 'NF>0{print NF}' <<<"$csv"
}

csv_contains_name() {
  local csv="${1:-}" needle="${2:-}"
  [[ -n "$csv" && -n "$needle" ]] || return 1
  awk -F',' -v n="$needle" '{for(i=1;i<=NF;i++) if($i==n) found=1} END{exit found?0:1}' <<<"$csv"
}

model_processor_from_ps_file() {
  local file="${1:-}" model_name="${2:-}"
  [[ -s "$file" && -n "$model_name" ]] || return 0
  awk -v m="$model_name" '
    NR>1 && $1==m {
      p=""
      # ollama ps columns split SIZE into two fields, so PROCESSOR starts at field 5.
      for(i=5;i<=NF;i++){
        if($i ~ /^[0-9]+$/) break
        p=(p==""?$i:p" "$i)
      }
      print p
      exit
    }' "$file" 2>/dev/null || true
}

model_processor_after() {
  model_processor_from_ps_file "$RUN_DIR/ollama-ps-after.txt" "$MODEL"
}

processor_residency_state() {
  local processor="${1:-}"
  if [[ -z "$processor" ]]; then
    echo "unknown"
  elif [[ "$processor" == "100% GPU" ]]; then
    echo "full_gpu"
  elif [[ "$processor" == *CPU* && "$processor" == *GPU* ]]; then
    echo "cpu_gpu_offload"
  elif [[ "$processor" == *CPU* ]]; then
    echo "cpu_only_or_cpu_heavy"
  else
    echo "non_full_gpu"
  fi
}


ollama_unload_named_model() {
  local model_name="$1" role="${2:-unknown}" safe raw payload http err endpoint
  safe="$(printf '%s' "$model_name" | tr -c 'A-Za-z0-9_.:-' '_' | cut -c1-120)"
  payload="$RUN_DIR/unload-any-${safe}.request.json"
  raw="$RUN_DIR/unload-any-${safe}.response.json"
  http="$RUN_DIR/unload-any-${safe}.http"
  err="$RUN_DIR/unload-any-${safe}.stderr"
  [[ -n "$role" && "$role" != "unknown" ]] || role="$(ollama_model_role_common "$model_name" "$BASE_URL" "$CONNECT_TIMEOUT_SEC" 2>/dev/null || printf 'generate')"
  log "LoadMode: requesting unload for resident model $model_name role=$role"
  if [[ "$role" == "embedding" ]]; then
    jq -nc --arg model "$model_name" '{model:$model,input:"unload",keep_alive:0}' >"$payload"
    ollama_curl_embed "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload" "$raw" "$http" "$err" "$BASE_URL" || true
  else
    jq -nc --arg model "$model_name" '{model:$model,prompt:"",stream:false,keep_alive:0,options:{num_predict:0}}' >"$payload"
    ollama_curl_generate "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload" "$raw" "$http" "$err" "$BASE_URL" || true
  fi
}

ollama_unload_all_loaded_models() {
  local names name role
  names="$(loaded_model_names_before)"
  if [[ -z "$names" ]]; then
    log "LoadMode: empty-card requested; no resident Ollama models detected before unload"
    return 0
  fi
  log "LoadMode: empty-card requested; unloading resident Ollama model(s): $names"
  IFS=',' read -r -a __loaded_models <<<"$names"
  for name in "${__loaded_models[@]}"; do
    [[ -n "$name" ]] || continue
    role="$(ollama_model_role_common "$name" "$BASE_URL" "$CONNECT_TIMEOUT_SEC" 2>/dev/null || printf 'generate')"
    ollama_unload_named_model "$name" "$role" || true
  done
  sleep 1
}

assess_load_state() {
  RESIDENT_MODELS_BEFORE="$(loaded_model_names_before)"
  RESIDENT_COUNT_BEFORE="$(count_csv_names "$RESIDENT_MODELS_BEFORE")"
  OTHER_MODELS_RESIDENT_BEFORE="0"
  MODEL_RESIDENT_BEFORE="absent_all_clear"
  LOAD_STATE_VERDICT="observed_absent_clean"
  EMPTY_CARD_REQUESTED="0"
  EMPTY_CARD_VERIFIED="0"

  if csv_contains_name "$RESIDENT_MODELS_BEFORE" "$MODEL"; then
    MODEL_RESIDENT_BEFORE="present"
    LOAD_STATE_VERDICT="warm_or_resident_before"
  elif [[ "${RESIDENT_COUNT_BEFORE:-0}" -gt 0 ]]; then
    MODEL_RESIDENT_BEFORE="tested_absent_other_present"
    OTHER_MODELS_RESIDENT_BEFORE="1"
    LOAD_STATE_VERDICT="model_switch_observed"
  fi

  COLD_VERIFIED="0"
  if [[ "$LOAD_MODE" == "empty-card" ]]; then
    EMPTY_CARD_REQUESTED="1"
    ollama_unload_all_loaded_models || true
    snapshot_before_after before-empty-card-check
    local after_empty_names after_empty_count
    after_empty_names="$(loaded_model_names_for_prefix before-empty-card-check)"
    after_empty_count="$(count_csv_names "$after_empty_names")"
    if [[ "${after_empty_count:-0}" -eq 0 ]]; then
      EMPTY_CARD_VERIFIED="1"
      COLD_VERIFIED="1"
      MODEL_RESIDENT_BEFORE="absent_after_empty_card_unload"
      OTHER_MODELS_RESIDENT_BEFORE="0"
      LOAD_STATE_VERDICT="empty_card_verified"
    elif csv_contains_name "$after_empty_names" "$MODEL"; then
      EMPTY_CARD_VERIFIED="0"
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="present_after_empty_card_unload_failed"
      LOAD_STATE_VERDICT="empty_card_unload_failed_model_still_resident"
    else
      EMPTY_CARD_VERIFIED="0"
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="tested_absent_after_empty_card_other_present"
      OTHER_MODELS_RESIDENT_BEFORE="1"
      LOAD_STATE_VERDICT="empty_card_unload_incomplete_other_model_resident"
    fi
  elif [[ "$LOAD_MODE" == "warm" ]]; then
    LOAD_STATE_VERDICT="warm_requested"
    COLD_VERIFIED="0"
  elif [[ "$LOAD_MODE" == "unload-model" ]]; then
    ollama_unload_model || true
    snapshot_before_after before-unload-check
    local after_unload_names after_unload_count
    after_unload_names="$(loaded_model_names_for_prefix before-unload-check)"
    after_unload_count="$(count_csv_names "$after_unload_names")"
    if csv_contains_name "$after_unload_names" "$MODEL"; then
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="present_after_unload_failed"
      LOAD_STATE_VERDICT="unload_failed_model_still_resident"
    elif [[ "${after_unload_count:-0}" -gt 0 ]]; then
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="tested_absent_after_unload_other_present"
      OTHER_MODELS_RESIDENT_BEFORE="1"
      LOAD_STATE_VERDICT="unload_verified_but_other_model_resident"
    else
      COLD_VERIFIED="1"
      MODEL_RESIDENT_BEFORE="absent_after_unload"
      LOAD_STATE_VERDICT="cold_verified_after_unload"
    fi
  elif [[ "$LOAD_MODE" == "restart-ollama" ]]; then
    ollama_restart_service || true
    sleep 2
    snapshot_before_after before-restart-check
    local after_restart_names after_restart_count
    after_restart_names="$(loaded_model_names_for_prefix before-restart-check)"
    after_restart_count="$(count_csv_names "$after_restart_names")"
    if csv_contains_name "$after_restart_names" "$MODEL"; then
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="present_after_restart"
      LOAD_STATE_VERDICT="restart_attempt_model_still_resident"
    elif [[ "${after_restart_count:-0}" -gt 0 ]]; then
      COLD_VERIFIED="0"
      MODEL_RESIDENT_BEFORE="tested_absent_after_restart_other_present"
      OTHER_MODELS_RESIDENT_BEFORE="1"
      LOAD_STATE_VERDICT="restart_verified_but_other_model_resident"
    else
      COLD_VERIFIED="1"
      MODEL_RESIDENT_BEFORE="absent_after_restart"
      LOAD_STATE_VERDICT="cold_verified_after_restart"
    fi
  fi

  {
    echo "load_mode=$LOAD_MODE"
    echo "test_profile=$TEST_PROFILE"
    echo "empty_card_requested=$EMPTY_CARD_REQUESTED"
    echo "empty_card_verified=$EMPTY_CARD_VERIFIED"
    echo "model_resident_before=$MODEL_RESIDENT_BEFORE"
    echo "resident_count_before=$RESIDENT_COUNT_BEFORE"
    echo "resident_models_before=${RESIDENT_MODELS_BEFORE:-none}"
    echo "other_models_resident_before=$OTHER_MODELS_RESIDENT_BEFORE"
    echo "load_state_verdict=$LOAD_STATE_VERDICT"
    echo "cold_verified=$COLD_VERIFIED"
    echo "note=FirstReqLoad is Ollama load_duration on the first benchmark request. Empty-card mode unloads all resident Ollama models before testing and verifies /api/ps is empty when possible. ColdVerified means model-residency preconditions were verified; it is not a disk-cache or storage-throughput claim."
  } >"$LOAD_STATE_FILE"
}
ollama_restart_service() {
  log "LoadMode: requesting Ollama service restart before benchmark"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart ollama >/dev/null 2>"$RUN_DIR/restart-ollama.stderr" && { printf 'systemctl --user restart ollama
' >"$RUN_DIR/restart-ollama.command"; return 0; }
    systemctl restart ollama >/dev/null 2>>"$RUN_DIR/restart-ollama.stderr" && { printf 'systemctl restart ollama
' >"$RUN_DIR/restart-ollama.command"; return 0; }
  fi
  warn "LOAD_MODE=restart-ollama could not restart Ollama via systemctl; ColdVerified requires model absence evidence after restart"
  return 1
}

ollama_unload_model() {
  local payload="$RUN_DIR/unload-model-request.json" raw="$RUN_DIR/unload-model-response.json" http="$RUN_DIR/unload-model.http" err="$RUN_DIR/unload-model.stderr"
  log "LoadMode: requesting unload for $MODEL before benchmark"
  if [[ "$EMBEDDING_MODE" == "1" || "$MODEL_ROLE" == "embedding" ]]; then
    jq -nc --arg model "$MODEL" '{model:$model,input:"unload",keep_alive:0}' >"$payload"
    ollama_curl_embed "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload" "$raw" "$http" "$err" "$BASE_URL" || true
  else
    jq -nc --arg model "$MODEL" '{model:$model,prompt:"",stream:false,keep_alive:0,options:{num_predict:0}}' >"$payload"
    ollama_curl_generate "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload" "$raw" "$http" "$err" "$BASE_URL" || true
  fi
}

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

error_body_from_raw() {
  local raw_file="$1" stderr_file="$2" body=""
  # A successful Ollama /api/generate response is valid JSON too. Do not treat
  # successful JSON as an error body. Only explicit error/message/detail fields
  # in JSON are error bodies. Non-JSON raw text can still be diagnostic output.
  if [[ -s "$raw_file" ]] && jq -e . "$raw_file" >/dev/null 2>&1; then
    body="$(jq -r 'if has("error") then (.error|tostring) elif has("message") then (.message|tostring) elif has("detail") then (.detail|tostring) else empty end' "$raw_file" 2>/dev/null | head -c 1200)"
  elif [[ -s "$raw_file" ]]; then
    body="$(head -c 1200 "$raw_file" | tr '\n' ' ')"
  fi
  if [[ -z "$body" && -s "$stderr_file" ]]; then
    body="$(head -c 1200 "$stderr_file" | tr '\n' ' ')"
  fi
  printf '%s' "$body"
}

raw_response_is_error() {
  local raw_file="$1" http_file="${2:-}" http_code="000"
  if [[ -n "$http_file" && -s "$http_file" ]]; then
    http_code="$(tr -dc '0-9' <"$http_file" 2>/dev/null | tail -c 3)"
    [[ -n "$http_code" ]] || http_code="000"
  fi
  if [[ ! "$http_code" =~ ^2 ]]; then return 0; fi
  if [[ ! -s "$raw_file" ]]; then return 1; fi
  if ! jq -e . "$raw_file" >/dev/null 2>&1; then return 0; fi
  jq -e 'has("error")' "$raw_file" >/dev/null 2>&1
}

classify_failure() {
  local rc="$1" http_code="$2" body="$3" stderr_file="${4:-}" text lc
  text="$body"
  if [[ -z "$text" && -n "$stderr_file" && -s "$stderr_file" ]]; then text="$(tr '\n' ' ' <"$stderr_file")"; fi
  lc="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if [[ "$rc" == "124" || "$rc" == "137" ]]; then printf 'request_timeout'; return 0; fi
  if [[ "$rc" != "0" && "$http_code" == "000" ]]; then printf 'curl_transport_error'; return 0; fi
  if grep -qiE 'does not support generate|not support generate|unsupported.*generate|embedding-only.*generate' <<<"$text"; then printf 'unsupported_generate_for_embedding_model'; return 0; fi
  if grep -qiE 'empty embedding|no embedding|embedding vector.*missing|vector dimension.*missing' <<<"$text"; then printf 'embedding_empty_response'; return 0; fi
  if grep -qiE 'unable to load model' <<<"$text"; then printf 'model_load_error'; return 0; fi
  if grep -qiE 'no such file|cannot find|not found|missing|bad manifest|bad file|invalid file|checksum|sha256' <<<"$text"; then printf 'model_file_or_manifest_error'; return 0; fi
  if grep -qiE 'out of memory|cuda.*memory|memory allocation|insufficient.*memory|failed to allocate|no memory|oom' <<<"$text"; then printf 'memory_allocation_error'; return 0; fi
  if grep -qiE 'permission denied|operation not permitted|access denied' <<<"$text"; then printf 'permission_error'; return 0; fi
  if [[ "$http_code" =~ ^5 ]]; then printf 'ollama_server_error_%s' "$http_code"; return 0; fi
  if [[ "$http_code" =~ ^4 ]]; then printf 'ollama_client_error_%s' "$http_code"; return 0; fi
  if [[ "$rc" != "0" ]]; then printf 'curl_failed_rc_%s' "$rc"; return 0; fi
  if [[ -z "$text" ]]; then printf 'none'; return 0; fi
  printf 'api_error'
}

append_summary_from_json() {
  local category="$1" test_name="$2" model_name="$3" mode="$4" conc="$5" np="$6" ctx="$7" raw_file="$8" payload_file="$9" wall_s="${10}" prompt_chars="${11}" prompt_words="${12}" err_msg="${13:-}" http_code="${14:-}" error_class="${15:-}" error_body="${16:-}"
  local line
  [[ -n "$http_code" ]] || http_code=""
  [[ -n "$error_class" ]] || error_class="$err_msg"
  if [[ -n "$err_msg" ]]; then
    local result_state="FAIL" sample_status="ERROR"
    if [[ "$error_class" == "unsupported_generate_for_embedding_model" ]]; then result_state="UNSUPPORTED"; sample_status="UNSUPPORTED"; fi
    line="$(jq -rn --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg err "$err_msg" --arg http "$http_code" --arg cls "$error_class" --arg body "$error_body" --arg raw "$raw_file" --arg payload "$payload_file" --arg sample "$sample_status" --arg state "$result_state" \
      '[$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,"","","","","","","","","","","",$pc,$pw,"",$err,$http,$cls,$body,$raw,$payload,"/api/generate","","","","","","","","","","","",$sample,$state] | @csv')"
    append_csv_line "$line"
    return 0
  fi
  line="$(jq -r --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg http "$http_code" --arg raw "$raw_file" --arg payload "$payload_file" --argjson min512 "$DECODE512_MIN_EVAL_TOKENS" --argjson min1024 "$DECODE1024_MIN_EVAL_TOKENS" --argjson minlong "$LONGCTX_MIN_EVAL_TOKENS" --argjson minfill "$LONG_CONTEXT_MIN_FILL_PCT" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    def fill(tokens; ctx): if tokens == null or ctx == null or (ctx|tonumber)==0 then null else (100 * (tokens|tonumber) / (ctx|tonumber)) end;
    def metric($k): (._stream_metrics[$k] // null);
    def eval_tokens: (.eval_count // 0);
    def gen_tps: (tps(.eval_count;.eval_duration));
    def fill_pct: (fill(.prompt_eval_count;$ctx));
    def sample_status:
      if $cat == "throughput" and eval_tokens < $min512 then "SHORT_SAMPLE"
      elif $cat == "sustained" and eval_tokens < $min1024 then "SHORT_SAMPLE"
      elif $cat == "longctx" and ((fill_pct // 0) < $minfill) then "UNDERFILLED"
      elif $cat == "longctx" and eval_tokens < $minlong then "SHORT_SAMPLE"
      else "OK" end;
    def result_state: if sample_status == "OK" then "PASS" else "INCONCLUSIVE" end;
    def thinking_only: (((.response // "")|length) == 0 and ((.thinking // "")|length) > 0);
    def ttfa: metric("ttft_answer_ms");
    def e2e_tokens($n): if (ttfa != null and gen_tps != null and gen_tps > 0) then (ttfa + (($n / gen_tps) * 1000)) else null end;
    [$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,((.response // "")|length),((.thinking // "")|length),(.done_reason // ""),(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),(.eval_count//""),(tps(.prompt_eval_count;.prompt_eval_duration)//""),(gen_tps//""),(sec(.prompt_eval_duration)//""),(sec(.eval_duration)//""),$pc,$pw,(fill_pct//""),"",$http,"","",$raw,$payload,"/api/generate","","","",(metric("ttft_any_ms")//""),(metric("ttft_thinking_ms")//""),(metric("ttft_answer_ms")//""),(e2e_tokens(100)//""),(e2e_tokens(500)//""),(gen_tps//""),(if (((.response // "")|length)>0) then (gen_tps//"") else "" end),(thinking_only|tostring),sample_status,result_state] | @csv' "$raw_file")"
  append_csv_line "$line"
}

run_generate() {
  local category="$1" test_name="$2" model_name="$3" mode="$4" conc="$5" np="$6" ctx="$7" prompt="$8" step_label="${9:-?}"
  local payload_file="$PAYLOAD_DIR/$test_name.json" raw_file="$RAW_DIR/$test_name.json" stream_file="$RAW_DIR/$test_name.stream.ndjson" metrics_file="$RAW_DIR/$test_name.stream-metrics.json" stderr_file="$RAW_DIR/$test_name.stderr" http_file="$RAW_DIR/$test_name.http" rc=0 start_ns end_ns wall_s prompt_chars prompt_words http_code error_body error_class
  prompt_chars="${#prompt}"
  prompt_words="$(prompt_word_count "$prompt")"
  build_payload "$model_name" "$prompt" "$np" "$ctx" "$mode" >"$payload_file"
  log "START [$step_label/$PLANNED_TESTS] $test_name: category=$category model=$model_name mode=$mode ctx=$ctx predict=$np conc=$conc prompt_words=$prompt_words stream=$STREAM_GENERATION"
  start_ns="$(date +%s%N)"
  set +e
  if [[ "$STREAM_GENERATION" == "1" ]]; then
    ollama_curl_generate_stream "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload_file" "$stream_file" "$http_file" "$stderr_file" "$BASE_URL" "$start_ns" "$metrics_file"
    rc=$?
    ollama_stream_to_final_json "$stream_file" "$raw_file" "$metrics_file"
  else
    ollama_curl_generate "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload_file" "$raw_file" "$http_file" "$stderr_file" "$BASE_URL"
    rc=$?
  fi
  set -e
  end_ns="$(date +%s%N)"
  wall_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.6f", (e-s)/1000000000}')"
  http_code="$(tr -dc '0-9' <"$http_file" 2>/dev/null | tail -c 3)"
  [[ -n "$http_code" ]] || http_code="000"

  if [[ "$rc" -ne 0 || ! "$http_code" =~ ^2 ]]; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    error_class="$(classify_failure "$rc" "$http_code" "$error_body" "$stderr_file")"
    warn "$test_name failed rc=$rc http=$http_code class=$error_class body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500) stderr=$(tr '\n' ' ' <"$stderr_file" | cut -c1-240)"
    append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "$error_class" "$http_code" "$error_class" "$error_body"
    return 0
  fi
  if ! jq -e . "$raw_file" >/dev/null 2>&1; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    warn "$test_name returned non-JSON http=$http_code body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500)"
    append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "non_json_response" "$http_code" "non_json_response" "$error_body"
    return 0
  fi
  if jq -e 'has("error")' "$raw_file" >/dev/null 2>&1; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    error_class="$(classify_failure "$rc" "$http_code" "$error_body" "$stderr_file")"
    warn "$test_name returned API error http=$http_code class=$error_class body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500)"
    append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "$error_class" "$http_code" "$error_class" "$error_body"
    return 0
  fi
  append_summary_from_json "$category" "$test_name" "$model_name" "$mode" "$conc" "$np" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "" "$http_code" "" ""
  local done_line
  done_line="$(jq -r --arg step "$step_label" --arg planned "$PLANNED_TESTS" --arg wall "$wall_s" --arg http "$http_code" '"DONE  [\($step)/\($planned)] http=" + $http + " done_reason=" + (.done_reason // "") + " prompt_tokens=" + ((.prompt_eval_count // 0)|tostring) + " eval_tokens=" + ((.eval_count // 0)|tostring) + " gen_tps=" + (if (.eval_duration // 0) > 0 then (((.eval_count / (.eval_duration/1000000000))*100|round/100)|tostring) else "n/a" end) + " ttft_any_ms=" + ((._stream_metrics.ttft_any_ms // "")|tostring) + " ttft_answer_ms=" + ((._stream_metrics.ttft_answer_ms // "")|tostring) + " wall_s=" + $wall + " response_chars=" + (((.response // "")|length)|tostring) + " thinking_chars=" + (((.thinking // "")|length)|tostring)' "$raw_file" 2>/dev/null || true)"
  [[ -n "$done_line" ]] && log "$done_line"
}

build_embed_payload_json() {
  local model_name="$1" input_json="$2"
  jq -nc --arg model "$model_name" --arg keep "$KEEP_ALIVE" --argjson input "$input_json" '{model:$model,input:$input,keep_alive:$keep}'
}

input_json_text_stats() {
  local input_json="$1"
  jq -r 'if type=="array" then map(tostring)|join(" ") else tostring end' <<<"$input_json" | awk '{chars+=length($0); words+=NF} END{printf "%d %d", chars+0, words+0}'
}

append_embedding_summary_from_json() {
  local category="$1" test_name="$2" model_name="$3" ctx="$4" raw_file="$5" payload_file="$6" wall_s="$7" prompt_chars="$8" prompt_words="$9" err_msg="${10:-}" http_code="${11:-}" error_class="${12:-}" error_body="${13:-}"
  local line
  [[ -n "$http_code" ]] || http_code=""
  [[ -n "$error_class" ]] || error_class="$err_msg"
  if [[ -n "$err_msg" ]]; then
    line="$(jq -rn --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg err "$err_msg" --arg http "$http_code" --arg cls "$error_class" --arg body "$error_body" --arg raw "$raw_file" --arg payload "$payload_file" \
      '[$ts,$cat,$test,$model,$ctx,"","EMBED","1",$wall,"0","0","embed","","","","","","","","",$pc,$pw,"",$err,$http,$cls,$body,$raw,$payload,"/api/embed","","","","","","","","","","false","ERROR","FAIL"] | @csv')"
    append_csv_line "$line"
    return 0
  fi
  line="$(jq -r --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg http "$http_code" --arg raw "$raw_file" --arg payload "$payload_file" --argjson minfill "$LONG_CONTEXT_MIN_FILL_PCT" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    def fill(tokens; ctx): if tokens == null or ctx == null or (ctx|tonumber)==0 then null else (100 * (tokens|tonumber) / (ctx|tonumber)) end;
    def vc: ((.embeddings // []) | length);
    def vd: if vc > 0 then ((.embeddings[0] // []) | length) else 0 end;
    def etps: if (.total_duration // 0) > 0 then (vc / (.total_duration/1000000000)) else null end;
    def fill_pct: (fill(.prompt_eval_count;$ctx));
    def sample_status: if $cat == "embedding_longctx" and ((fill_pct // 0) < $minfill) then "UNDERFILLED" else "OK" end;
    def result_state: if sample_status == "OK" then "PASS" else "INCONCLUSIVE" end;
    [$ts,$cat,$test,$model,$ctx,"","EMBED","1",$wall,"0","0","embed",(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),"",(tps(.prompt_eval_count;.prompt_eval_duration)//""),"",(sec(.prompt_eval_duration)//""),"",$pc,$pw,(fill_pct//""),"",$http,"","",$raw,$payload,"/api/embed",(vc|tostring),(vd|tostring),(etps//""),"","","","","","","","false",sample_status,result_state] | @csv' "$raw_file")"
  append_csv_line "$line"
}

run_embed() {
  local category="$1" test_name="$2" model_name="$3" ctx="$4" input_json="$5" step_label="${6:-?}"
  local payload_file="$PAYLOAD_DIR/$test_name.json" raw_file="$RAW_DIR/$test_name.json" stderr_file="$RAW_DIR/$test_name.stderr" http_file="$RAW_DIR/$test_name.http" rc=0 start_ns end_ns wall_s stats prompt_chars prompt_words http_code error_body error_class vectors dim
  stats="$(input_json_text_stats "$input_json")"
  prompt_chars="${stats%% *}"
  prompt_words="${stats##* }"
  build_embed_payload_json "$model_name" "$input_json" >"$payload_file"
  log "START [$step_label/$PLANNED_TESTS] $test_name: category=$category model=$model_name mode=EMBED endpoint=/api/embed ctx=$ctx input_words=$prompt_words"
  start_ns="$(date +%s%N)"
  set +e
  ollama_curl_embed "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload_file" "$raw_file" "$http_file" "$stderr_file" "$BASE_URL"
  rc=$?
  set -e
  end_ns="$(date +%s%N)"
  wall_s="$(awk -v s="$start_ns" -v e="$end_ns" 'BEGIN{printf "%.6f", (e-s)/1000000000}')"
  http_code="$(tr -dc '0-9' <"$http_file" 2>/dev/null | tail -c 3)"
  [[ -n "$http_code" ]] || http_code="000"
  if [[ "$rc" -ne 0 || ! "$http_code" =~ ^2 ]]; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    error_class="$(classify_failure "$rc" "$http_code" "$error_body" "$stderr_file")"
    warn "$test_name failed rc=$rc http=$http_code class=$error_class body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500) stderr=$(tr '\n' ' ' <"$stderr_file" | cut -c1-240)"
    append_embedding_summary_from_json "$category" "$test_name" "$model_name" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "$error_class" "$http_code" "$error_class" "$error_body"
    return 0
  fi
  if ! jq -e . "$raw_file" >/dev/null 2>&1; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    warn "$test_name returned non-JSON http=$http_code body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500)"
    append_embedding_summary_from_json "$category" "$test_name" "$model_name" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "non_json_response" "$http_code" "non_json_response" "$error_body"
    return 0
  fi
  if jq -e 'has("error")' "$raw_file" >/dev/null 2>&1; then
    error_body="$(error_body_from_raw "$raw_file" "$stderr_file")"
    error_class="$(classify_failure "$rc" "$http_code" "$error_body" "$stderr_file")"
    warn "$test_name returned API error http=$http_code class=$error_class body=$(printf '%s' "$error_body" | tr '\n' ' ' | cut -c1-500)"
    append_embedding_summary_from_json "$category" "$test_name" "$model_name" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "$error_class" "$http_code" "$error_class" "$error_body"
    return 0
  fi
  vectors="$(jq -r '(.embeddings // []) | length' "$raw_file" 2>/dev/null || echo 0)"
  dim="$(jq -r 'if ((.embeddings // []) | length) > 0 then ((.embeddings[0] // []) | length) else 0 end' "$raw_file" 2>/dev/null || echo 0)"
  if [[ "${vectors:-0}" -le 0 || "${dim:-0}" -le 0 ]]; then
    error_body="empty embedding response or vector dimension missing"
    error_class="embedding_empty_response"
    warn "$test_name embedding validation failed http=$http_code class=$error_class vectors=${vectors:-0} dim=${dim:-0}"
    append_embedding_summary_from_json "$category" "$test_name" "$model_name" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "$error_class" "$http_code" "$error_class" "$error_body"
    return 0
  fi
  append_embedding_summary_from_json "$category" "$test_name" "$model_name" "$ctx" "$raw_file" "$payload_file" "$wall_s" "$prompt_chars" "$prompt_words" "" "$http_code" "" ""
  local done_line
  done_line="$(jq -r --arg step "$step_label" --arg planned "$PLANNED_TESTS" --arg wall "$wall_s" --arg http "$http_code" '"DONE  [\($step)/\($planned)] http=" + $http + " endpoint=/api/embed vectors=" + (((.embeddings // []) | length)|tostring) + " dim=" + (if (((.embeddings // []) | length) > 0) then (((.embeddings[0] // []) | length)|tostring) else "0" end) + " prompt_tokens=" + ((.prompt_eval_count // 0)|tostring) + " wall_s=" + $wall' "$raw_file" 2>/dev/null || true)"
  [[ -n "$done_line" ]] && log "$done_line"
}

record_unsupported_generate_preflight() {
  local raw_file="$RAW_DIR/00_capability_preflight.json" payload_file="$PAYLOAD_DIR/00_capability_preflight.json" http_file="$RAW_DIR/00_capability_preflight.http" stderr_file="$RAW_DIR/00_capability_preflight.stderr" msg
  msg="model '$MODEL' is embedding-only and does not support generate; use ollama embed-test $MODEL or ollama bench $MODEL"
  jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" --arg error "$msg" '{error:$error, model:$model, role:$role, endpoint_attempted:"/api/generate", recommended_endpoint:"/api/embed", result_state:"UNSUPPORTED"}' >"$raw_file"
  jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" '{model:$model, role:$role, reason:"generation benchmark preflight refused embedding-only model"}' >"$payload_file"
  printf '200' >"$http_file"
  : >"$stderr_file"
  append_summary_from_json "preflight" "00_capability_preflight" "$MODEL" "N/A" "0" "0" "0" "$raw_file" "$payload_file" "0.000000" "0" "0" "unsupported_generate_for_embedding_model" "200" "unsupported_generate_for_embedding_model" "$msg"
}

ensure_generation_supported_or_exit() {
  if [[ "$EMBEDDING_MODE" == "1" ]]; then return 0; fi
  if ollama_model_role_is_embedding_only "$MODEL_ROLE"; then
    log "UNSUPPORTED generation benchmark: model=$MODEL role=$MODEL_ROLE does not support /api/generate"
    record_unsupported_generate_preflight
    snapshot_before_after after
    capture_dmesg_gpu_errors
    capture_ollama_server_log_tail
    make_failure_hints
    if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
    make_summary_md
    make_terminal_summary
    make_archive
    if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then print_file_plain "$TERMINAL_SUMMARY"; else log "Test collector completed; artifacts are under $RUN_DIR"; fi
    exit 2
  fi
}


make_capability_analysis() {
  [[ "$EMBEDDING_MODE" == "0" && "$TEST_PROFILE" == "ados" ]] || return 0
  {
    echo "# ADOS Capability Prompt Analysis"
    echo
    echo "Model: $MODEL"
    echo "Profile: $TEST_PROFILE"
    echo "Load mode: $LOAD_MODE"
    echo
    echo "This file records deterministic evidence checks for the three default prompts. It does not claim full model quality; it checks whether each probe produced usable output and whether the internet-access probe avoids fabricating live access."
    echo
    echo "| Probe | Output chars | Evidence verdict | Check notes |"
    echo "|---|---:|---|---|"
    local test raw response lower chars verdict notes
    for test in 01_coding_first_prompt 02_essay_second_prompt 03_internet_access_third_prompt; do
      raw="$RAW_DIR/$test.json"
      response="$(jq -r '(.response // "")' "$raw" 2>/dev/null || true)"
      chars="${#response}"
      lower="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
      verdict="NEEDS_REVIEW"
      notes="response present"
      if [[ "$test" == "01_coding_first_prompt" ]]; then
        if [[ "$chars" -gt 0 && "$lower" == *"top_k"* ]]; then verdict="PASS"; notes="coding response references requested function"; fi
      elif [[ "$test" == "02_essay_second_prompt" ]]; then
        if [[ "$chars" -gt 0 ]]; then verdict="PASS"; notes="essay response produced visible prose"; fi
      elif [[ "$test" == "03_internet_access_third_prompt" ]]; then
        if printf '%s' "$lower" | grep -Eq "cannot|can't|do not have|don't have|no live|no browser|without (live |external )?internet|not able to access"; then
          verdict="PASS"; notes="internet-access response denies live browsing/runtime internet access"
        elif [[ "$chars" -gt 0 ]]; then
          verdict="NEEDS_REVIEW"; notes="internet-access response produced output but did not clearly deny live access"
        else
          verdict="FAIL"; notes="no visible response"
        fi
      fi
      printf '| `%s` | %s | %s | %s |\n' "$test" "$chars" "$verdict" "$notes"
    done
  } >"$CAPABILITY_ANALYSIS"
}

run_embedding_suite() {
  local sanity_input batch_input long_input rag_input
  sanity_input="$(jq -Rn --arg s "RTX 3090 embedding test for RAG retrieval." '$s')"
  batch_input="$(jq -nc '[range(0;32) | "RTX 3090 Ollama embedding batch chunk " + tostring + ": local RAG retrieval, code search, WSL2 CUDA telemetry, prompt ingestion, and vector indexing baseline."]')"
  long_input="$(make_long_prompt "$LONG_PROMPT_WORDS" | jq -Rs .)"
  rag_input="$(jq -nc '[
    "Repository README chunk: ollama-info validates local RTX 3090 Ollama generation, embedding, telemetry, and package evidence.",
    "Code chunk: run_generate records TTFT, prompt_eval_count, eval_count, visible answer length, and sample status for ranking.",
    "Documentation chunk: embedding models must use /api/embed and report vector count, vector dimension, tokens per second, and embeddings per second.",
    "Issue chunk: cold load is named FirstReqLoad unless model absence is verified before the first request.",
    "Operations chunk: PCIe Gen3 x8 is a warning for load/offload/concurrency, not automatic resident decode failure.",
    "Agentic workflow chunk: concurrency 1, 2, and 4 should be inspected for p50/p95 latency and throughput collapse."
  ]')"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_sanity" "01_embed_sanity" "$MODEL" "$NUM_CTX" "$sanity_input" "$TEST_STEP"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_batch" "02_embed_batch" "$MODEL" "$NUM_CTX" "$batch_input" "$TEST_STEP"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_longctx" "03_embed_longctx" "$MODEL" "$LONG_CTX" "$long_input" "$TEST_STEP"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_rag_profile" "04_embed_rag_profile" "$MODEL" "$NUM_CTX" "$rag_input" "$TEST_STEP"
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
    echo "- model_role: $MODEL_ROLE"
    echo "- mode: $([[ "$EMBEDDING_MODE" == "1" ]] && echo embedding || echo generation)"
    echo "- base_url: $BASE_URL"
    echo "- think: $THINK"
    echo "- stream_generation: $STREAM_GENERATION"
    echo "- test_profile: $TEST_PROFILE"
    echo "- load_mode: $LOAD_MODE"
    echo "- cold_verified: $COLD_VERIFIED"
    echo "- run_dir: $RUN_DIR"
    echo "- archive: ${ARCHIVE_PATH:-pending}"; echo
    echo "## Load-state semantics"; echo '```text'; cat "$LOAD_STATE_FILE" 2>/dev/null || true; echo '```'; echo
    if [[ -s "$CAPABILITY_ANALYSIS" ]]; then echo "## Capability analysis"; echo; cat "$CAPABILITY_ANALYSIS"; echo; fi
    local processor_after residency_state
    processor_after="$(model_processor_after)"
    residency_state="$(processor_residency_state "$processor_after")"
    echo "## Residency/offload classification"; echo
    echo "- processor_after: ${processor_after:-unknown}"
    echo "- residency_state: $residency_state"
    if [[ "$residency_state" == "cpu_gpu_offload" || "$residency_state" == "cpu_only_or_cpu_heavy" || "$residency_state" == "non_full_gpu" ]]; then
      echo "- warning: CPU/offload or non-full-GPU residency detected; decode/load numbers are not a clean full-GPU-resident benchmark."
    elif [[ "$residency_state" == "full_gpu" ]]; then
      echo "- warning: none; tested model is reported as 100% GPU resident after the run."
    else
      echo "- warning: residency unknown; inspect ollama-ps-after.txt."
    fi
    echo
    echo "## Classified metrics"; echo
    awk -F',' -v minfill="$LONG_CONTEXT_MIN_FILL_PCT" -v cold="$COLD_VERIFIED" -v loadver="$LOAD_STATE_VERDICT" -v resident="$MODEL_RESIDENT_BEFORE" '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {
        rows++; cat=col("category"); mode=col("mode"); endpoint=col("endpoint"); conc=col("concurrency"); err=col("error"); state=col("result_state"); sample=col("sample_status"); gen=col("decode_tps_raw")+0; vis=col("visible_answer_tps")+0; load=col("load_s")+0; total=col("total_s")+0; resp=col("response_chars")+0; think=col("thinking_chars")+0; pe=col("prompt_eval_tokens")+0; eval=col("eval_tokens")+0; ctx=col("num_ctx")+0; fill=col("context_fill_pct")+0; vc=col("vector_count")+0; vd=col("vector_dim")+0; etps=col("embedding_tps")+0; ttfa=col("ttft_any_ms")+0; ttfans=col("ttft_answer_ms")+0; e2e500=col("end_to_end_500_ms")+0;
        if(state=="UNSUPPORTED") unsupported++;
        if(err!="" && state!="UNSUPPORTED") errors++;
        if(sample=="SHORT_SAMPLE") short_samples++;
        if(sample=="UNDERFILLED") underfilled++;
        if(endpoint=="/api/embed" || mode=="EMBED" || cat ~ /^embedding/) {embed_rows++; embed_vectors+=vc; if(vd>0) embed_dim=vd; if(err=="") embed_ok++; if(etps>0){embed_tps_n++; embed_tps_sum+=etps}; if(cat=="embedding_longctx"){elong_seen=1; elong_fill=fill; elong_pe=pe; elong_ctx=ctx; elong_sample=sample}}
        else {gen_rows++; if(resp>0) visible++; if(resp==0&&think>0) thinkonly++; if(cat=="sanity" && load>first_load) first_load=load; if(cat=="sanity"||cat=="coding"){first_ttfa=ttfa; first_ttfans=ttfans}; iswarm=(cat=="throughput"||cat=="sustained"||cat=="coding"||cat=="essay"||cat=="internet_access"); if(mode=="GPU"&&conc==1&&err==""&&iswarm&&sample=="OK"&&vis>0){warmn++; warmsum+=vis; if(cat!="coding"&&ttfa>0){warm_ttfa_n++; warm_ttfa_sum+=ttfa}; if(cat!="coding"&&ttfans>0){warm_ttfans_n++; warm_ttfans_sum+=ttfans}}; if(cat=="longctx"){long_seen=1; longgen=gen; longvis=vis; longpe=pe; longctx=ctx; longfill=fill; longsample=sample; long_ttfa=ttfa; long_ttfans=ttfans}; if(ttfa>0){ttfa_n++; ttfa_sum+=ttfa}; if(ttfans>0){ttfans_n++; ttfans_sum+=ttfans}; if(e2e500>0){e2e_n++; e2e_sum+=e2e500}}
      }
      END{
        printf "- status_basis: rows=%d errors=%d unsupported=%d short_samples=%d underfilled=%d visible_rows=%d thinking_only=%d embedding_rows=%d\n", rows, errors, unsupported, short_samples, underfilled, visible, thinkonly, embed_rows;
        if(unsupported>0){print "- result_state: UNSUPPORTED generation benchmark for selected model role"}
        else if(errors>0){print "- result_state: FAIL"}
        else if(short_samples>0 || underfilled>0){print "- result_state: PASS_WITH_WARNINGS"}
        else {print "- result_state: PASS"}
        if(embed_rows>0 && gen_rows==0){ if(embed_tps_n>0) printf "- embedding: vectors=%d dim=%d rows_ok=%d avg_embeddings_per_s=%.2f\n", embed_vectors, embed_dim, embed_ok, embed_tps_sum/embed_tps_n; else printf "- embedding: vectors=%d dim=%d rows_ok=%d\n", embed_vectors, embed_dim, embed_ok; if(elong_seen) printf "- embedding_long_context: prompt_eval_tokens=%d ctx=%d fill=%.1f%% sample_status=%s\n", elong_pe, elong_ctx, elong_fill, elong_sample; }
        else { if(warmn>0) printf "- warm_visible_answer_tps_avg: %.2f across %d OK rows\n", warmsum/warmn, warmn; else print "- warm_visible_answer_tps_avg: N/A; no OK visible-answer warm rows"; printf "- first_request_load_s: %.2f\n", first_load; printf "- load_state_verdict: %s\n", loadver; printf "- model_resident_before: %s\n", resident; printf "- cold_verified: %s\n", cold; if(first_ttfa>0) printf "- first_request_ttft_any_ms: %.1f\n", first_ttfa; if(first_ttfans>0) printf "- first_request_ttft_answer_ms: %.1f\n", first_ttfans; if(warm_ttfa_n>0) printf "- warm_ttft_any_ms_avg: %.1f across %d OK throughput/sustained rows\n", warm_ttfa_sum/warm_ttfa_n, warm_ttfa_n; if(warm_ttfans_n>0) printf "- warm_ttft_answer_ms_avg: %.1f across %d OK throughput/sustained rows\n", warm_ttfans_sum/warm_ttfans_n, warm_ttfans_n; if(ttfa_n>0) printf "- ttft_any_ms_avg_all_rows: %.1f\n", ttfa_sum/ttfa_n; if(ttfans_n>0) printf "- ttft_answer_ms_avg_all_rows: %.1f\n", ttfans_sum/ttfans_n; if(e2e_n>0) printf "- end_to_end_500_ms_est_avg: %.1f\n", e2e_sum/e2e_n; if(long_seen) printf "- long_context: prompt_eval_tokens=%d ctx=%d fill=%.1f%% decode_tps_raw=%.2f visible_answer_tps=%.2f sample_status=%s ttft_any_ms=%.1f ttft_answer_ms=%.1f\n", longpe, longctx, longfill, longgen, longvis, longsample, long_ttfa, long_ttfans; }
      }' "$SUMMARY_CSV"
    if [[ -s "$CONC_AGG_CSV" ]]; then echo; echo "## Concurrency aggregate"; echo '```csv'; cat "$CONC_AGG_CSV"; echo '```'; fi
    if [[ -s "$SOAK_SUMMARY_CSV" ]]; then echo; echo "## Soak aggregate"; echo '```csv'; cat "$SOAK_SUMMARY_CSV"; echo '```'; fi
    if [[ -s "$FAILURE_HINTS" ]]; then echo; echo "## Failure hints"; echo '```text'; cat "$FAILURE_HINTS"; echo '```'; fi
    echo; echo "## Preflight diagnostics"; echo
    echo "- API version: $API_VERSION_FILE"
    echo "- API tags: $API_TAGS_FILE"
    echo "- API show model: $API_SHOW_FILE"
    echo "- load state: $LOAD_STATE_FILE"
    echo "- ollama show/list: $OLLAMA_SHOW_FILE"
    echo "- WSL diagnostics: $WSL_DIAG"
    echo "- Ollama server log tail: $SERVER_LOG_TAIL"
    echo; echo "## Test results"; echo
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {test=col("test"); cat=col("category"); endpoint=col("endpoint"); state=col("result_state"); sample=col("sample_status"); ctx=col("num_ctx"); np=col("num_predict"); prompt=col("prompt_eval_tokens"); fill=col("context_fill_pct"); eval=col("eval_tokens"); raw=col("decode_tps_raw"); vis=col("visible_answer_tps"); any=col("ttft_any_ms"); ans=col("ttft_answer_ms"); vec=col("vector_count"); dim=col("vector_dim"); http=col("http_code"); cls=col("error_class"); if(NR==2){print "| Test | Category | Endpoint | State | Sample | Ctx | Predict | Prompt tok | Fill % | Eval tok | Decode tok/s | Visible tok/s | TTFT any ms | TTFT answer ms | Vectors | Dim | HTTP | Class |"; print "|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|"}; if(raw!="") raw=sprintf("%.2f", raw); if(vis!="") vis=sprintf("%.2f", vis); if(fill!="") fill=sprintf("%.1f", fill); printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", test, cat, endpoint, state, sample, ctx, np, prompt, fill, eval, raw, vis, any, ans, vec, dim, http, cls}
    ' "$SUMMARY_CSV"
    echo; echo "## Ollama loaded models after test"; echo '```text'; cat "$RUN_DIR/ollama-ps-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## NVIDIA snapshot after test"; echo '```text'; cat "$RUN_DIR/nvidia-smi-after.txt" 2>/dev/null || true; echo '```'
    echo; echo "## dmesg GPU/error scan"; echo '```text'; cat "$RUN_DIR/dmesg-gpu-errors.txt" 2>/dev/null || true; echo '```'
    echo; echo "## Files"; echo "- terminal summary: $TERMINAL_SUMMARY"; echo "- CSV: $SUMMARY_CSV"; echo "- concurrency aggregate CSV: $CONC_AGG_CSV"; echo "- soak summary CSV: $SOAK_SUMMARY_CSV"; echo "- failure hints: $FAILURE_HINTS"; echo "- Ollama server log tail: $SERVER_LOG_TAIL"; echo "- WSL diagnostics: $WSL_DIAG"; echo "- raw JSON: $RAW_DIR"; echo "- payload JSON: $PAYLOAD_DIR"; echo "- meta: $META"
  } >"$SUMMARY_MD"
}

make_terminal_summary() {
  {
    echo "============================================================"
    echo "RTX3090 OLLAMA TEST SUMMARY"
    echo "Run ID  : $RUN_ID"
    echo "Model   : $MODEL"
    echo "Role    : $MODEL_ROLE"
    echo "Mode    : $([[ "$EMBEDDING_MODE" == "1" ]] && echo embedding || echo generation)"
    echo "API     : $BASE_URL"
    echo "Think   : $THINK"
    echo "Stream  : $STREAM_GENERATION"
    awk -F',' -v minfill="$LONG_CONTEXT_MIN_FILL_PCT" -v cold="$COLD_VERIFIED" -v loadver="$LOAD_STATE_VERDICT" -v resident="$MODEL_RESIDENT_BEFORE" '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {
        rows++; cat=col("category"); mode=col("mode"); endpoint=col("endpoint"); conc=col("concurrency"); err=col("error"); cls=col("error_class"); state=col("result_state"); sample=col("sample_status"); gen=col("decode_tps_raw")+0; vis=col("visible_answer_tps")+0; total=col("total_s")+0; load=col("load_s")+0; resp=col("response_chars")+0; think=col("thinking_chars")+0; pe=col("prompt_eval_tokens")+0; eval=col("eval_tokens")+0; ctx=col("num_ctx")+0; fill=col("context_fill_pct")+0; vc=col("vector_count")+0; vd=col("vector_dim")+0; etps=col("embedding_tps")+0; any=col("ttft_any_ms")+0; ans=col("ttft_answer_ms")+0; e2e=col("end_to_end_500_ms")+0;
        if(state=="UNSUPPORTED") unsupported++;
        if(err!="" && state!="UNSUPPORTED") errors++;
        if(sample=="SHORT_SAMPLE") short_samples++;
        if(sample=="UNDERFILLED") underfilled++;
        if(endpoint=="/api/embed" || mode=="EMBED" || cat ~ /^embedding/) {embed_rows++; embed_vectors+=vc; if(vd>0) embed_dim=vd; if(err=="") embed_ok++; if(etps>0){embed_tps_n++; embed_tps_sum+=etps}; if(cat=="embedding_longctx"){elong_seen=1; elong_fill=fill; elong_pe=pe; elong_ctx=ctx; elong_sample=sample}}
        else {gen_rows++; if(resp>0) visible++; if(resp==0&&think>0) think_only++; if(cat=="sanity" && load>first_load) first_load=load; if(cat=="sanity"||cat=="coding"){first_any=any; first_ans=ans}; iswarm=(cat=="throughput"||cat=="sustained"||cat=="coding"||cat=="essay"||cat=="internet_access"); if(mode=="GPU"&&conc==1&&err==""&&iswarm&&sample=="OK"&&vis>0){warm_n++; warm_sum+=vis; if(warm_n==1||vis>warm_max)warm_max=vis; if(warm_n==1||vis<warm_min)warm_min=vis; if(cat!="coding"&&any>0){warm_any_n++; warm_any_sum+=any}; if(cat!="coding"&&ans>0){warm_ans_n++; warm_ans_sum+=ans}}; if(cat=="longctx"){long_seen=1; long_gen=gen; long_vis=vis; long_fill=fill; long_pe=pe; long_ctx=ctx; long_sample=sample; long_any=any; long_ans=ans}; if(any>0){any_n++; any_sum+=any}; if(ans>0){ans_n++; ans_sum+=ans}; if(e2e>0){e2e_n++; e2e_sum+=e2e}}
        if(total>max_total)max_total=total
      }
      END{
        if(unsupported>0) status="UNSUPPORTED"; else if(errors>0) status="FAIL"; else if(short_samples>0||underfilled>0) status="PASS_WITH_WARNINGS"; else status="PASS";
        printf "Status  : %s\n", status;
        if(embed_rows>0 && gen_rows==0){
          if(embed_tps_n>0) printf "Embed   : vectors=%d dim=%d rows=%d ok=%d avg=%.2f embeds/s\n", embed_vectors, embed_dim, embed_rows, embed_ok, embed_tps_sum/embed_tps_n; else printf "Embed   : vectors=%d dim=%d rows=%d ok=%d\n", embed_vectors, embed_dim, embed_rows, embed_ok;
          if(elong_seen) printf "LongEmb : prompt_tokens=%d ctx=%d fill=%.1f%% %s\n", elong_pe, elong_ctx, elong_fill, elong_sample; else print "LongEmb : N/A; embedding long-context row not run";
          printf "Output  : embedding rows %d/%d; errors %d\n", embed_ok, embed_rows, errors;
          if(errors==0) print "Inference: PASS; completed embedding benchmark"; else print "Inference: INCONCLUSIVE; embedding benchmark did not complete cleanly";
        } else if(unsupported>0) {
          print "Inference: UNSUPPORTED; selected model role does not support /api/generate";
        } else {
          if(warm_n>0) printf "Warm    : visible-answer %.2f tok/s avg (%.2f-%.2f), OK rows %d\n", warm_sum/warm_n, warm_min, warm_max, warm_n; else print "Warm    : no OK visible-answer warm rows";
          printf "FirstReqLoad: %.2fs; LoadState=%s; ColdVerified=%s; max total %.2fs\n", first_load, loadver, cold, max_total;
          if(first_any>0) printf "FirstTTFT: any %.1f ms; answer %s\n", first_any, (first_ans>0?sprintf("%.1f ms", first_ans):"N/A");
          if(warm_any_n>0 || warm_ans_n>0) printf "WarmTTFT: any %s; answer %s\n", (warm_any_n>0?sprintf("%.1f ms avg", warm_any_sum/warm_any_n):"N/A"), (warm_ans_n>0?sprintf("%.1f ms avg", warm_ans_sum/warm_ans_n):"N/A");
          if(any_n>0) printf "TTFTall : any %.1f ms avg; answer %s\n", any_sum/any_n, (ans_n>0?sprintf("%.1f ms avg", ans_sum/ans_n):"N/A"); else print "TTFT    : N/A; streaming metrics unavailable";
          if(e2e_n>0) printf "E2E500  : %.1f ms estimated avg\n", e2e_sum/e2e_n;
          if(long_seen) printf "LongCtx : prompt_tokens=%d ctx=%d fill=%.1f%% decode=%.2f visible=%.2f ttft=%.1f/%.1f %s\n", long_pe, long_ctx, long_fill, long_gen, long_vis, long_any, long_ans, long_sample; else print "LongCtx : N/A; long-context row not run";
          printf "Output  : visible rows %d/%d; thinking-only %d; errors %d; short=%d underfilled=%d\n", visible, rows, think_only, errors, short_samples, underfilled;
          if(errors==0 && visible>0) print "Inference: PASS; completed generation benchmark"; else print "Inference: NOT TESTED; model did not produce usable generation tokens";
        }
      }' "$SUMMARY_CSV"
    local processor_after residency_state
    processor_after="$(model_processor_after)"
    residency_state="$(processor_residency_state "$processor_after")"
    if [[ "$residency_state" == "full_gpu" ]]; then
      echo "Residency: full GPU ($processor_after)"
    elif [[ "$residency_state" == "unknown" ]]; then
      echo "Residency: unknown; inspect ollama-ps-after.txt"
    else
      echo "Residency: WARN $residency_state ($processor_after); not a clean full-GPU-resident benchmark"
    fi
    if [[ "${OTHER_MODELS_RESIDENT_BEFORE:-0}" == "1" ]]; then
      echo "LoadWarn : other model(s) resident before benchmark: ${RESIDENT_MODELS_BEFORE:-unknown}; FirstReqLoad includes model-switch/eviction effects"
    fi
    if [[ "$LOAD_MODE" == "empty-card" ]]; then
      echo "EmptyCard: requested=$EMPTY_CARD_REQUESTED verified=$EMPTY_CARD_VERIFIED; default prevents dependence on a previously loaded Ollama model when unload verification succeeds"
    fi
    if [[ "$LOAD_MODE" == "observed" && "$COLD_VERIFIED" != "1" ]]; then
      echo "LoadNote : observed mode does not claim verified-cold load; use --load-mode empty-card, unload-model, or restart-ollama for verification"
    fi
    if [[ -s "$FAILURE_HINTS" ]] && ! grep -q '^primary_error_class=none$' "$FAILURE_HINTS"; then
      awk -F= '/^(primary_error_class|api_error_rows|first_api_error|likely_cause|next_action)=/{v=$0; if(length(v)>160)v=substr(v,1,157)"..."; sub(/^primary_error_class=/,"Error   : class=",v); sub(/^api_error_rows=/,"Errors  : API rows=",v); sub(/^first_api_error=/,"API err : ",v); sub(/^likely_cause=/,"Likely  : ",v); sub(/^next_action=/,"Next    : ",v); print v}' "$FAILURE_HINTS" | head -5
    fi
    if [[ -s "$CONC_AGG_CSV" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Conc    : x%s aggregate %.2f tok/s over %.2fs; ok=%s err=%s\n", unq($2), unq($6)+0, unq($3)+0, unq($7), unq($8)}' "$CONC_AGG_CSV"
    fi
    if [[ -s "$SOAK_SUMMARY_CSV" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Soak    : iterations=%s aggregate %.2f tok/s over %.1fs; errors=%s\n", unq($2), unq($5)+0, unq($3)+0, unq($6)}' "$SOAK_SUMMARY_CSV"
    fi
    echo "Tests:"
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      NR<=13{test=col("test"); cat=col("category"); mode=col("mode"); ctx=col("num_ctx"); raw=col("decode_tps_raw"); vis=col("visible_answer_tps"); prompt=col("prompt_eval_tokens"); sample=col("sample_status"); state=col("result_state"); cls=col("error_class"); http=col("http_code"); vec=col("vector_count"); dim=col("vector_dim"); any=col("ttft_any_ms"); ans=col("ttft_answer_ms"); if(raw!="") raw=sprintf("%.2f", raw); if(vis!="") vis=sprintf("%.2f", vis); suffix=(cls!=""?"http="http" "cls:state"/"sample); if(mode=="EMBED"||cat~/^embedding/) printf "  %-18s %-18s ctx=%-5s prompt=%-5s vec=%-4s dim=%-5s %s\n", test, cat, ctx, prompt, vec, dim, suffix; else printf "  %-18s %-10s ctx=%-5s prompt=%-5s raw=%6s vis=%6s ttft=%s/%s %s\n", test, cat, ctx, prompt, raw, vis, any, ans, suffix}
      NR==14{print "  ... additional rows omitted from terminal summary; see summary.csv"}' "$SUMMARY_CSV"
    echo "Files:"; echo "  run : $RUN_DIR"; echo "  md  : $SUMMARY_MD"; echo "  csv : $SUMMARY_CSV"; echo "  load: $LOAD_STATE_FILE"; if [[ -s "$CAPABILITY_ANALYSIS" ]]; then echo "  cap : $CAPABILITY_ANALYSIS"; fi; echo "  hint: $FAILURE_HINTS"; echo "  log : $SERVER_LOG_TAIL"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then echo "  zip : $ARCHIVE_PATH"; fi
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
if [[ "$NO_MODEL_ARGS" == "1" ]]; then
  show_no_args_screen
  exit 2
fi
ensure_server
select_or_explain_model "$MODEL"
ensure_model "$MODEL"
if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then ensure_model "${VRAM_MODEL:-$MODEL}"; fi
collect_preflight_diagnostics
snapshot_before_after before
assess_load_state
write_meta
capture_dmesg_cursor
ensure_generation_supported_or_exit

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
coding_prompt="$(with_prefix "Coding capability probe. Write Python 3.11 code for function top_k_frequent(items: list[str], k: int) -> list[str]. Return the k most frequent strings. Sort ties alphabetically. Include concise pytest tests for normal, tie, and empty-input cases. Do not claim execution; provide code only plus short usage notes.")"
essay_prompt="$(with_prefix "Essay capability probe. Write a concise structured essay for a technical reader. Thesis: local-first LLM runtimes should separate capability tests from performance benchmarks. Use a title, thesis paragraph, three body sections, and a short conclusion. Avoid hidden reasoning.")"
internet_prompt="$(with_prefix "Internet access capability probe. You are running as a local Ollama model in this benchmark. State whether you can access live internet or browse current web pages from this runtime. Do not invent current facts. Explain how a user should verify current information if live browsing/tool access is not explicitly provided.")"

if [[ "$EMBEDDING_MODE" == "1" ]]; then
  PLANNED_TESTS=4
else
  if [[ "$TEST_PROFILE" == "ados" ]]; then
    PLANNED_TESTS=3
  else
    PLANNED_TESTS=4
  fi
  if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then PLANNED_TESTS=$((PLANNED_TESTS + CONCURRENCY)); fi
  if [[ "$RUN_CPU" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
  if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
fi
TEST_STEP=0
log "Test plan: model=$MODEL role=$MODEL_ROLE profile=$TEST_PROFILE embedding=$EMBEDDING_MODE think=$THINK stream=$STREAM_GENERATION load_mode=$LOAD_MODE empty_card=$EMPTY_CARD_REQUESTED/$EMPTY_CARD_VERIFIED cold_verified=$COLD_VERIFIED tests=$PLANNED_TESTS ctx=$NUM_CTX long_ctx=$LONG_CTX long_prompt_words=$LONG_PROMPT_WORDS predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU soak_minutes=$SOAK_MINUTES run_vram_pressure=$RUN_VRAM_PRESSURE"

if [[ "$EMBEDDING_MODE" == "1" ]]; then
  run_embedding_suite
else
  if [[ "$TEST_PROFILE" == "ados" ]]; then
    TEST_STEP=$((TEST_STEP + 1)); run_generate "coding" "01_coding_first_prompt" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$coding_prompt" "$TEST_STEP"
    TEST_STEP=$((TEST_STEP + 1)); run_generate "essay" "02_essay_second_prompt" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$essay_prompt" "$TEST_STEP"
    TEST_STEP=$((TEST_STEP + 1)); run_generate "internet_access" "03_internet_access_third_prompt" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$internet_prompt" "$TEST_STEP"
  else
    TEST_STEP=$((TEST_STEP + 1)); run_generate "sanity" "01_sanity_gpu" "$MODEL" "GPU" "1" 128 "$NUM_CTX" "$sanity_prompt" "$TEST_STEP"
    TEST_STEP=$((TEST_STEP + 1)); run_generate "throughput" "02_throughput_gpu" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$NUM_CTX" "$base_prompt" "$TEST_STEP"
    TEST_STEP=$((TEST_STEP + 1)); run_generate "sustained" "03_sustained_gpu" "$MODEL" "GPU" "1" "$LONG_NUM_PREDICT" "$NUM_CTX" "$sustained_prompt" "$TEST_STEP"
    TEST_STEP=$((TEST_STEP + 1)); run_generate "longctx" "04_longctx_gpu" "$MODEL" "GPU" "1" "$NUM_PREDICT" "$LONG_CTX" "$long_prompt" "$TEST_STEP"
  fi

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
fi
snapshot_before_after after
capture_dmesg_gpu_errors
capture_ollama_server_log_tail
make_failure_hints
make_capability_analysis
if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
make_summary_md
if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then
  make_terminal_summary
else
  rm -f "$TERMINAL_SUMMARY" 2>/dev/null || true
fi
make_archive

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then print_file_plain "$TERMINAL_SUMMARY"; else log "Test collector completed; artifacts are under $RUN_DIR"; fi
ERROR_COUNT="$(awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s} NR==1{for(i=1;i<=NF;i++)h[unq($i)]=i; next} {if(unq($(h["error"]))!="")e++} END{print e+0}' "$SUMMARY_CSV")"
if [[ "$ERROR_COUNT" -gt 0 ]]; then exit 1; fi
