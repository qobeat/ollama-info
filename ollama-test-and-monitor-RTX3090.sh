#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.6.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_AND_MONITOR_RTX3090_SCRIPT_SIGNATURE=v0.6.0-orchestrator-terminal-summary"

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
PRINT_TERMINAL_SUMMARY="${PRINT_TERMINAL_SUMMARY:-1}"
THINK="${THINK:-false}"

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
SUMMARY_MD="$RUN_DIR/orchestrator-summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
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
  --think VALUE         Ollama top-level think parameter: false|true|none|low|medium|high (default: $THINK)
  --run-conc / --no-conc        Enable/disable concurrency probe (default: $RUN_CONC)
  --run-cpu / --no-cpu          Enable/disable CPU comparison (default: $RUN_CPU)
  --pull / --no-pull            Pull model if missing (default: $PULL_IF_MISSING)
  --timeout-sec N       curl max time per test request (default: $TIMEOUT_SEC)
  --terminal-summary / --no-terminal-summary  Print <=50-line ASCII summary (default: $PRINT_TERMINAL_SUMMARY)
  --zip / --no-zip      Create combined ~/tmp zip archive (default: $ZIP_ON_EXIT)
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
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --monitor-profile) MONITOR_PROFILE="${2:-}"; shift 2 ;;
    --num-ctx) NUM_CTX="${2:-}"; shift 2 ;;
    --long-ctx) LONG_CTX="${2:-}"; shift 2 ;;
    --num-predict) NUM_PREDICT="${2:-}"; shift 2 ;;
    --long-num-predict) LONG_NUM_PREDICT="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --think) THINK="${2:-}"; shift 2 ;;
    --run-conc) RUN_CONC=1; shift ;;
    --no-conc) RUN_CONC=0; shift ;;
    --run-cpu) RUN_CPU=1; shift ;;
    --no-cpu) RUN_CPU=0; shift ;;
    --pull) PULL_IF_MISSING=1; shift ;;
    --no-pull) PULL_IF_MISSING=0; shift ;;
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --terminal-summary) PRINT_TERMINAL_SUMMARY=1; shift ;;
    --no-terminal-summary) PRINT_TERMINAL_SUMMARY=0; shift ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for n in INTERVAL NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT CONCURRENCY TIMEOUT_SEC; do is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }; done
case "$THINK" in true|false|none|low|medium|high) ;; *) echo "ERROR: --think must be false, true, none, low, medium, or high" >&2; exit 2 ;; esac
[[ "$INTERVAL" -ge 1 ]] || INTERVAL=1
[[ "$CONCURRENCY" -ge 1 ]] || CONCURRENCY=1

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
SUMMARY_MD="$RUN_DIR/orchestrator-summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
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
need_cmd tee

ensure_server() {
  if curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1; then return 0; fi
  if [[ -x "$START_SCRIPT" ]]; then BASE_URL="$BASE_URL" "$START_SCRIPT" || true; elif command -v ollama >/dev/null 2>&1; then mkdir -p "$HOME/log"; nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 & sleep 3; fi
  curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1 || { echo "ERROR: Ollama server is not reachable at $BASE_URL" >&2; exit 3; }
}

