#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.3.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_AND_MONITOR_RTX3090_SCRIPT_SIGNATURE=v1.3.0-timestamped-clean-errors-nvidia-snapshots-reorg"

MODEL="${MODEL:-}"
MODEL_PATTERN="${MODEL_PATTERN:-}"
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
LONG_PROMPT_WORDS="${LONG_PROMPT_WORDS:-3200}"
CONCURRENCY="${CONCURRENCY:-2}"
RUN_CONC="${RUN_CONC:-1}"
RUN_CPU="${RUN_CPU:-0}"
SOAK_MINUTES="${SOAK_MINUTES:-0}"
SOAK_NUM_PREDICT="${SOAK_NUM_PREDICT:-512}"
RUN_VRAM_PRESSURE="${RUN_VRAM_PRESSURE:-0}"
VRAM_MODEL="${VRAM_MODEL:-}"
VRAM_CTX="${VRAM_CTX:-$LONG_CTX}"
VRAM_NUM_PREDICT="${VRAM_NUM_PREDICT:-256}"
PULL_IF_MISSING="${PULL_IF_MISSING:-0}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"
PRINT_TERMINAL_SUMMARY="${PRINT_TERMINAL_SUMMARY:-1}"
THINK="${THINK:-false}"
SERVER_LOG_LINES="${SERVER_LOG_LINES:-240}"
CAPTURE_WSL_DIAGNOSTICS="${CAPTURE_WSL_DIAGNOSTICS:-1}"

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
HARDWARE_ROOT="$RUN_DIR/hardware"
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
  ./ollama-test-and-monitor-RTX3090.sh MODEL_PATTERN [options]
  ./ollama-test-and-monitor-RTX3090.sh --model MODEL_PATTERN [options]
  ./ollama-test-and-monitor-RTX3090.sh --help

Short example:
  ./ollama-test-and-monitor-RTX3090.sh qwen3.6

Model selection:
  MODEL_PATTERN is resolved against locally available Ollama model names from /api/tags.
  Matching order is exact full name, exact base name before ':', then unique case-insensitive substring.
  Example: qwen3.6 resolves to qwen3.6:35b when that is the only local match.
  With no MODEL_PATTERN, the script prints a short dashboard, status, available models, and run commands.
  With no/ambiguous match, it prints matching/available model run commands only.
  Full help is shown only with -h or --help.

Defaults for RTX 3090 baseline:
  monitor-profile=$MONITOR_PROFILE interval=${INTERVAL}s ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT
  long_prompt_words=$LONG_PROMPT_WORDS concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU think=$THINK

Core options:
  --model PATTERN           Model name or pattern to resolve locally
  --base-url URL            Ollama base URL (default: $BASE_URL)
  --out-dir DIR             Output root (default: $OUT_DIR)
  --run-id ID               Override run id
  --interval N              Monitor interval seconds (default: $INTERVAL)
  --monitor-profile P       brief|normal|deep (default: $MONITOR_PROFILE)
  --num-ctx N               Test standard context (default: $NUM_CTX)
  --long-ctx N              Test long context (default: $LONG_CTX)
  --num-predict N           Test generation length (default: $NUM_PREDICT)
  --long-num-predict N      Sustained generation length (default: $LONG_NUM_PREDICT)
  --long-prompt-words N     True long-context prompt size (default: $LONG_PROMPT_WORDS)
  --concurrency N           Test concurrency probe size (default: $CONCURRENCY)
  --think VALUE             Ollama top-level think: false|true|none|low|medium|high (default: $THINK)
  --server-log-lines N      Capture last N Ollama server log lines in test artifacts (default: $SERVER_LOG_LINES)
  --no-wsl-diagnostics      Skip WSL/Windows-side configuration snapshots in test artifacts

