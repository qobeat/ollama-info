#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.6.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_RTX3090_SCRIPT_SIGNATURE=v1.6.0-capability-aware-embed-mode"

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
LONG_CONTEXT_MIN_FILL_PCT="${LONG_CONTEXT_MIN_FILL_PCT:-35}"
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
Defaults: ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT concurrency=$CONCURRENCY think=$THINK embedding=$EMBEDDING_MODE
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

for n in NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT LONG_PROMPT_WORDS TIMEOUT_SEC CONNECT_TIMEOUT_SEC CONCURRENCY SOAK_MINUTES SOAK_NUM_PREDICT VRAM_CTX VRAM_NUM_PREDICT SERVER_LOG_LINES; do
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
FAILURE_HINTS="$RUN_DIR/failure-hints.txt"
SERVER_LOG_TAIL="$RUN_DIR/ollama-server-log-tail.txt"
WSL_DIAG="$RUN_DIR/wsl-diagnostics.txt"
API_VERSION_FILE="$RUN_DIR/ollama-api-version.json"
API_TAGS_FILE="$RUN_DIR/ollama-api-tags.json"
API_SHOW_FILE="$RUN_DIR/ollama-api-show-model.json"
API_SHOW_RAW_FILE="$RUN_DIR/ollama-api-show-model-raw.json"
API_SHOW_FULL_FILE="$RUN_DIR/ollama-api-show-model-full.json"
MODEL_CAPABILITY_FILE="$RUN_DIR/model-capability.json"
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
    nvidia-smi -q -d POWER,TEMPERATURE,CLOCK,PERFORMANCE,PCI,MEMORY,UTILIZATION >"$RUN_DIR/nvidia-smi-q-$label.txt" 2>&1 || true
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
  local first_body="" first_class="" body class f count=0 blob model_gib free_gib
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
    raw_response_is_error "$f" "${f%.json}.http" || continue
    body="$(error_body_from_raw "$f" "${f%.json}.stderr")"
    [[ -n "$body" ]] || body="http=$(cat "${f%.json}.http" 2>/dev/null || printf 000) raw=$(head -c 500 "$f" 2>/dev/null | tr '\n' ' ')"
    local_http="$(tr -dc '0-9' <"${f%.json}.http" 2>/dev/null | tail -c 3)"; [[ -n "$local_http" ]] || local_http=000
    class="$(classify_failure 0 "$local_http" "$body" "${f%.json}.stderr")"
    if [[ -z "$first_body" ]]; then first_body="$body"; first_class="$class"; fi
    count=$((count + 1))
  done
  shopt -u nullglob
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
        echo "next_action=use a generation model with ollama test, or run embedding mode with: ollama embed-test ${MODEL%%:*}"
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
' 'timestamp,category,test,model,num_ctx,num_predict,mode,concurrency,request_wall_s,response_chars,thinking_chars,done_reason,total_s,load_s,prompt_eval_tokens,eval_tokens,prompt_tps,gen_tps,prompt_eval_s,eval_s,prompt_chars,prompt_words,context_fill_pct,error,http_code,error_class,error_body,raw_json,payload_json,endpoint,vector_count,vector_dim,embedding_tps' >"$SUMMARY_CSV"
  printf '%s
' 'timestamp,concurrency,wall_s,total_eval_tokens,total_response_chars,aggregate_gen_tps,requests_ok,requests_error,raw_glob' >"$CONC_AGG_CSV"
  printf '%s