make_terminal_summary() {
  local test_csv monitor_csv test_summary monitor_report
  test_csv="$(find "$TEST_ROOT" -name summary.csv -type f | sort | tail -1 || true)"
  monitor_csv="$(find "$MONITOR_ROOT" -name gpu.csv -type f | sort | tail -1 || true)"
  test_summary="$(find "$TEST_ROOT" -name summary.md -type f | sort | tail -1 || true)"
  monitor_report="$(find "$MONITOR_ROOT" -name report.md -type f | sort | tail -1 || true)"
  {
    echo "============================================================"
    echo "RTX3090 OLLAMA TEST+MONITOR SUMMARY"
    echo "Run ID  : $RUN_ID"
    echo "Model   : $MODEL"
    echo "API     : $BASE_URL"
    echo "Status  : test_exit_code=$TEST_RC"
    if [[ -n "$test_csv" && -f "$test_csv" ]]; then
      awk -F',' '
        function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
        NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
        {rows++; mode=unq($(h["mode"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; total=unq($(h["total_s"]))+0; load=unq($(h["load_s"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; if(err!="") errors++; if(mode=="GPU"&&gen>0){gpu_n++; gpu_sum+=gen; if(gpu_n==1||gen>gpu_max)gpu_max=gen; if(gpu_n==1||gen<gpu_min)gpu_min=gen}; if(resp>0)visible++; if(resp==0&&think>0)think_only++; if(load>max_load)max_load=load; if(total>max_total)max_total=total}
        END{printf "Perf    : GPU avg %.2f tok/s, min %.2f, max %.2f, rows %d\n", (gpu_n?gpu_sum/gpu_n:0), gpu_min, gpu_max, gpu_n; printf "Output  : visible rows %d/%d; thinking-only rows %d; errors %d\n", visible, rows, think_only, errors; printf "Timing  : max total %.2fs; max load %.2fs\n", max_total, max_load}' "$test_csv"
    else
      echo "Perf    : test CSV not found"
    fi
    if [[ -n "$monitor_csv" && -f "$monitor_csv" ]]; then
      awk -F',' '
        function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
        NR==1{for(i=1;i<=NF;i++) h[trim($i)]=i; next}
        {n++; name=trim($(h["name"])); util=trim($(h["gpu_util_pct"]))+0; temp=trim($(h["temp_c"]))+0; power=trim($(h["power_w"]))+0; vram=trim($(h["vram_used_mib"]))+0; total=trim($(h["vram_total_mib"]))+0; pg=trim($(h["pcie_gen_current"])); pw=trim($(h["pcie_width_current"])); pmw=trim($(h["pcie_width_max"])); sum_util+=util; if(util>max_util)max_util=util; if(temp>max_temp)max_temp=temp; if(power>max_power)max_power=power; if(vram>max_vram)max_vram=vram; if(total>0)last_total=total; last_pg=pg; last_pw=pw; last_pmw=pmw}
        END{pct=(last_total?100*max_vram/last_total:0); printf "GPU     : %s; samples %d; avg-util %.1f%%; max-util %.0f%%\n", name, n, (n?sum_util/n:0), max_util; printf "Thermal : max-temp %.0fC; max-power %.1fW\n", max_temp, max_power; printf "VRAM    : max-used %.0f MiB / %.0f MiB (%.1f%%)\n", max_vram, last_total, pct; printf "PCIe    : gen %s; width x%s / max x%s\n", last_pg, last_pw, last_pmw}' "$monitor_csv"
    else
      echo "GPU     : monitor CSV not found"
    fi
    echo "Tests:"
    if [[ -n "$test_csv" && -f "$test_csv" ]]; then
      awk -F',' '
        function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
        NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
        {test=unq($(h["test"])); mode=unq($(h["mode"])); ctx=unq($(h["num_ctx"])); np=unq($(h["num_predict"])); gen=unq($(h["gen_tps"])); total=unq($(h["total_s"])); resp=unq($(h["response_chars"])); think=unq($(h["thinking_chars"])); done=unq($(h["done_reason"])); if(gen!="")gen=sprintf("%.2f",gen); if(total!="")total=sprintf("%.2f",total); printf "  %-18s %3s ctx=%-5s pred=%-5s gen=%6s t/s total=%7ss resp=%-4s think=%-5s %s\n", test, mode, ctx, np, gen, total, resp, think, done}' "$test_csv"
    fi
    echo "Files:"
    echo "  run : $RUN_DIR"
    echo "  zip : ${ARCHIVE_PATH:-not-created}"
    echo "  md  : $SUMMARY_MD"
    echo "  test: ${test_summary:-not-found}"
    echo "  mon : ${monitor_report:-not-found}"
    echo "============================================================"
  } >"$TERMINAL_SUMMARY"
}

make_summary() {
  local test_summary monitor_report test_csv monitor_csv
  test_summary="$(find "$TEST_ROOT" -name summary.md -type f | sort | tail -1 || true)"
  monitor_report="$(find "$MONITOR_ROOT" -name report.md -type f | sort | tail -1 || true)"
  test_csv="$(find "$TEST_ROOT" -name summary.csv -type f | sort | tail -1 || true)"
  monitor_csv="$(find "$MONITOR_ROOT" -name gpu.csv -type f | sort | tail -1 || true)"
  {
    echo "# RTX 3090 Ollama Test + Monitor Orchestrator Summary"; echo
    echo "## Run metadata"
    echo "- script_version: $VERSION"
    echo "- signature: $SCRIPT_SIGNATURE"
    echo "- run_id: $RUN_ID"
    echo "- model: $MODEL"
    echo "- base_url: $BASE_URL"
    echo "- think: $THINK"
    echo "- run_dir: $RUN_DIR"
    echo "- test_exit_code: $TEST_RC"
    echo "- combined_archive: ${ARCHIVE_PATH:-pending}"; echo
    echo "## Compact terminal summary"; echo '```text'; if [[ -s "$TERMINAL_SUMMARY" ]]; then cat "$TERMINAL_SUMMARY"; else echo "terminal summary not generated"; fi; echo '```'; echo
    echo "## Detailed component files"
    echo "- test summary: ${test_summary:-not found}"
    echo "- test CSV: ${test_csv:-not found}"
    echo "- monitor report: ${monitor_report:-not found}"
    echo "- monitor GPU CSV: ${monitor_csv:-not found}"
    echo "- monitor console: $RUN_DIR/monitor.console.log"
    echo "- test console: $RUN_DIR/test.console.log"; echo
    echo "## Retention guidance"
    echo "Keep Markdown summaries for human review, CSV files for sortable metrics, raw JSON for exact Ollama API evidence, payload JSON for reproducibility, and gpu.csv for independent telemetry analysis. The orchestrator summary is intentionally compact and should not duplicate every nested report."
  } >"$SUMMARY_MD"
}

make_archive() {
  [[ "$ZIP_ON_EXIT" == "1" ]] || return 0
  mkdir -p "$TMP_DIR"; ARCHIVE_PATH="$TMP_DIR/ollama-test-and-monitor-RTX3090-$RUN_ID.zip"; rm -f "$ARCHIVE_PATH"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  if command -v zip >/dev/null 2>&1; then (cd "$OUT_DIR" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")"); elif command -v python3 >/dev/null 2>&1; then (cd "$OUT_DIR" && python3 -m zipfile -c "$ARCHIVE_PATH" "$(basename "$RUN_DIR")"); else warn "zip and python3 are missing; cannot create combined archive"; fi
}

cleanup() {
  [[ "$CLEANED" == "1" ]] && return 0
  CLEANED=1
  if [[ -n "${MONITOR_PID:-}" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
    kill -TERM "$MONITOR_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do if ! kill -0 "$MONITOR_PID" 2>/dev/null; then break; fi; sleep 1; done
    if kill -0 "$MONITOR_PID" 2>/dev/null; then warn "monitor did not stop after TERM; sending KILL"; kill -KILL "$MONITOR_PID" 2>/dev/null || true; fi
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
  if [[ "$ZIP_ON_EXIT" == "1" ]]; then ARCHIVE_PATH="$TMP_DIR/ollama-test-and-monitor-RTX3090-$RUN_ID.zip"; printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"; fi
  make_terminal_summary || true
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
log "Plan: model=$MODEL think=$THINK ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU"
log "Monitor: interval=${INTERVAL}s profile=$MONITOR_PROFILE"
log "Starting monitor..."

BASE_URL="$BASE_URL" OUT_DIR="$MONITOR_ROOT" TMP_DIR="$TMP_DIR" "$MONITOR_SCRIPT" --interval "$INTERVAL" --profile "$MONITOR_PROFILE" --run-id "$RUN_ID-monitor" --no-zip >"$RUN_DIR/monitor.console.log" 2>&1 &
MONITOR_PID="$!"
sleep 2

log "Running tests..."
TEST_ARGS=(
  --model "$MODEL" --base-url "$BASE_URL" --out-dir "$TEST_ROOT" --run-id "$RUN_ID-test"
  --num-ctx "$NUM_CTX" --long-ctx "$LONG_CTX" --num-predict "$NUM_PREDICT" --long-num-predict "$LONG_NUM_PREDICT"
  --concurrency "$CONCURRENCY" --timeout-sec "$TIMEOUT_SEC" --think "$THINK" --no-terminal-summary --no-zip --no-ensure-server
)
[[ "$RUN_CONC" == "1" ]] && TEST_ARGS+=(--run-conc) || TEST_ARGS+=(--no-conc)
[[ "$RUN_CPU" == "1" ]] && TEST_ARGS+=(--run-cpu) || TEST_ARGS+=(--no-cpu)
[[ "$PULL_IF_MISSING" == "1" ]] && TEST_ARGS+=(--pull) || TEST_ARGS+=(--no-pull)

set +e
BASE_URL="$BASE_URL" TMP_DIR="$TMP_DIR" "$TEST_SCRIPT" "${TEST_ARGS[@]}" 2>&1 | tee "$RUN_DIR/test.console.log"
TEST_RC=${PIPESTATUS[0]}
set -e

cleanup

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" && -s "$TERMINAL_SUMMARY" ]]; then cat "$TERMINAL_SUMMARY"; else log "Summary: $SUMMARY_MD"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:     $ARCHIVE_PATH"; fi; log "Run dir: $RUN_DIR"; fi
exit "$TEST_RC"