Optional probes:
  --run-conc / --no-conc    Enable/disable concurrency probe (default: $RUN_CONC)
  --run-cpu / --no-cpu      Enable/disable CPU comparison (default: $RUN_CPU)
  --soak-minutes N          Optional soak duration; 0 disables (default: $SOAK_MINUTES)
  --soak-num-predict N      Per-request soak generation length (default: $SOAK_NUM_PREDICT)
  --run-vram-pressure       Enable optional VRAM-pressure probe
  --no-vram-pressure        Disable optional VRAM-pressure probe (default)
  --vram-model NAME         Optional larger model for VRAM pressure
  --vram-ctx N              VRAM-pressure context (default: $VRAM_CTX)
  --vram-num-predict N      VRAM-pressure generation length (default: $VRAM_NUM_PREDICT)

Operational options:
  --pull / --no-pull        Pull missing exact model after resolution (default: $PULL_IF_MISSING)
  --timeout-sec N           curl max time per test request (default: $TIMEOUT_SEC)
  --terminal-summary / --no-terminal-summary  Print <=50-line ASCII summary (default: $PRINT_TERMINAL_SUMMARY)
  --zip / --no-zip          Create combined ~/tmp zip archive (default: $ZIP_ON_EXIT)
  -h, --help                Show help
EOF_USAGE
}

short_usage() {
  cat <<EOF_SHORT
ollama-test-and-monitor-RTX3090.sh v$VERSION
Usage: $(script_display_cmd) <model-pattern> [options]
Example: $(script_display_cmd) qwen3.6
Safe first run: $(script_display_cmd) qwen3.6 --no-conc --concurrency 1
Defaults: monitor=$MONITOR_PROFILE interval=${INTERVAL}s ctx=$NUM_CTX long_ctx=$LONG_CTX predict=$NUM_PREDICT concurrency=$CONCURRENCY think=$THINK
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
    trap - EXIT INT TERM 2>/dev/null || true
    exit 3
  fi
}

