#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.5.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_AND_MONITOR_RTX3090_SCRIPT_SIGNATURE=v0.5.0-orchestrator"

MODEL="${MODEL:-qwen3:8b}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-and-monitor-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
INTERVAL="${INTERVAL:-1}"
MONITOR_PROFILE="${MONITOR_PROFILE:-deep}"
NUM_CTX="${NUM_CTX:-4096}"
LONG_CTX="${LONG_CTX:-8192}"
NUM_PREDICT="${NUM_PREDICT:-512}"
LONG_NUM_PREDICT="${LONG_NUM_PREDICT:-1024}"
CONCURRENCY="${CONCURRENCY:-2}"
RUN_CONC="${RUN_CONC:-1}"
RUN_CPU="${RUN_CPU:-0}"
PULL_IF_MISSING="${PULL_IF_MISSING:-0}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
SUMMARY_MD="$RUN_DIR/orchestrator-summary.md"
ERRORS_FILE="$RUN_DIR/errors.log"
ARCHIVE_PATH=""
MONITOR_PID=""
TEST_RC=0
CLEANED=0

usage() {
  cat <<EOF_USAGE
ollama-test-and-monitor-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Run RTX 3090 Ollama tests while ollama-monitor.sh captures GPU/Ollama telemetry in parallel.

Usage:
  ./ollama-test-and-monitor-RTX3090.sh [options]

Options:
  --model NAME          Model to test (default: $MODEL)
  --base-url URL        Ollama base URL (default: $BASE_URL)
  --out-dir DIR         Output root (default: $OUT_DIR)
  --run-id ID           Override run id
  --interval N          Monitor interval seconds (default: $INTERVAL)
  --monitor-profile P   brief|normal|deep (default: $MONITOR_PROFILE)
  --num-ctx N           Test standard context (default: $NUM_CTX)
  --long-ctx N          Test long context (default: $LONG_CTX)
  --num-predict N       Test generation length (default: $NUM_PREDICT)
  --long-num-predict N  Sustained generation length (default: $LONG_NUM_PREDICT)
  --concurrency N       Test concurrency probe size (default: $CONCURRENCY)
  --run-conc / --no-conc        Enable/disable concurrency probe (default: $RUN_CONC)
  --run-cpu / --no-cpu          Enable/disable CPU comparison (default: $RUN_CPU)
  --pull / --no-pull            Pull model if missing (default: $PULL_IF_MISSING)
  --timeout-sec N       curl max time per test request (default: $TIMEOUT_SEC)
  --zip / --no-zip      Create combined ~/tmp zip archive (default: $ZIP_ON_EXIT)
  -h, --help            Show help

Outputs:
  $RUN_DIR/
    monitor.console.log, test.console.log, orchestrator-summary.md, monitor/, test/
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
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --monitor-profile) MONITOR_PROFILE="${2:-}"; shift 2 ;;
    --num-ctx) NUM_CTX="${2:-}"; shift 2 ;;
    --long-ctx) LONG_CTX="${2:-}"; shift 2 ;;
    --num-predict) NUM_PREDICT="${2:-}"; shift 2 ;;
    --long-num-predict) LONG_NUM_PREDICT="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --run-conc) RUN_CONC=1; shift ;;
    --no-conc) RUN_CONC=0; shift ;;
    --run-cpu) RUN_CPU=1; shift ;;
    --no-cpu) RUN_CPU=0; shift ;;
    --pull) PULL_IF_MISSING=1; shift ;;
    --no-pull) PULL_IF_MISSING=0; shift ;;
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for n in INTERVAL NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT CONCURRENCY TIMEOUT_SEC; do
  is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }
done
[[ "$INTERVAL" -ge 1 ]] || INTERVAL=1
[[ "$CONCURRENCY" -ge 1 ]] || CONCURRENCY=1

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
SUMMARY_MD="$RUN_DIR/orchestrator-summary.md"
ERRORS_FILE="$RUN_DIR/errors.log"
mkdir -p "$RUN_DIR" "$MONITOR_ROOT" "$TEST_ROOT" "$TMP_DIR"
: >"$ERRORS_FILE"

SD="$(script_dir)"
MONITOR_SCRIPT="$SD/ollama-monitor.sh"
TEST_SCRIPT="$SD/ollama-test-RTX3090.sh"
START_SCRIPT="$SD/ollama-start"
[[ -x "$MONITOR_SCRIPT" ]] || { echo "ERROR: missing executable $MONITOR_SCRIPT" >&2; exit 2; }
[[ -x "$TEST_SCRIPT" ]] || { echo "ERROR: missing executable $TEST_SCRIPT" >&2; exit 2; }
need_cmd curl

ensure_server() {
  if curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$START_SCRIPT" ]]; then
    BASE_URL="$BASE_URL" "$START_SCRIPT" || true
  elif command -v ollama >/dev/null 2>&1; then
    mkdir -p "$HOME/log"
    nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 &
    sleep 3
  fi
  curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1 || {
    echo "ERROR: Ollama server is not reachable at $BASE_URL" >&2
    exit 3
  }
}