' 'timestamp,iterations,wall_s,total_eval_tokens,aggregate_gen_tps,errors' >"$SOAK_SUMMARY_CSV"
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
    line="$(jq -rn --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg err "$err_msg" --arg http "$http_code" --arg cls "$error_class" --arg body "$error_body" --arg raw "$raw_file" --arg payload "$payload_file" \
      '[$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,"","","","","","","","","","","",$pc,$pw,"",$err,$http,$cls,$body,$raw,$payload,"/api/generate","","",""] | @csv')"
    append_csv_line "$line"
    return 0
  fi
  line="$(jq -r --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg np "$np" --arg mode "$mode" --arg conc "$conc" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg http "$http_code" --arg raw "$raw_file" --arg payload "$payload_file" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    def fill(tokens; ctx): if tokens == null or ctx == null or (ctx|tonumber)==0 then null else (100 * (tokens|tonumber) / (ctx|tonumber)) end;
    [$ts,$cat,$test,$model,$ctx,$np,$mode,$conc,$wall,((.response // "")|length),((.thinking // "")|length),(.done_reason // ""),(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),(.eval_count//""),(tps(.prompt_eval_count;.prompt_eval_duration)//""),(tps(.eval_count;.eval_duration)//""),(sec(.prompt_eval_duration)//""),(sec(.eval_duration)//""),$pc,$pw,(fill(.prompt_eval_count;$ctx)//""),"",$http,"","",$raw,$payload,"/api/generate","","",""] | @csv' "$raw_file")"
  append_csv_line "$line"
}

run_generate() {
  local category="$1" test_name="$2" model_name="$3" mode="$4" conc="$5" np="$6" ctx="$7" prompt="$8" step_label="${9:-?}"
  local payload_file="$PAYLOAD_DIR/$test_name.json" raw_file="$RAW_DIR/$test_name.json" stderr_file="$RAW_DIR/$test_name.stderr" http_file="$RAW_DIR/$test_name.http" rc=0 start_ns end_ns wall_s prompt_chars prompt_words http_code error_body error_class
  prompt_chars="${#prompt}"
  prompt_words="$(prompt_word_count "$prompt")"
  build_payload "$model_name" "$prompt" "$np" "$ctx" "$mode" >"$payload_file"
  log "START [$step_label/$PLANNED_TESTS] $test_name: category=$category model=$model_name mode=$mode ctx=$ctx predict=$np conc=$conc prompt_words=$prompt_words"
  start_ns="$(date +%s%N)"
  set +e
  ollama_curl_generate "$TIMEOUT_SEC" "$CONNECT_TIMEOUT_SEC" "$payload_file" "$raw_file" "$http_file" "$stderr_file" "$BASE_URL"
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
  done_line="$(jq -r --arg step "$step_label" --arg planned "$PLANNED_TESTS" --arg wall "$wall_s" --arg http "$http_code" '"DONE  [\($step)/\($planned)] http=" + $http + " done_reason=" + (.done_reason // "") + " prompt_tokens=" + ((.prompt_eval_count // 0)|tostring) + " eval_tokens=" + ((.eval_count // 0)|tostring) + " gen_tps=" + (if (.eval_duration // 0) > 0 then (((.eval_count / (.eval_duration/1000000000))*100|round/100)|tostring) else "n/a" end) + " wall_s=" + $wall + " response_chars=" + (((.response // "")|length)|tostring) + " thinking_chars=" + (((.thinking // "")|length)|tostring)' "$raw_file" 2>/dev/null || true)"
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
      '[$ts,$cat,$test,$model,$ctx,"","EMBED","1",$wall,"0","0","embed","","","","","","","","",$pc,$pw,"",$err,$http,$cls,$body,$raw,$payload,"/api/embed","","",""] | @csv')"
    append_csv_line "$line"
    return 0
  fi
  line="$(jq -r --arg ts "$(date -Is)" --arg cat "$category" --arg test "$test_name" --arg model "$model_name" --arg ctx "$ctx" --arg wall "$wall_s" --arg pc "$prompt_chars" --arg pw "$prompt_words" --arg http "$http_code" --arg raw "$raw_file" --arg payload "$payload_file" '
    def sec(ns): if ns == null then null else (ns / 1000000000) end;
    def tps(tokens; ns): if tokens == null or ns == null or ns == 0 then null else (tokens / (ns / 1000000000)) end;
    def fill(tokens; ctx): if tokens == null or ctx == null or (ctx|tonumber)==0 then null else (100 * (tokens|tonumber) / (ctx|tonumber)) end;
    def vc: ((.embeddings // []) | length);
    def vd: if vc > 0 then ((.embeddings[0] // []) | length) else 0 end;
    def etps: if (.total_duration // 0) > 0 then (vc / (.total_duration/1000000000)) else null end;
    [$ts,$cat,$test,$model,$ctx,"","EMBED","1",$wall,"0","0","embed",(sec(.total_duration)//""),(sec(.load_duration)//""),(.prompt_eval_count//""),"",(tps(.prompt_eval_count;.prompt_eval_duration)//""),"",(sec(.prompt_eval_duration)//""),"",$pc,$pw,(fill(.prompt_eval_count;$ctx)//""),"",$http,"","",$raw,$payload,"/api/embed",(vc|tostring),(vd|tostring),(etps//"")] | @csv' "$raw_file")"
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
  msg="model '$MODEL' is embedding-only and does not support generate; use ollama embed-test ${MODEL%%:*} or choose a generation model for ollama test"
  jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" --arg error "$msg" '{error:$error, model:$model, role:$role, endpoint_attempted:"/api/generate", recommended_endpoint:"/api/embed"}' >"$raw_file"
  jq -n --arg model "$MODEL" --arg role "$MODEL_ROLE" '{model:$model, role:$role, reason:"generation benchmark preflight refused embedding-only model"}' >"$payload_file"
  printf '200' >"$http_file"
  : >"$stderr_file"
  append_summary_from_json "preflight" "00_capability_preflight" "$MODEL" "N/A" "0" "0" "0" "$raw_file" "$payload_file" "0.000000" "0" "0" "unsupported_generate_for_embedding_model" "200" "unsupported_generate_for_embedding_model" "$msg"
}

ensure_generation_supported_or_exit() {
  if [[ "$EMBEDDING_MODE" == "1" ]]; then return 0; fi
  if ollama_model_role_is_embedding_only "$MODEL_ROLE"; then
    log "SKIP generation tests: model=$MODEL role=$MODEL_ROLE does not support /api/generate"
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
    exit 1
  fi
}

run_embedding_suite() {
  local sanity_input batch_input long_input
  sanity_input="$(jq -Rn --arg s "RTX 3090 embedding test for RAG retrieval." '$s')"
  batch_input="$(jq -nc '["RTX 3090 local embedding smoke test.","Ollama /api/embed vector generation.","RAG retrieval semantic search baseline.","WSL2 CUDA telemetry embedding run."]')"
  long_input="$(make_long_prompt "$LONG_PROMPT_WORDS" | jq -Rs .)"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_sanity" "01_embed_sanity" "$MODEL" "$NUM_CTX" "$sanity_input" "$TEST_STEP"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_batch" "02_embed_batch" "$MODEL" "$NUM_CTX" "$batch_input" "$TEST_STEP"
  TEST_STEP=$((TEST_STEP + 1)); run_embed "embedding_longctx" "03_embed_longctx" "$MODEL" "$LONG_CTX" "$long_input" "$TEST_STEP"
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
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {
        rows++; cat=col("category"); mode=col("mode"); conc=col("concurrency"); err=col("error"); gen=col("gen_tps")+0; load=col("load_s")+0; resp=col("response_chars")+0; think=col("thinking_chars")+0; pe=col("prompt_eval_tokens")+0; ctx=col("num_ctx")+0; fill=col("context_fill_pct")+0; vc=col("vector_count")+0; vd=col("vector_dim")+0; etps=col("embedding_tps")+0; endpoint=col("endpoint");
        if(err!="")errors++;
        if(mode=="EMBED" || endpoint=="/api/embed" || cat ~ /^embedding/) {embed_rows++; embed_vectors+=vc; if(vd>0) embed_dim=vd; if(err=="") embed_ok++; if(etps>0){embed_tps_n++; embed_tps_sum+=etps}; if(cat=="embedding_longctx"){elong_seen=1; elong_err=err; elong_pe=pe; elong_ctx=ctx; elong_fill=fill}}
        else {gen_rows++; if(resp>0)visible++; if(resp==0&&think>0)thinkonly++; if(cat=="sanity" && load>cold) cold=load; if(mode=="GPU"&&conc==1&&err==""&&(cat=="throughput"||cat=="sustained")&&gen>0){warmn++; warmsum+=gen}; if(cat=="longctx"){long_seen=1; long_err=err; longgen=gen; longpe=pe; longctx=ctx; longfill=fill}}
      }
      END{
        printf "- status_basis: rows=%d errors=%d visible=%d thinking_only=%d embedding_rows=%d\n", rows, errors, visible, thinkonly, embed_rows;
        if(embed_rows>0 && gen_rows==0){ if(embed_tps_n>0) printf "- embedding: vectors=%d dim=%d rows_ok=%d avg_embeddings_per_s=%.2f\n", embed_vectors, embed_dim, embed_ok, embed_tps_sum/embed_tps_n; else printf "- embedding: vectors=%d dim=%d rows_ok=%d\n", embed_vectors, embed_dim, embed_ok; if(elong_seen && elong_err=="") printf "- embedding_long_context: prompt_eval_tokens=%d ctx=%d fill=%.1f%% verdict=%s\n", elong_pe, elong_ctx, elong_fill, (elong_fill>=minfill?"OK":"UNDERFILLED"); else if(elong_seen) print "- embedding_long_context: N/A request failed before prompt evaluation"; }
        else { if(warmn>0) printf "- warm_single_gpu_tps_avg: %.2f across %d rows\n", warmsum/warmn, warmn; printf "- cold_load_s: %.2f\n", cold; if(long_seen && long_err=="") printf "- long_context: prompt_eval_tokens=%d ctx=%d fill=%.1f%% gen_tps=%.2f verdict=%s\n", longpe, longctx, longfill, longgen, (longfill>=minfill?"OK":"UNDERFILLED"); else if(long_seen) print "- long_context: N/A request failed before prompt evaluation"; else print "- long_context: N/A long-context row not run"; }
      }' "$SUMMARY_CSV"
    if [[ -s "$CONC_AGG_CSV" ]]; then echo; echo "## Concurrency aggregate"; echo '```csv'; cat "$CONC_AGG_CSV"; echo '```'; fi
    if [[ -s "$SOAK_SUMMARY_CSV" ]]; then echo; echo "## Soak aggregate"; echo '```csv'; cat "$SOAK_SUMMARY_CSV"; echo '```'; fi
    if [[ -s "$FAILURE_HINTS" ]]; then echo; echo "## Failure hints"; echo '```text'; cat "$FAILURE_HINTS"; echo '```'; fi
    echo; echo "## Preflight diagnostics"; echo
    echo "- API version: $API_VERSION_FILE"
    echo "- API tags: $API_TAGS_FILE"
    echo "- API show model: $API_SHOW_FILE"
    echo "- ollama show/list: $OLLAMA_SHOW_FILE"
    echo "- WSL diagnostics: $WSL_DIAG"
    echo "- Ollama server log tail: $SERVER_LOG_TAIL"
    echo; echo "## Test results"; echo
    awk -F',' '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {test=unq($(h["test"])); cat=unq($(h["category"])); mode=unq($(h["mode"])); endpoint=unq($(h["endpoint"])); ctx=unq($(h["num_ctx"])); np=unq($(h["num_predict"])); reason=unq($(h["done_reason"])); err=unq($(h["error"])); http=unq($(h["http_code"])); cls=unq($(h["error_class"])); body=unq($(h["error_body"])); gen=unq($(h["gen_tps"])); eval=unq($(h["eval_tokens"])); prompt=unq($(h["prompt_eval_tokens"])); fill=unq($(h["context_fill_pct"])); total=unq($(h["total_s"])); vec=unq($(h["vector_count"])); dim=unq($(h["vector_dim"])); gsub(/[|]/,"/",body); if(length(body)>160) body=substr(body,1,157)"..."; if(NR==2){print "| Test | Category | Endpoint | Mode | Ctx | Predict | Prompt tok | Fill % | Eval tok | Gen tok/s | Vectors | Dim | Total s | HTTP | Class | Done/Error body |"; print "|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|"}; if(gen!="") gen=sprintf("%.2f", gen); if(total!="") total=sprintf("%.2f", total); if(fill!="") fill=sprintf("%.1f", fill); final=(body!=""?body:reason); if(cls=="") cls=err; printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", test, cat, endpoint, mode, ctx, np, prompt, fill, eval, gen, vec, dim, total, http, cls, final}
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
    awk -F',' -v minfill="$LONG_CONTEXT_MIN_FILL_PCT" '
      function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
      function col(n){return (h[n] ? unq($(h[n])) : "")}
      NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
      {
        rows++; cat=col("category"); mode=col("mode"); conc=col("concurrency"); err=col("error"); gen=col("gen_tps")+0; total=col("total_s")+0; load=col("load_s")+0; resp=col("response_chars")+0; think=col("thinking_chars")+0; pe=col("prompt_eval_tokens")+0; ctx=col("num_ctx")+0; fill=col("context_fill_pct")+0; vc=col("vector_count")+0; vd=col("vector_dim")+0; etps=col("embedding_tps")+0;
        if(err!="") errors++;
        if(mode=="EMBED" || cat ~ /^embedding/) {embed_rows++; embed_vectors+=vc; if(vd>0) embed_dim=vd; if(etps>0){embed_tps_n++; embed_tps_sum+=etps}; if(err=="") embed_ok++; if(cat=="embedding_longctx"){elong_seen=1; elong_err=err; elong_pe=pe; elong_ctx=ctx; elong_fill=fill}}
        else {gen_rows++; if(resp>0) visible++; if(resp==0&&think>0) think_only++; if(cat=="sanity" && load>cold_load)cold_load=load; if(mode=="GPU"&&conc==1&&err==""&&(cat=="throughput"||cat=="sustained")&&gen>0){warm_n++; warm_sum+=gen; if(warm_n==1||gen>warm_max)warm_max=gen; if(warm_n==1||gen<warm_min)warm_min=gen}; if(cat=="longctx"){long_seen=1; long_err=err; long_gen=gen; long_fill=fill; long_pe=pe; long_ctx=ctx}}
        if(total>max_total)max_total=total
      }
      END{
        status=(errors>0?"FAIL":"PASS"); printf "Status  : %s\n", status;
        if(embed_rows>0 && gen_rows==0){
          if(embed_tps_n>0) printf "Embed   : vectors=%d dim=%d rows=%d ok=%d avg=%.2f embeds/s\n", embed_vectors, embed_dim, embed_rows, embed_ok, embed_tps_sum/embed_tps_n; else printf "Embed   : vectors=%d dim=%d rows=%d ok=%d\n", embed_vectors, embed_dim, embed_rows, embed_ok;
          if(elong_seen && elong_err=="") printf "LongEmb : prompt_tokens=%d ctx=%d fill=%.1f%% %s\n", elong_pe, elong_ctx, elong_fill, (elong_fill>=minfill?"OK":"UNDERFILLED"); else if(elong_seen) print "LongEmb : N/A; request failed before prompt evaluation"; else print "LongEmb : N/A; embedding long-context row not run";
          printf "Output  : embedding rows %d/%d; errors %d\n", embed_ok, embed_rows, errors;
          if(errors==0) print "Inference: PASS; completed embedding benchmark"; else print "Inference: INCONCLUSIVE; embedding benchmark did not complete cleanly";
        } else {
          if(warm_n>0) printf "Warm    : single GPU %.2f tok/s avg (%.2f-%.2f), rows %d\n", warm_sum/warm_n, warm_min, warm_max, warm_n; else print "Warm    : no valid warm single GPU rows";
          printf "Cold    : first-load %.2fs; max total %.2fs\n", cold_load, max_total;
          if(long_seen && long_err=="") printf "LongCtx : prompt_tokens=%d ctx=%d fill=%.1f%% gen=%.2f tok/s %s\n", long_pe, long_ctx, long_fill, long_gen, (long_fill>=minfill?"OK":"UNDERFILLED"); else if(long_seen) print "LongCtx : N/A; request failed before prompt evaluation"; else print "LongCtx : N/A; long-context row not run";
          printf "Output  : visible rows %d/%d; thinking-only %d; errors %d\n", visible, rows, think_only, errors;
          if(errors==0 && visible>0) print "Inference: PASS; completed generation benchmark"; else print "Inference: NOT TESTED; model did not produce usable generation tokens";
          if(errors>0 && visible==0) print "Verdict : benchmark INCONCLUSIVE; model never produced usable tokens";
        }
      }' "$SUMMARY_CSV"
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
      NR<=13{test=col("test"); cat=col("category"); mode=col("mode"); ctx=col("num_ctx"); gen=col("gen_tps"); prompt=col("prompt_eval_tokens"); done=col("done_reason"); cls=col("error_class"); http=col("http_code"); vec=col("vector_count"); dim=col("vector_dim"); if(gen!="") gen=sprintf("%.2f", gen); suffix=(cls!=""?"http="http" "cls:done); if(mode=="EMBED"||cat~/^embedding/) printf "  %-18s %-16s %3s ctx=%-5s prompt=%-5s vec=%-4s dim=%-5s %s\n", test, cat, mode, ctx, prompt, vec, dim, suffix; else printf "  %-18s %-10s %3s ctx=%-5s prompt=%-5s gen=%6s %s\n", test, cat, mode, ctx, prompt, gen, suffix}
      NR==14{print "  ... additional rows omitted from terminal summary; see summary.csv"}' "$SUMMARY_CSV"
    echo "Files:"; echo "  run : $RUN_DIR"; echo "  md  : $SUMMARY_MD"; echo "  csv : $SUMMARY_CSV"; echo "  hint: $FAILURE_HINTS"; echo "  log : $SERVER_LOG_TAIL"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then echo "  zip : $ARCHIVE_PATH"; fi
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
write_meta
snapshot_before_after before
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

if [[ "$EMBEDDING_MODE" == "1" ]]; then
  PLANNED_TESTS=3
else
  PLANNED_TESTS=4
  if [[ "$RUN_CONC" == "1" && "$CONCURRENCY" -gt 1 ]]; then PLANNED_TESTS=$((PLANNED_TESTS + CONCURRENCY)); fi
  if [[ "$RUN_CPU" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
  if [[ "$RUN_VRAM_PRESSURE" == "1" ]]; then PLANNED_TESTS=$((PLANNED_TESTS + 1)); fi
fi
TEST_STEP=0
log "Test plan: model=$MODEL role=$MODEL_ROLE embedding=$EMBEDDING_MODE think=$THINK tests=$PLANNED_TESTS ctx=$NUM_CTX long_ctx=$LONG_CTX long_prompt_words=$LONG_PROMPT_WORDS predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU soak_minutes=$SOAK_MINUTES run_vram_pressure=$RUN_VRAM_PRESSURE"

if [[ "$EMBEDDING_MODE" == "1" ]]; then
  run_embedding_suite
else
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
fi
snapshot_before_after after
capture_dmesg_gpu_errors
capture_ollama_server_log_tail
make_failure_hints
if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
make_summary_md
make_terminal_summary
make_archive

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" ]]; then print_file_plain "$TERMINAL_SUMMARY"; else log "Test collector completed; artifacts are under $RUN_DIR"; fi
ERROR_COUNT="$(awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s} NR==1{for(i=1;i<=NF;i++)h[unq($i)]=i; next} {if(unq($(h["error"]))!="")e++} END{print e+0}' "$SUMMARY_CSV")"
if [[ "$ERROR_COUNT" -gt 0 ]]; then exit 1; fi