log() { printf '%s %s\n' "$(date -Is)" "$*"; }
warn() { printf '%s WARN: %s\n' "$(date -Is)" "$*" >&2; printf '%s WARN: %s\n' "$(date -Is)" "$*" >>"$ERRORS_FILE" 2>/dev/null || true; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 2; }; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
print_file_timestamped() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
      printf '%s\n' "$line"
    else
      printf '%s %s\n' "$(date -Is)" "$line"
    fi
  done <"$1"
}
script_dir() { cd -- "$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")" && pwd; }
script_display_cmd() {
  case "$0" in
    */*) printf '%s\n' "$0" ;;
    *) printf '%s\n' "$(basename "$0")" ;;
  esac
}

timestamp_stream() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
      printf '%s\n' "$line"
    else
      printf '%s %s\n' "$(date -Is)" "$line"
    fi
  done
}

ORIGINAL_ARGC=$#
NO_MODEL_ARGS=0
[[ "$ORIGINAL_ARGC" -eq 0 ]] && NO_MODEL_ARGS=1

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
    --long-prompt-words) LONG_PROMPT_WORDS="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --think) THINK="${2:-}"; shift 2 ;;
    --server-log-lines) SERVER_LOG_LINES="${2:-}"; shift 2 ;;
    --wsl-diagnostics) CAPTURE_WSL_DIAGNOSTICS=1; shift ;;
    --no-wsl-diagnostics) CAPTURE_WSL_DIAGNOSTICS=0; shift ;;
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
    --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
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

for n in INTERVAL NUM_CTX LONG_CTX NUM_PREDICT LONG_NUM_PREDICT LONG_PROMPT_WORDS CONCURRENCY SOAK_MINUTES SOAK_NUM_PREDICT VRAM_CTX VRAM_NUM_PREDICT TIMEOUT_SEC CONNECT_TIMEOUT_SEC; do is_uint "${!n}" || { echo "ERROR: $n must be an integer" >&2; exit 2; }; done
case "$THINK" in true|false|none|low|medium|high) ;; *) echo "ERROR: --think must be false, true, none, low, medium, or high" >&2; exit 2 ;; esac
[[ "$INTERVAL" -ge 1 ]] || INTERVAL=1
[[ "$CONCURRENCY" -ge 1 ]] || CONCURRENCY=1

RUN_DIR="$OUT_DIR/run-$RUN_ID"
MONITOR_ROOT="$RUN_DIR/monitor"
TEST_ROOT="$RUN_DIR/test"
HARDWARE_ROOT="$RUN_DIR/hardware"
SUMMARY_MD="$RUN_DIR/orchestrator-summary.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
mkdir -p "$RUN_DIR" "$MONITOR_ROOT" "$TEST_ROOT" "$HARDWARE_ROOT" "$TMP_DIR"
: >"$ERRORS_FILE"

SD="$(script_dir)"
COMMON_SCRIPT="$SD/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"
MONITOR_SCRIPT="$SD/ollama-monitor.sh"
TEST_SCRIPT="$SD/ollama-test-RTX3090.sh"
START_SCRIPT="$SD/ollama-start"
[[ -x "$MONITOR_SCRIPT" ]] || { echo "ERROR: missing executable $MONITOR_SCRIPT" >&2; exit 2; }
[[ -x "$TEST_SCRIPT" ]] || { echo "ERROR: missing executable $TEST_SCRIPT" >&2; exit 2; }
need_cmd curl
need_cmd jq
need_cmd tee

# Preflight never starts Ollama. It reports status and prints the exact start command instead.
ensure_server() {
  require_ollama_ready
}

select_or_explain_model() {
  local pattern="$1" resolved rc matches
  if [[ -z "$pattern" ]]; then
    echo "ERROR: model pattern is required." >&2
    show_no_args_screen >&2
    trap - EXIT INT TERM 2>/dev/null || true
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
    trap - EXIT INT TERM 2>/dev/null || true
    exit 5
  fi
  echo "ERROR: no local Ollama model matched pattern '$pattern'." >&2
  ollama_print_available_model_commands "$BASE_URL" "$(script_display_cmd)" "$CONNECT_TIMEOUT_SEC" >&2 || true
  echo "Use -h for full options." >&2
  trap - EXIT INT TERM 2>/dev/null || true
  exit 4
}

latest_file() { find "$1" -name "$2" -type f 2>/dev/null | sort | tail -1 || true; }
capture_nvidia_boundary() {
  local label="$1"
  mkdir -p "$HARDWARE_ROOT"
  {
    echo "# nvidia-smi $label snapshot"
    echo "timestamp=$(date -Is)"
    echo
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi
    else
      echo "nvidia-smi not found"
    fi
  } >"$HARDWARE_ROOT/nvidia-smi-$label.txt" 2>&1 || true
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -q -d POWER,TEMPERATURE,CLOCK,PERFORMANCE,PCI,MEMORY,UTILIZATION >"$HARDWARE_ROOT/nvidia-smi-q-$label.txt" 2>&1 || true
    nvidia-smi --query-gpu=timestamp,index,name,driver_version,pci.bus_id,temperature.gpu,power.draw,power.limit,memory.used,memory.total,memory.free,utilization.gpu,utilization.memory,clocks.gr,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,pstate,fan.speed --format=csv >"$HARDWARE_ROOT/nvidia-smi-query-$label.csv" 2>&1 || true
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv >"$HARDWARE_ROOT/nvidia-compute-apps-$label.csv" 2>&1 || true
  fi
}

make_terminal_summary() {
  local test_csv conc_csv soak_csv monitor_csv test_summary monitor_report hint_file server_log_tail
  test_csv="$(latest_file "$TEST_ROOT" summary.csv)"
  conc_csv="$(latest_file "$TEST_ROOT" concurrency-aggregate.csv)"
  soak_csv="$(latest_file "$TEST_ROOT" soak-summary.csv)"
  monitor_csv="$(latest_file "$MONITOR_ROOT" gpu.csv)"
  test_summary="$(latest_file "$TEST_ROOT" summary.md)"
  monitor_report="$(latest_file "$MONITOR_ROOT" report.md)"
  hint_file="$(latest_file "$TEST_ROOT" failure-hints.txt)"
  server_log_tail="$(latest_file "$TEST_ROOT" ollama-server-log-tail.txt)"
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
        {rows++; cat=unq($(h["category"])); mode=unq($(h["mode"])); conc=unq($(h["concurrency"])); err=unq($(h["error"])); gen=unq($(h["gen_tps"]))+0; load=unq($(h["load_s"]))+0; resp=unq($(h["response_chars"]))+0; think=unq($(h["thinking_chars"]))+0; pe=unq($(h["prompt_eval_tokens"]))+0; ctx=unq($(h["num_ctx"]))+0; fill=unq($(h["context_fill_pct"]))+0; if(err!="") errors++; if(resp>0)visible++; if(resp==0&&think>0)thinkonly++; if(cat=="sanity" && load>cold)cold=load; if(mode=="GPU"&&conc==1&&err==""&&(cat=="throughput"||cat=="sustained")&&gen>0){warmn++; warmsum+=gen; if(warmn==1||gen>wmax)wmax=gen; if(warmn==1||gen<wmin)wmin=gen}; if(cat=="longctx"){longgen=gen; longpe=pe; longctx=ctx; longfill=fill}}
        END{status=(errors>0?"FAIL":((thinkonly>0||longfill<35)?"PASS_WITH_WARNINGS":"PASS")); printf "Test    : %s\n", status; if(warmn>0) printf "Warm    : single GPU %.2f tok/s avg (%.2f-%.2f), rows %d\n", warmsum/warmn, wmin, wmax, warmn; else print "Warm    : no valid warm single GPU rows"; printf "Cold    : first-load %.2fs\n", cold; printf "LongCtx : prompt_tokens=%d ctx=%d fill=%.1f%% gen=%.2f tok/s %s\n", longpe, longctx, longfill, longgen, (longfill>=35?"OK":"UNDERFILLED"); printf "Output  : visible rows %d/%d; thinking-only %d; errors %d\n", visible, rows, thinkonly, errors}' "$test_csv"
    else
      echo "Perf    : test CSV not found"
    fi
    if [[ -n "$hint_file" && -f "$hint_file" ]] && ! grep -q '^primary_error_class=none$' "$hint_file"; then
      awk -F= '/^(primary_error_class|api_error_rows|first_api_error|likely_cause|next_action)=/{v=$0; if(length(v)>160)v=substr(v,1,157)"..."; sub(/^primary_error_class=/,"Error   : class=",v); sub(/^api_error_rows=/,"Errors  : API rows=",v); sub(/^first_api_error=/,"API err : ",v); sub(/^likely_cause=/,"Likely  : ",v); sub(/^next_action=/,"Next    : ",v); print v}' "$hint_file" | head -5
    fi
    if [[ "$TEST_RC" -ne 0 ]]; then
      echo "Verdict : inference-health INCONCLUSIVE; monitor telemetry is not a completed-model-load benchmark"
    fi
    if [[ -n "$conc_csv" && -f "$conc_csv" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Conc    : x%s aggregate %.2f tok/s over %.2fs; ok=%s err=%s\n", unq($2), unq($6)+0, unq($3)+0, unq($7), unq($8)}' "$conc_csv"
    fi
    if [[ -n "$soak_csv" && -f "$soak_csv" ]]; then
      awk -F',' 'function unq(s){gsub(/^"|"$/, "", s); return s} NR==2{printf "Soak    : iterations=%s aggregate %.2f tok/s over %.1fs; errors=%s\n", unq($2), unq($5)+0, unq($3)+0, unq($6)}' "$soak_csv"
    fi
    if [[ -n "$monitor_csv" && -f "$monitor_csv" ]]; then
      awk -F',' -v temp_warn=83 -v temp_crit=88 -v vram_warn=90 -v busy_pct=85 -v busy_low_clock=1000 '
        function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
        function raw(name, pos){pos=h[name]; if(pos=="" || pos<1 || pos>NF) return ""; return trim($pos)}
        function num(name, s){s=raw(name); if(s=="" || s=="N/A" || s ~ /Not Supported|Unavailable|deprecated/) return ""; gsub(/ MiB| W| %| C| MHz/, "", s); return s+0}
        function active(v){return (v!="" && v!="N/A" && v !~ /Not Active|0x0000000000000000/)}
        NR==1{for(i=1;i<=NF;i++) h[trim($i)]=i; next}
        {n++; name=raw("name"); util=num("gpu_util_pct"); temp=num("temp_c"); power=num("power_w"); vram=num("vram_used_mib"); total=num("vram_total_mib"); pg=raw("pcie_gen_current"); pw=num("pcie_width_current"); pmw=num("pcie_width_max"); gfx=num("graphics_clock_mhz"); memtemp=raw("mem_temp_c"); hw=raw("throttle_hw_slowdown"); sw=raw("throttle_sw_power_cap"); sum_util+=util; if(util>max_util)max_util=util; if(temp>max_temp)max_temp=temp; if(power>max_power)max_power=power; if(vram>max_vram)max_vram=vram; if(total>0)last_total=total; last_pg=pg; last_pw=pw; last_pmw=pmw; if(temp>=temp_warn)tw++; if(temp>=temp_crit)tc++; if(total>0&&100*vram/total>=vram_warn)vh++; if(util>=busy_pct&&pw>0&&pmw>0&&pw<pmw)pcie_warn++; if(util>=busy_pct&&gfx>0&&gfx<busy_low_clock)lowclk++; if(active(hw))hwc++; if(active(sw))swc++; if(memtemp==""||memtemp=="N/A") memmiss++}
        END{pct=(last_total?100*max_vram/last_total:0); verdict="PASS"; if(tc>0||hwc>0)verdict="FAIL"; else if(tw>0||vh>0||swc>0||pcie_warn>0)verdict="PASS_WITH_CHECKS"; printf "Health  : %s; GPU samples %d avg-util %.1f%% max-util %.0f%%\n", verdict, n, (n?sum_util/n:0), max_util; printf "Thermal : max-temp %.0fC; max-power %.1fW; temp-warn=%d crit=%d\n", max_temp, max_power, tw, tc; printf "VRAM    : max-used %.0f MiB / %.0f MiB (%.1f%%); high=%d\n", max_vram, last_total, pct, vh; printf "PCIe    : gen %s; width x%s / max x%s; busy-width-checks=%d\n", last_pg, last_pw, last_pmw, pcie_warn; printf "Throttle: hw=%d sw_power=%d lowclk_obs=%d memtemp_NA=%d/%d\n", hwc, swc, lowclk, memmiss, n}' "$monitor_csv"
    else
      echo "GPU     : monitor CSV not found"
    fi
    echo "Tests:"
    if [[ -n "$test_csv" && -f "$test_csv" ]]; then
      awk -F',' '
        function unq(s){gsub(/^"|"$/, "", s); gsub(/""/, "\"", s); return s}
        NR==1{for(i=1;i<=NF;i++) h[unq($i)]=i; next}
        NR<=11{test=unq($(h["test"])); cat=unq($(h["category"])); ctx=unq($(h["num_ctx"])); prompt=unq($(h["prompt_eval_tokens"])); gen=unq($(h["gen_tps"])); done=unq($(h["done_reason"])); http=unq($(h["http_code"])); cls=unq($(h["error_class"])); if(gen!="")gen=sprintf("%.2f",gen); suffix=(cls!=""?"http="http" "cls:done); printf "  %-18s %-10s ctx=%-5s prompt=%-5s gen=%6s %s\n", test, cat, ctx, prompt, gen, suffix}
        NR==12{print "  ... additional rows omitted; see summary.csv"}' "$test_csv"
    fi
    echo "Files:"
    echo "  run : $RUN_DIR"
    echo "  hw  : $HARDWARE_ROOT"
    echo "  zip : ${ARCHIVE_PATH:-not-created}"
    echo "  md  : $SUMMARY_MD"
    echo "  test: ${test_summary:-not-found}"
    echo "  hint: ${hint_file:-not-found}"
    echo "  log : ${server_log_tail:-not-found}"
    echo "  mon : ${monitor_report:-not-found}"
    echo "============================================================"
  } >"$TERMINAL_SUMMARY"
}

make_summary() {
  local test_summary monitor_report test_csv monitor_csv conc_csv soak_csv hint_file server_log_tail
  test_summary="$(latest_file "$TEST_ROOT" summary.md)"
  monitor_report="$(latest_file "$MONITOR_ROOT" report.md)"
  test_csv="$(latest_file "$TEST_ROOT" summary.csv)"
  monitor_csv="$(latest_file "$MONITOR_ROOT" gpu.csv)"
  conc_csv="$(latest_file "$TEST_ROOT" concurrency-aggregate.csv)"
  soak_csv="$(latest_file "$TEST_ROOT" soak-summary.csv)"
  hint_file="$(latest_file "$TEST_ROOT" failure-hints.txt)"
  server_log_tail="$(latest_file "$TEST_ROOT" ollama-server-log-tail.txt)"
  {
    echo "# RTX 3090 Ollama Test + Monitor Orchestrator Summary"; echo
    echo "## Run metadata"
    echo "- script_version: $VERSION"
    echo "- signature: $SCRIPT_SIGNATURE"
    echo "- run_id: $RUN_ID"
    echo "- requested_model: ${MODEL_PATTERN:-$MODEL}"
    echo "- resolved_model: $MODEL"
    echo "- base_url: $BASE_URL"
    echo "- think: $THINK"
    echo "- run_dir: $RUN_DIR"
    echo "- test_exit_code: $TEST_RC"
    echo "- combined_archive: ${ARCHIVE_PATH:-pending}"; echo
    echo "## Compact terminal summary"; echo '```text'; if [[ -s "$TERMINAL_SUMMARY" ]]; then cat "$TERMINAL_SUMMARY"; else echo "terminal summary not generated"; fi; echo '```'; echo
    echo "## Detailed component files"
    echo "- test summary: ${test_summary:-not found}"
    echo "- failure hints: ${hint_file:-not found}"
    echo "- Ollama server log tail: ${server_log_tail:-not found}"
    echo "- test CSV: ${test_csv:-not found}"
    echo "- concurrency aggregate CSV: ${conc_csv:-not found}"
    echo "- soak aggregate CSV: ${soak_csv:-not found}"
    echo "- monitor report: ${monitor_report:-not found}"
    echo "- monitor GPU CSV: ${monitor_csv:-not found}"
    echo "- orchestrator NVIDIA start snapshot: $HARDWARE_ROOT/nvidia-smi-start.txt"
    echo "- orchestrator NVIDIA end snapshot: $HARDWARE_ROOT/nvidia-smi-end.txt"
    echo "- monitor console: $RUN_DIR/monitor.console.log"
    echo "- test console: $RUN_DIR/test.console.log"; echo
    echo "## Retention guidance"
    echo "Keep Markdown summaries for human review, CSV files for sortable metrics, raw JSON for exact Ollama API evidence, payload JSON for reproducibility, and gpu.csv for independent telemetry analysis. The orchestrator summary is intentionally compact and should not duplicate every nested report."
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
  else
    warn "zip is missing; cannot create combined archive"
  fi
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
  capture_nvidia_boundary end || true
  make_terminal_summary || true
  make_summary || true
  make_archive || true
}
trap 'TEST_RC=130; cleanup; exit 130' INT
trap 'TEST_RC=143; cleanup; exit 143' TERM
trap 'rc=$?; if [[ $rc -ne 0 ]]; then TEST_RC=$rc; fi; cleanup' EXIT

if [[ "$NO_MODEL_ARGS" == "1" ]]; then
  trap - EXIT INT TERM 2>/dev/null || true
  show_no_args_screen
  exit 2
fi
ensure_server
select_or_explain_model "$MODEL"

log "ollama-test-and-monitor-RTX3090.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Run dir: $RUN_DIR"
log "Plan: requested_model=${MODEL_PATTERN:-$MODEL} resolved_model=$MODEL think=$THINK ctx=$NUM_CTX long_ctx=$LONG_CTX long_prompt_words=$LONG_PROMPT_WORDS predict=$NUM_PREDICT long_predict=$LONG_NUM_PREDICT concurrency=$CONCURRENCY run_conc=$RUN_CONC run_cpu=$RUN_CPU soak_minutes=$SOAK_MINUTES run_vram_pressure=$RUN_VRAM_PRESSURE"
log "Monitor: interval=${INTERVAL}s profile=$MONITOR_PROFILE"
log "Capturing NVIDIA start snapshot..."
capture_nvidia_boundary start || true
log "Starting monitor..."

BASE_URL="$BASE_URL" OUT_DIR="$MONITOR_ROOT" TMP_DIR="$TMP_DIR" "$MONITOR_SCRIPT" --interval "$INTERVAL" --profile "$MONITOR_PROFILE" --run-id "$RUN_ID-monitor" --no-zip >"$RUN_DIR/monitor.console.log" 2>&1 &
MONITOR_PID="$!"
sleep 2

log "Running tests..."
TEST_ARGS=(
  --model "$MODEL" --base-url "$BASE_URL" --out-dir "$TEST_ROOT" --run-id "$RUN_ID-test"
  --num-ctx "$NUM_CTX" --long-ctx "$LONG_CTX" --num-predict "$NUM_PREDICT" --long-num-predict "$LONG_NUM_PREDICT" --long-prompt-words "$LONG_PROMPT_WORDS"
  --concurrency "$CONCURRENCY" --timeout-sec "$TIMEOUT_SEC" --think "$THINK" --soak-minutes "$SOAK_MINUTES" --soak-num-predict "$SOAK_NUM_PREDICT"
  --vram-ctx "$VRAM_CTX" --vram-num-predict "$VRAM_NUM_PREDICT"
  --no-terminal-summary --no-zip --no-ensure-server --server-log-lines "$SERVER_LOG_LINES"
)
[[ -n "$VRAM_MODEL" ]] && TEST_ARGS+=(--vram-model "$VRAM_MODEL")
[[ "$CAPTURE_WSL_DIAGNOSTICS" == "1" ]] || TEST_ARGS+=(--no-wsl-diagnostics)
[[ "$RUN_CONC" == "1" ]] && TEST_ARGS+=(--run-conc) || TEST_ARGS+=(--no-conc)
[[ "$RUN_CPU" == "1" ]] && TEST_ARGS+=(--run-cpu) || TEST_ARGS+=(--no-cpu)
[[ "$RUN_VRAM_PRESSURE" == "1" ]] && TEST_ARGS+=(--run-vram-pressure) || TEST_ARGS+=(--no-vram-pressure)
[[ "$PULL_IF_MISSING" == "1" ]] && TEST_ARGS+=(--pull) || TEST_ARGS+=(--no-pull)

set +e
BASE_URL="$BASE_URL" TMP_DIR="$TMP_DIR" "$TEST_SCRIPT" "${TEST_ARGS[@]}" 2>&1 | tee "$RUN_DIR/test.console.log"
TEST_RC=${PIPESTATUS[0]}
set -e

cleanup

if [[ "$PRINT_TERMINAL_SUMMARY" == "1" && -s "$TERMINAL_SUMMARY" ]]; then print_file_timestamped "$TERMINAL_SUMMARY"; else log "Summary: $SUMMARY_MD"; if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:     $ARCHIVE_PATH"; fi; log "Run dir: $RUN_DIR"; fi
exit "$TEST_RC"