make_summary() {
  {
    echo "# RTX 3090 Ollama Test + Monitor Orchestrator Summary"
    echo
    echo "## Run metadata"
    echo "- script_version: $VERSION"
    echo "- signature: $SCRIPT_SIGNATURE"
    echo "- run_id: $RUN_ID"
    echo "- model: $MODEL"
    echo "- base_url: $BASE_URL"
    echo "- run_dir: $RUN_DIR"
    echo "- test_exit_code: $TEST_RC"
    echo "- combined_archive: ${ARCHIVE_PATH:-pending}"
    echo
    echo "## Component outputs"
    echo "- monitor root: $MONITOR_ROOT"
    echo "- test root: $TEST_ROOT"
    echo "- monitor console: $RUN_DIR/monitor.console.log"
    echo "- test console: $RUN_DIR/test.console.log"
    echo
    echo "## Latest test summary"
    local test_summary
    test_summary="$(find "$TEST_ROOT" -name summary.md -type f | sort | tail -1 || true)"
    if [[ -n "$test_summary" && -f "$test_summary" ]]; then
      cat "$test_summary"
    else
      echo "No test summary found."
    fi
    echo
    echo "## Latest monitor report"
    local monitor_report
    monitor_report="$(find "$MONITOR_ROOT" -name report.md -type f | sort | tail -1 || true)"
    if [[ -n "$monitor_report" && -f "$monitor_report" ]]; then
      cat "$monitor_report"
    else
      echo "No monitor report found."
    fi
  } >"$SUMMARY_MD"
}

make_archive() {
  [[ "$ZIP_ON_EXIT" == "1" ]] || return 0
  mkdir -p "$TMP_DIR"
  ARCHIVE_PATH="$TMP_DIR/ollama-test-and-monitor-RTX3090-$RUN_ID.zip"
  rm -f "$ARCHIVE_PATH"
  printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  if command -v zip >/dev/null 2>&1; then
    (cd "$OUT_DIR" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  elif command -v python3 >/dev/null 2>&1; then
    (cd "$OUT_DIR" && python3 -m zipfile -c "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  else
    warn "zip and python3 are missing; cannot create combined archive"
  fi
}

cleanup() {
  [[ "$CLEANED" == "1" ]] && return 0
  CLEANED=1
  if [[ -n "${MONITOR_PID:-}" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
    # Background jobs in non-interactive Bash may inherit SIGINT ignored; use TERM,
    # which ollama-monitor.sh traps and finalizes into report+zip.
    kill -TERM "$MONITOR_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
      warn "monitor did not stop after TERM; sending KILL"
      kill -KILL "$MONITOR_PID" 2>/dev/null || true
    fi
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
  if [[ "$ZIP_ON_EXIT" == "1" ]]; then
    ARCHIVE_PATH="$TMP_DIR/ollama-test-and-monitor-RTX3090-$RUN_ID.zip"
    printf '%s
' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  fi
  make_summary || true
  make_archive || true
}
trap 'TEST_RC=130; cleanup; exit 130' INT
trap 'TEST_RC=143; cleanup; exit 143' TERM
trap 'rc=$?; if [[ $rc -ne 0 ]]; then TEST_RC=$rc; fi; cleanup' EXIT

ensure_server

log "ollama-test-and-monitor-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Starting monitor..."

BASE_URL="$BASE_URL" OUT_DIR="$MONITOR_ROOT" TMP_DIR="$TMP_DIR" \
  "$MONITOR_SCRIPT" --interval "$INTERVAL" --profile "$MONITOR_PROFILE" --run-id "$RUN_ID-monitor" \
  >"$RUN_DIR/monitor.console.log" 2>&1 &
MONITOR_PID="$!"
sleep 2

log "Running tests..."
TEST_ARGS=(
  --model "$MODEL"
  --base-url "$BASE_URL"
  --out-dir "$TEST_ROOT"
  --run-id "$RUN_ID-test"
  --num-ctx "$NUM_CTX"
  --long-ctx "$LONG_CTX"
  --num-predict "$NUM_PREDICT"
  --long-num-predict "$LONG_NUM_PREDICT"
  --concurrency "$CONCURRENCY"
  --timeout-sec "$TIMEOUT_SEC"
  --no-ensure-server
)
[[ "$RUN_CONC" == "1" ]] && TEST_ARGS+=(--run-conc) || TEST_ARGS+=(--no-conc)
[[ "$RUN_CPU" == "1" ]] && TEST_ARGS+=(--run-cpu) || TEST_ARGS+=(--no-cpu)
[[ "$PULL_IF_MISSING" == "1" ]] && TEST_ARGS+=(--pull) || TEST_ARGS+=(--no-pull)

set +e
BASE_URL="$BASE_URL" TMP_DIR="$TMP_DIR" "$TEST_SCRIPT" "${TEST_ARGS[@]}" >"$RUN_DIR/test.console.log" 2>&1
TEST_RC=$?
set -e

cleanup

log "Summary: $SUMMARY_MD"
if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:     $ARCHIVE_PATH"; fi
log "Run dir: $RUN_DIR"
exit "$TEST_RC"
