#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.5.0"
SCRIPT_SIGNATURE="OLLAMA_MONITOR_SCRIPT_SIGNATURE=v1.5.0-atomic-review-plain-summary"

INTERVAL="${INTERVAL:-3}"
DURATION="${DURATION:-0}"
PROFILE="${PROFILE:-normal}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-monitor}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
SNAPSHOT_EVERY="${SNAPSHOT_EVERY:-5}"
SNAPSHOT_EVERY_PROVIDED="${SNAPSHOT_EVERY_PROVIDED:-0}"
ZIP_ON_EXIT="${ZIP_ON_EXIT:-1}"

TEMP_WARN="${TEMP_WARN:-83}"
TEMP_CRIT="${TEMP_CRIT:-88}"
TEMP_SPIKE="${TEMP_SPIKE:-8}"
POWER_SPIKE="${POWER_SPIKE:-80}"
VRAM_WARN_PCT="${VRAM_WARN_PCT:-90}"
GPU_UTIL_BUSY_PCT="${GPU_UTIL_BUSY_PCT:-85}"
LOW_GPU_UTIL_PCT="${LOW_GPU_UTIL_PCT:-20}"
HIGH_POWER_LOW_UTIL_W="${HIGH_POWER_LOW_UTIL_W:-150}"
BUSY_LOW_CLOCK_MHZ="${BUSY_LOW_CLOCK_MHZ:-1000}"

RUN_DIR="$OUT_DIR/run-$RUN_ID"
CSV="$RUN_DIR/gpu.csv"
REPORT="$RUN_DIR/report.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
META="$RUN_DIR/meta.txt"
OLLAMA_PS_FILE="$RUN_DIR/ollama-ps.txt"
OLLAMA_API_PS_FILE="$RUN_DIR/ollama-api-ps.jsonl"
PROCESSES_FILE="$RUN_DIR/processes.tsv"
COMPUTE_APPS_FILE="$RUN_DIR/nvidia-compute-apps.csv"
NVIDIA_Q_START="$RUN_DIR/nvidia-smi-q-start.txt"
NVIDIA_Q_END="$RUN_DIR/nvidia-smi-q-end.txt"
DMESG_GPU_FILE="$RUN_DIR/dmesg-gpu-errors.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
ARCHIVE_PATH=""
STOP_REASON="completed"
FINALIZED=0
START_EPOCH="$(date +%s)"
STOP_EPOCH="$START_EPOCH"

usage() {
  cat <<EOF_USAGE
ollama-monitor.sh v$VERSION
$SCRIPT_SIGNATURE

Collect RTX 3090/NVIDIA + Ollama telemetry during local LLM runs, including whether inference actually exercised a loaded model, and create a report + zip archive.

Usage:
  ./ollama-monitor.sh [options]

Options:
  --interval N          Sampling interval in seconds (default: $INTERVAL)
  --duration N          Stop automatically after N seconds; 0 means until Ctrl+C (default: $DURATION)
  --profile NAME        brief|normal|deep. Controls snapshot frequency/field set (default: $PROFILE)
  --out-dir DIR         Root output dir (default: $OUT_DIR)
  --run-id ID           Override run id (default: timestamp)
  --base-url URL        Ollama base URL (default: $BASE_URL)
  --snapshot-every N    Capture Ollama/process snapshots every N GPU samples (default: $SNAPSHOT_EVERY)
  --zip                 Create ~/tmp zip archive on exit (default)
  --no-zip              Do not create zip archive on exit
  --self-test           Generate a synthetic report/archive without nvidia-smi
  -h, --help            Show help

Useful env thresholds:
  TEMP_WARN=$TEMP_WARN TEMP_CRIT=$TEMP_CRIT TEMP_SPIKE=$TEMP_SPIKE POWER_SPIKE=$POWER_SPIKE
  VRAM_WARN_PCT=$VRAM_WARN_PCT GPU_UTIL_BUSY_PCT=$GPU_UTIL_BUSY_PCT BUSY_LOW_CLOCK_MHZ=$BUSY_LOW_CLOCK_MHZ

Outputs per run:
  $RUN_DIR/
    gpu.csv, report.md, meta.txt, ollama-ps.txt, ollama-api-ps.jsonl,
    processes.tsv, nvidia-compute-apps.csv, nvidia-smi-q-start.txt, nvidia-smi-q-end.txt, dmesg-gpu-errors.txt, errors.log, archive.path
EOF_USAGE
}

log() { ollama_log "$*"; }
warn() { ollama_warn_to_file "$ERRORS_FILE" "$*"; }
need_cmd() { ollama_need_cmd "$1" || exit 2; }
is_uint() { ollama_is_uint "$1"; }
print_file_plain() { ollama_print_file_plain "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --duration) DURATION="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --profile) PROFILE="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --snapshot-every) SNAPSHOT_EVERY="$(ollama_require_arg_value "$1" "${2-}")"; SNAPSHOT_EVERY_PROVIDED=1; shift 2 ;;
    --zip) ZIP_ON_EXIT=1; shift ;;
    --no-zip) ZIP_ON_EXIT=0; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

is_uint "$INTERVAL" || { echo "ERROR: --interval must be an integer" >&2; exit 2; }
is_uint "$DURATION" || { echo "ERROR: --duration must be an integer" >&2; exit 2; }
is_uint "$SNAPSHOT_EVERY" || { echo "ERROR: --snapshot-every must be an integer" >&2; exit 2; }
[[ "$INTERVAL" -ge 1 ]] || { echo "ERROR: --interval must be >= 1" >&2; exit 2; }
[[ "$SNAPSHOT_EVERY" -ge 1 ]] || SNAPSHOT_EVERY=1

case "$PROFILE" in
  brief) if [[ "$SNAPSHOT_EVERY_PROVIDED" != "1" ]]; then SNAPSHOT_EVERY=10; fi ;;
  normal|deep) ;;
  *) echo "ERROR: --profile must be brief, normal, or deep" >&2; exit 2 ;;
esac

RUN_DIR="$OUT_DIR/run-$RUN_ID"
CSV="$RUN_DIR/gpu.csv"
REPORT="$RUN_DIR/report.md"
TERMINAL_SUMMARY="$RUN_DIR/terminal-summary.txt"
META="$RUN_DIR/meta.txt"
OLLAMA_PS_FILE="$RUN_DIR/ollama-ps.txt"
OLLAMA_API_PS_FILE="$RUN_DIR/ollama-api-ps.jsonl"
PROCESSES_FILE="$RUN_DIR/processes.tsv"
COMPUTE_APPS_FILE="$RUN_DIR/nvidia-compute-apps.csv"
NVIDIA_Q_START="$RUN_DIR/nvidia-smi-q-start.txt"
NVIDIA_Q_END="$RUN_DIR/nvidia-smi-q-end.txt"
DMESG_GPU_FILE="$RUN_DIR/dmesg-gpu-errors.txt"
ERRORS_FILE="$RUN_DIR/errors.log"
mkdir -p "$RUN_DIR" "$TMP_DIR"
: >"$ERRORS_FILE"

QUERY_DEEP="timestamp,index,name,temperature.gpu,temperature.memory,utilization.gpu,utilization.memory,memory.used,memory.total,memory.free,power.draw,power.limit,enforced.power.limit,clocks.gr,clocks.sm,clocks.mem,clocks.video,pstate,fan.speed,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,compute_mode,display_active,display_mode,clocks_throttle_reasons.active,clocks_throttle_reasons.gpu_idle,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.sw_power_cap,driver_version,vbios_version,pci.bus_id,uuid,utilization.encoder,utilization.decoder"
HEADERS_DEEP="timestamp,gpu_index,name,temp_c,mem_temp_c,gpu_util_pct,mem_util_pct,vram_used_mib,vram_total_mib,vram_free_mib,power_w,power_limit_w,enforced_power_limit_w,graphics_clock_mhz,sm_clock_mhz,mem_clock_mhz,video_clock_mhz,pstate,fan_pct,pcie_gen_current,pcie_width_current,pcie_gen_max,pcie_width_max,compute_mode,display_active,display_mode,throttle_active,throttle_gpu_idle,throttle_hw_slowdown,throttle_sw_power_cap,driver_version,vbios_version,pci_bus_id,uuid,enc_util_pct,dec_util_pct"
QUERY_NORMAL="timestamp,index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,memory.free,power.draw,power.limit,enforced.power.limit,clocks.gr,clocks.sm,clocks.mem,pstate,fan.speed,pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max,display_active,clocks_throttle_reasons.active,clocks_throttle_reasons.gpu_idle,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.sw_power_cap,driver_version,pci.bus_id,uuid"
HEADERS_NORMAL="timestamp,gpu_index,name,temp_c,gpu_util_pct,mem_util_pct,vram_used_mib,vram_total_mib,vram_free_mib,power_w,power_limit_w,enforced_power_limit_w,graphics_clock_mhz,sm_clock_mhz,mem_clock_mhz,pstate,fan_pct,pcie_gen_current,pcie_width_current,pcie_gen_max,pcie_width_max,display_active,throttle_active,throttle_gpu_idle,throttle_hw_slowdown,throttle_sw_power_cap,driver_version,pci_bus_id,uuid"
QUERY_BASE="timestamp,index,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,clocks.gr,clocks.mem,driver_version,pci.bus_id,uuid"
HEADERS_BASE="timestamp,gpu_index,name,temp_c,gpu_util_pct,mem_util_pct,vram_used_mib,vram_total_mib,power_w,graphics_clock_mhz,mem_clock_mhz,driver_version,pci_bus_id,uuid"
QUERY=""
QUERY_HEADERS=""

choose_query() {
  local q h
  if [[ "${SELF_TEST:-0}" == "1" ]]; then
    QUERY="$QUERY_DEEP"; QUERY_HEADERS="$HEADERS_DEEP"; return 0
  fi
  need_cmd nvidia-smi
  for pair in deep normal base; do
    case "$pair" in
      deep) q="$QUERY_DEEP"; h="$HEADERS_DEEP" ;;
      normal) q="$QUERY_NORMAL"; h="$HEADERS_NORMAL" ;;
      base) q="$QUERY_BASE"; h="$HEADERS_BASE" ;;
    esac
    if [[ "$PROFILE" == "brief" && "$pair" == "deep" ]]; then
      continue
    fi
    if nvidia-smi --query-gpu="$q" --format=csv,noheader,nounits >/dev/null 2>&1; then
      QUERY="$q"; QUERY_HEADERS="$h"; return 0
    fi
  done
  echo "ERROR: nvidia-smi query failed even with base field set" >&2
  exit 3
}

write_meta() {
  {
    echo "script_name=ollama-monitor.sh"
    echo "version=$VERSION"
    echo "signature=$SCRIPT_SIGNATURE"
    echo "run_id=$RUN_ID"
    echo "run_dir=$RUN_DIR"
    echo "start_time=$(date -Is)"
    echo "interval_sec=$INTERVAL"
    echo "duration_sec=$DURATION"
    echo "profile=$PROFILE"
    echo "base_url=$BASE_URL"
    echo "zip_on_exit=$ZIP_ON_EXIT"
    echo "temp_warn_c=$TEMP_WARN"
    echo "temp_crit_c=$TEMP_CRIT"
    echo "temp_spike_c=$TEMP_SPIKE"
    echo "power_spike_w=$POWER_SPIKE"
    echo "vram_warn_pct=$VRAM_WARN_PCT"
    echo "gpu_util_busy_pct=$GPU_UTIL_BUSY_PCT"
    echo "high_power_low_util_w=$HIGH_POWER_LOW_UTIL_W"
    echo "low_gpu_util_pct=$LOW_GPU_UTIL_PCT"
    echo "busy_low_clock_mhz=$BUSY_LOW_CLOCK_MHZ"
    echo "snapshot_every=$SNAPSHOT_EVERY"
    echo "query_fields=$QUERY"
    echo "query_headers=$QUERY_HEADERS"
    echo
    echo "## environment"
    date -Is
    uname -a || true
    if command -v lsb_release >/dev/null 2>&1; then lsb_release -ds || true; fi
    echo
    echo "## executable resolution"
    command -v ollama-monitor.sh || true
    type ollama-monitor.sh 2>/dev/null || true
    echo
    echo "## nvidia-smi -L"
    nvidia-smi -L 2>&1 || true
    echo
    echo "## nvidia-smi summary"
    nvidia-smi 2>&1 || true
    echo
    echo "## memory"
    free -h 2>&1 || true
    echo
    echo "## disk"
    df -h "$HOME" 2>&1 || true
    echo
    echo "## ollama version"
    ollama --version 2>&1 || true
    echo
    echo "## curl"
    command -v curl || true
    echo
    echo "## jq"
    command -v jq || true
  } >"$META"
}

snapshot_runtime() {
  local ts
  ts="$(date -Is)"
  {
    echo "--- $ts"
    if command -v ollama >/dev/null 2>&1; then
      ollama ps 2>&1 || true
    else
      echo "ollama CLI not found"
    fi
  } >>"$OLLAMA_PS_FILE"

  if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    curl -fsS "$BASE_URL/api/ps" 2>/dev/null \
      | jq -c --arg ts "$ts" '{timestamp:$ts, api_ps:.}' >>"$OLLAMA_API_PS_FILE" \
      || printf '{"timestamp":"%s","error":"api_ps_unavailable"}\n' "$ts" >>"$OLLAMA_API_PS_FILE"
  else
    printf '{"timestamp":"%s","error":"curl_or_jq_missing"}\n' "$ts" >>"$OLLAMA_API_PS_FILE"
  fi

  if [[ ! -s "$PROCESSES_FILE" ]]; then
    printf 'timestamp\tpid\tppid\tcpu_pct\tmem_pct\trss_kb\tstat\tetime\targs\n' >"$PROCESSES_FILE"
  fi
  ps -eo pid=,ppid=,pcpu=,pmem=,rss=,stat=,etime=,args= \
    | awk -v ts="$ts" '/[o]llama|[c]uda|[n]vidia-smi/ {printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t", ts,$1,$2,$3,$4,$5,$6,$7; for(i=8;i<=NF;i++) printf "%s%s", $i, (i<NF?OFS:ORS)}' \
    >>"$PROCESSES_FILE" 2>/dev/null || true

  if command -v nvidia-smi >/dev/null 2>&1; then
    if [[ ! -s "$COMPUTE_APPS_FILE" ]]; then
      printf 'timestamp,pid,process_name,used_gpu_memory_mib\n' >"$COMPUTE_APPS_FILE"
    fi
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null \
      | awk -v ts="$ts" 'BEGIN{FS=","; OFS=","} NF>=1 {gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3); print ts,$1,$2,$3}' \
      >>"$COMPUTE_APPS_FILE" || true
  fi
}



capture_static_snapshot() {
  local label="$1" out
  case "$label" in
    start) out="$NVIDIA_Q_START" ;;
    end) out="$NVIDIA_Q_END" ;;
    *) out="$RUN_DIR/nvidia-smi-q-$label.txt" ;;
  esac
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi -q -d POWER,TEMPERATURE,CLOCK,PERFORMANCE,PCI,MEMORY,UTILIZATION >"$out" 2>&1 || true
  else
    echo "nvidia-smi not found" >"$out"
  fi
}

capture_gpu_error_scan() {
  {
    echo "# dmesg GPU/error scan"
    echo "timestamp=$(date -Is)"
    if command -v dmesg >/dev/null 2>&1; then
      dmesg -T 2>&1 | grep -Ei 'nvrm|xid|cuda|gpu|dxg|wsl|nvidia' || true
    else
      echo "dmesg not found"
    fi
  } >"$DMESG_GPU_FILE"
}

ollama_loaded_snapshot_count() {
  [[ -s "$OLLAMA_PS_FILE" ]] || { echo 0; return 0; }
  awk '
    /^[[:space:]]*$/ {next}
    /^--- / {next}
    /^NAME[[:space:]]/ {next}
    /ollama CLI not found/ {next}
    /Error:/ {next}
    {n++}
    END{print n+0}
  ' "$OLLAMA_PS_FILE" 2>/dev/null || echo 0
}

ollama_api_loaded_snapshot_count() {
  [[ -s "$OLLAMA_API_PS_FILE" ]] || { echo 0; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -s '[.[] | (.api_ps.models? // []) | length] | add // 0' "$OLLAMA_API_PS_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

compute_app_snapshot_count() {
  [[ -s "$COMPUTE_APPS_FILE" ]] || { echo 0; return 0; }
  awk -F',' 'NR>1 && $2 != "" && $2 !~ /No running/ {n++} END{print n+0}' "$COMPUTE_APPS_FILE" 2>/dev/null || echo 0
}

make_archive() {
  [[ "$ZIP_ON_EXIT" == "1" ]] || return 0
  mkdir -p "$TMP_DIR"
  [[ -n "${ARCHIVE_PATH:-}" ]] || ARCHIVE_PATH="$TMP_DIR/ollama-monitor-$RUN_ID.zip"
  printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  rm -f "$ARCHIVE_PATH"
  if command -v zip >/dev/null 2>&1; then
    (cd "$OUT_DIR" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  else
    warn "zip is missing; cannot create archive"
    return 0
  fi
}

generate_report() {
  STOP_EPOCH="$(date +%s)"
  local elapsed=$((STOP_EPOCH - START_EPOCH))
  local loaded_cli loaded_api compute_apps exercise_verdict
  loaded_cli="$(ollama_loaded_snapshot_count)"
  loaded_api="$(ollama_api_loaded_snapshot_count)"
  compute_apps="$(compute_app_snapshot_count)"
  if [[ "$loaded_cli" -gt 0 || "$loaded_api" -gt 0 ]]; then
    exercise_verdict="model_load_observed"
  elif [[ "$compute_apps" -gt 0 ]]; then
    exercise_verdict="gpu_compute_process_observed_no_ollama_model_snapshot"
  else
    exercise_verdict="no_model_load_observed"
  fi
  {
    echo "# Ollama GPU Monitor Report"
    echo
    echo "## Run metadata"
    echo "- script_version: $VERSION"
    echo "- signature: $SCRIPT_SIGNATURE"
    echo "- run_id: $RUN_ID"
    echo "- stop_reason: $STOP_REASON"
    echo "- elapsed_wall_sec: $elapsed"
    echo "- csv: $CSV"
    echo "- interval_sec: $INTERVAL"
    echo "- profile: $PROFILE"
    echo "- archive: ${ARCHIVE_PATH:-pending}"
    echo "- temp_warn_c: $TEMP_WARN"
    echo "- temp_crit_c: $TEMP_CRIT"
    echo "- temp_spike_c: $TEMP_SPIKE"
    echo "- power_spike_w: $POWER_SPIKE"
    echo "- vram_warn_pct: $VRAM_WARN_PCT"
    echo

    echo "## Diagnostic verdicts"
    awk -F',' \
      -v temp_warn="$TEMP_WARN" -v temp_crit="$TEMP_CRIT" -v vram_warn="$VRAM_WARN_PCT" -v busy_pct="$GPU_UTIL_BUSY_PCT" -v busy_low_clock="$BUSY_LOW_CLOCK_MHZ" '
      function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
      function raw(name, pos){pos=idx[name]; if(pos=="" || pos<1 || pos>NF) return ""; return trim($pos)}
      function num(name, s){s=raw(name); if(s=="" || s=="N/A" || s ~ /Not Supported|Unavailable|deprecated/) return ""; gsub(/ MiB| W| %| C| MHz/, "", s); return s+0}
      function active(v){return (v!="" && v!="N/A" && v !~ /Not Active|0x0000000000000000/)}
      NR==1{for(i=1;i<=NF;i++)idx[trim($i)]=i; next}
      {n++; gpu=num("gpu_util_pct"); temp=num("temp_c"); memtemp=raw("mem_temp_c"); vram=num("vram_used_mib"); total=num("vram_total_mib"); power=num("power_w"); pcie=num("pcie_width_current"); pmax=num("pcie_width_max"); gfx=num("graphics_clock_mhz"); hw=raw("throttle_hw_slowdown"); sw=raw("throttle_sw_power_cap"); if(temp>max_temp)max_temp=temp; if(power>max_power)max_power=power; if(total>0 && vram>0){last_total=total; if(vram>max_vram)max_vram=vram}; if(memtemp=="" || memtemp=="N/A") memtemp_missing++; if(temp>=temp_warn)tw++; if(temp>=temp_crit)tc++; if(total>0 && 100*vram/total>=vram_warn)vh++; if(active(hw)) hwc++; if(active(sw)) swc++; if(gpu>=busy_pct && pcie>0 && pmax>0 && pcie<pmax) pcie_warn++; if(gpu>=busy_pct && gfx>0 && gfx<busy_low_clock) lowclk++}
      END{status="PASS"; if(tc>0||hwc>0)status="FAIL"; else if(tw>0||vh>0||swc>0||pcie_warn>0)status="PASS_WITH_CHECKS"; printf "- health_verdict: %s\n", status; printf "- temperature: max=%.0fC warn_samples=%d critical_samples=%d\n", max_temp, tw, tc; printf "- power: max=%.1fW sw_power_cap_samples=%d hw_slowdown_samples=%d\n", max_power, swc, hwc; printf "- vram: max=%.0f MiB total=%.0f MiB high_samples=%d\n", max_vram, last_total, vh; printf "- pcie: busy_width_below_max_samples=%d\n", pcie_warn; printf "- low_clock_observation_samples=%d\n", lowclk; printf "- memory_temperature_unavailable_samples=%d/%d\n", memtemp_missing, n; if(memtemp_missing>0) print "- note: RTX 3090 GDDR6X memory junction temperature may be unavailable in WSL2 nvidia-smi output."}' "$CSV"
    echo
    echo "## Inference exercise coverage"
    echo "- verdict: $exercise_verdict"
    echo "- ollama_cli_loaded_model_rows: $loaded_cli"
    echo "- ollama_api_loaded_model_rows: $loaded_api"
    echo "- nvidia_compute_app_rows: $compute_apps"
    if [[ "$loaded_cli" -eq 0 && "$loaded_api" -eq 0 ]]; then
      echo "- note: no Ollama-loaded model snapshot was observed; thermal/power/PCIe health may describe idle or failed-load telemetry, not completed inference stability."
    fi
    echo

    awk -F',' \
      -v sample_interval="$INTERVAL" \
      -v temp_warn="$TEMP_WARN" \
      -v temp_crit="$TEMP_CRIT" \
      -v temp_spike="$TEMP_SPIKE" \
      -v power_spike="$POWER_SPIKE" \
      -v vram_warn="$VRAM_WARN_PCT" \
      -v busy_pct="$GPU_UTIL_BUSY_PCT" \
      -v low_gpu_util="$LOW_GPU_UTIL_PCT" \
      -v high_power_low_util="$HIGH_POWER_LOW_UTIL_W" \
      -v busy_low_clock="$BUSY_LOW_CLOCK_MHZ" '
      function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
      function raw(name,    pos){pos=idx[name]; if(pos=="" || pos<1 || pos>NF) return ""; return trim($pos)}
      function numeric(name,    s){s=raw(name); if(s=="" || s=="N/A" || s ~ /Not Supported|Unavailable|deprecated|\[N\/A\]/) return ""; gsub(/ MiB| W| %| C| MHz/, "", s); return s+0}
      function add_metric(key, value, ts){
        if(value=="") return
        metric_count[key]++
        metric_sum[key]+=value
        if(metric_count[key]==1 || value<metric_min[key]) metric_min[key]=value
        if(metric_count[key]==1 || value>metric_max[key]) {metric_max[key]=value; metric_maxts[key]=ts}
      }
      function print_metric(key, label, fmt,    avg){
        if(metric_count[key]<1) return
        avg=metric_sum[key]/metric_count[key]
        printf "| %s | " fmt " | " fmt " | " fmt " | %s |\n", label, avg, metric_min[key], metric_max[key], metric_maxts[key]
      }
      NR==1 {
        for(i=1;i<=NF;i++){idx[trim($i)]=i}
        next
      }
      NF>=4 {
        ts=raw("timestamp")
        if(ts=="") next
        n++
        if(n==1){first_ts=ts; gpu_name=raw("name"); gpu_index=raw("gpu_index"); vram_total_first=numeric("vram_total_mib")}
        last_ts=ts
        gpu=numeric("gpu_util_pct")
        mem=numeric("mem_util_pct")
        temp=numeric("temp_c")
        memtemp=numeric("mem_temp_c")
        power=numeric("power_w")
        vram=numeric("vram_used_mib")
        vram_total=numeric("vram_total_mib")
        vram_free=numeric("vram_free_mib")
        gfx=numeric("graphics_clock_mhz")
        sm=numeric("sm_clock_mhz")
        memclk=numeric("mem_clock_mhz")
        vidclk=numeric("video_clock_mhz")
        pcie_gen=numeric("pcie_gen_current")
        pcie_max_gen=numeric("pcie_gen_max")
        pcie_width=numeric("pcie_width_current")
        pcie_max_width=numeric("pcie_width_max")
        fan=numeric("fan_pct")

        add_metric("gpu",gpu,ts); add_metric("mem",mem,ts); add_metric("temp",temp,ts); add_metric("memtemp",memtemp,ts)
        add_metric("power",power,ts); add_metric("vram",vram,ts); add_metric("vram_total",vram_total,ts); add_metric("vram_free",vram_free,ts)
        add_metric("gfx",gfx,ts); add_metric("sm",sm,ts); add_metric("memclk",memclk,ts); add_metric("vidclk",vidclk,ts)
        add_metric("pcie_gen",pcie_gen,ts); add_metric("pcie_max_gen",pcie_max_gen,ts); add_metric("pcie_width",pcie_width,ts); add_metric("pcie_max_width",pcie_max_width,ts); add_metric("fan",fan,ts)
        if(power!="") energy_wh += power * sample_interval / 3600.0

        if(gpu!="" && gpu>=busy_pct) busy_samples++
        if(temp!="" && temp>=temp_warn) {temp_warn_samples++; if(temp_warn_lines<20) temp_warn_line[++temp_warn_lines]=ts " temp=" temp "C gpu=" gpu "% power=" power "W"}
        if(temp!="" && temp>=temp_crit) {temp_crit_samples++; if(temp_crit_lines<20) temp_crit_line[++temp_crit_lines]=ts " temp=" temp "C gpu=" gpu "% power=" power "W"}
        if(vram!="" && vram_total!="" && vram_total>0 && (100*vram/vram_total)>=vram_warn) {vram_high_samples++; if(vram_high_lines<20) vram_high_line[++vram_high_lines]=ts " vram=" vram "/" vram_total " MiB"}
        if(gpu!="" && power!="" && gpu<low_gpu_util && power>=high_power_low_util) {low_util_high_power_samples++; if(low_util_high_power_lines<20) low_util_high_power_line[++low_util_high_power_lines]=ts " gpu=" gpu "% power=" power "W"}
        if(gpu!="" && gfx!="" && gpu>=busy_pct && gfx<busy_low_clock) {busy_low_clock_samples++; if(busy_low_clock_lines<20) busy_low_clock_line[++busy_low_clock_lines]=ts " gpu=" gpu "% graphics_clock=" gfx "MHz"}
        if(gpu!="" && pcie_width!="" && pcie_max_width!="" && gpu>=busy_pct && pcie_width<pcie_max_width) {pcie_busy_warn_samples++; if(pcie_busy_warn_lines<20) pcie_busy_warn_line[++pcie_busy_warn_lines]=ts " busy_gpu=" gpu "% pcie_width_current=x" pcie_width " max=x" pcie_max_width}

        if(prev_ts!="") {
          if(temp!="" && prev_temp!="" && (temp-prev_temp)>=temp_spike && temp_spike_lines<20) temp_spike_line[++temp_spike_lines]=prev_ts " -> " ts " +" (temp-prev_temp) "C (" prev_temp "C -> " temp "C)"
          if(power!="" && prev_power!="" && (power-prev_power)>=power_spike && power_spike_lines<20) power_spike_line[++power_spike_lines]=prev_ts " -> " ts " +" sprintf("%.1f", power-prev_power) "W (" prev_power "W -> " power "W)"
          if(gpu!="" && prev_gpu!="" && (prev_gpu-gpu)>=50 && gpu_drop_lines<20) gpu_drop_line[++gpu_drop_lines]=prev_ts " -> " ts " -" (prev_gpu-gpu) " GPU-util-points (" prev_gpu "% -> " gpu "%)"
        }
        prev_ts=ts; prev_temp=temp; prev_power=power; prev_gpu=gpu
      }
      END {
        print "## GPU telemetry summary"
        if(n<1){print "- No GPU samples captured."; exit}
        printf "- gpu_name: %s\n- gpu_index: %s\n- samples: %d\n- approx_duration_sec: %.1f\n- first_sample: %s\n- last_sample: %s\n- estimated_gpu_energy_wh: %.3f\n\n", gpu_name, gpu_index, n, n*sample_interval, first_ts, last_ts, energy_wh
        print "| Metric | Avg | Min | Max | Max at |"
        print "|---|---:|---:|---:|---|"
        print_metric("gpu", "GPU utilization %", "%.2f")
        print_metric("mem", "Memory-controller utilization %", "%.2f")
        print_metric("temp", "GPU temperature C", "%.2f")
        print_metric("memtemp", "Memory junction temperature C", "%.2f")
        print_metric("power", "Power W", "%.2f")
        print_metric("vram", "VRAM used MiB", "%.2f")
        print_metric("vram_free", "VRAM free MiB", "%.2f")
        print_metric("vram_total", "VRAM total MiB", "%.2f")
        print_metric("gfx", "Graphics clock MHz", "%.2f")
        print_metric("sm", "SM clock MHz", "%.2f")
        print_metric("memclk", "Memory clock MHz", "%.2f")
        print_metric("vidclk", "Video clock MHz", "%.2f")
        print_metric("fan", "Fan %", "%.2f")
        print_metric("pcie_gen", "PCIe current gen", "%.2f")
        print_metric("pcie_max_gen", "PCIe max gen", "%.2f")
        print_metric("pcie_width", "PCIe current width", "%.2f")
        print_metric("pcie_max_width", "PCIe max width", "%.2f")
        print ""
        print "## Diagnostic flags"
        printf "- busy_samples_ge_%s_pct: %d/%d\n", busy_pct, busy_samples, n
        printf "- temp_warning_samples_ge_%s_c: %d\n", temp_warn, temp_warn_samples
        printf "- temp_critical_samples_ge_%s_c: %d\n", temp_crit, temp_crit_samples
        printf "- vram_high_samples_ge_%s_pct: %d\n", vram_warn, vram_high_samples
        printf "- low_gpu_util_high_power_samples: %d\n", low_util_high_power_samples
        printf "- busy_low_graphics_clock_samples: %d\n", busy_low_clock_samples
        printf "- pcie_link_warnings_while_busy: %d\n", pcie_busy_warn_samples
        print ""
        print "## Temperature warning samples"; if(temp_warn_lines<1) print "- none"; else for(i=1;i<=temp_warn_lines;i++) print "- " temp_warn_line[i]
        print "\n## Temperature critical samples"; if(temp_crit_lines<1) print "- none"; else for(i=1;i<=temp_crit_lines;i++) print "- " temp_crit_line[i]
        print "\n## Temperature spikes"; if(temp_spike_lines<1) print "- none"; else for(i=1;i<=temp_spike_lines;i++) print "- " temp_spike_line[i]
        print "\n## Power spikes"; if(power_spike_lines<1) print "- none"; else for(i=1;i<=power_spike_lines;i++) print "- " power_spike_line[i]
        print "\n## Large GPU utilization drops"; if(gpu_drop_lines<1) print "- none"; else for(i=1;i<=gpu_drop_lines;i++) print "- " gpu_drop_line[i]
        print "\n## High VRAM samples"; if(vram_high_lines<1) print "- none"; else for(i=1;i<=vram_high_lines;i++) print "- " vram_high_line[i]
        print "\n## Low GPU utilization + high power samples"; if(low_util_high_power_lines<1) print "- none"; else for(i=1;i<=low_util_high_power_lines;i++) print "- " low_util_high_power_line[i]
        print "\n## Busy GPU + low graphics clock samples"; if(busy_low_clock_lines<1) print "- none"; else for(i=1;i<=busy_low_clock_lines;i++) print "- " busy_low_clock_line[i]
        print "\n## PCIe link warnings while GPU is busy"; if(pcie_busy_warn_lines<1) print "- none"; else for(i=1;i<=pcie_busy_warn_lines;i++) print "- " pcie_busy_warn_line[i]
      }' "$CSV"

    echo
    echo "## Ollama loaded-model snapshots"
    echo '```text'
    if [[ -s "$OLLAMA_PS_FILE" ]]; then cat "$OLLAMA_PS_FILE"; else echo "none"; fi
    echo '```'
    echo
    echo "## NVIDIA compute-process snapshots"
    echo '```csv'
    if [[ -s "$COMPUTE_APPS_FILE" ]]; then cat "$COMPUTE_APPS_FILE"; else echo "none"; fi
    echo '```'
    echo
    echo "## Process snapshots"
    echo '```text'
    if [[ -s "$PROCESSES_FILE" ]]; then cat "$PROCESSES_FILE"; else echo "none"; fi
    echo '```'
    echo
    echo "## Error log"
    echo '```text'
    if [[ -s "$ERRORS_FILE" ]]; then cat "$ERRORS_FILE"; else echo "none"; fi
    echo '```'
    echo
    echo "## Raw GPU CSV tail"
    echo '```csv'
    tail -n 25 "$CSV" 2>/dev/null || true
    echo '```'
    echo
    echo "## nvidia-smi -q start snapshot"
    echo '```text'
    sed -n '1,220p' "$NVIDIA_Q_START" 2>/dev/null || true
    echo '```'
    echo
    echo "## nvidia-smi -q end snapshot"
    echo '```text'
    sed -n '1,220p' "$NVIDIA_Q_END" 2>/dev/null || true
    echo '```'
    echo
    echo "## dmesg GPU/error scan"
    echo '```text'
    cat "$DMESG_GPU_FILE" 2>/dev/null || true
    echo '```'
    echo
    echo "## Meta snapshot"
    echo '```text'
    cat "$META" 2>/dev/null || true
    echo '```'
  } >"$REPORT"
}


make_terminal_summary() {
  {
    echo "============================================================"
    echo "RTX3090 OLLAMA MONITOR SUMMARY"
    echo "Run ID  : $RUN_ID"
    echo "Reason  : $STOP_REASON"
    if [[ -s "$CSV" ]]; then
      awk -F',' -v temp_warn="$TEMP_WARN" -v temp_crit="$TEMP_CRIT" -v vram_warn="$VRAM_WARN_PCT" -v busy_pct="$GPU_UTIL_BUSY_PCT" -v busy_low_clock="$BUSY_LOW_CLOCK_MHZ" '
        function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
        function raw(name, pos){pos=h[name]; if(pos=="" || pos<1 || pos>NF) return ""; return trim($pos)}
        function num(name, s){s=raw(name); if(s=="" || s=="N/A" || s ~ /Not Supported|Unavailable|deprecated/) return ""; gsub(/ MiB| W| %| C| MHz/, "", s); return s+0}
        function active(v){return (v!="" && v!="N/A" && v !~ /Not Active|0x0000000000000000/)}
        NR==1{for(i=1;i<=NF;i++) h[trim($i)]=i; next}
        {n++; name=raw("name"); util=num("gpu_util_pct"); temp=num("temp_c"); power=num("power_w"); vram=num("vram_used_mib"); total=num("vram_total_mib"); pg=raw("pcie_gen_current"); pw=num("pcie_width_current"); pmw=num("pcie_width_max"); gfx=num("graphics_clock_mhz"); memtemp=raw("mem_temp_c"); hw=raw("throttle_hw_slowdown"); sw=raw("throttle_sw_power_cap"); sum_util+=util; if(util>max_util)max_util=util; if(temp>max_temp)max_temp=temp; if(power>max_power)max_power=power; if(vram>max_vram)max_vram=vram; if(total>0)last_total=total; last_pg=pg; last_pw=pw; last_pmw=pmw; if(temp>=temp_warn)tw++; if(temp>=temp_crit)tc++; if(total>0&&100*vram/total>=vram_warn)vh++; if(util>=busy_pct&&pw>0&&pmw>0&&pw<pmw)pcie_warn++; if(util>=busy_pct&&gfx>0&&gfx<busy_low_clock)lowclk++; if(active(hw))hwc++; if(active(sw))swc++; if(memtemp==""||memtemp=="N/A") memmiss++}
        END{pct=(last_total?100*max_vram/last_total:0); verdict="PASS"; if(tc>0||hwc>0)verdict="FAIL"; else if(tw>0||vh>0||swc>0||pcie_warn>0)verdict="PASS_WITH_CHECKS"; printf "Health  : %s\n", verdict; printf "GPU     : %s; samples %d; avg-util %.1f%%; max-util %.0f%%\n", name, n, (n?sum_util/n:0), max_util; printf "Thermal : max-temp %.0fC; max-power %.1fW; temp-warn=%d crit=%d\n", max_temp, max_power, tw, tc; printf "VRAM    : max-used %.0f MiB / %.0f MiB (%.1f%%); high=%d\n", max_vram, last_total, pct, vh; printf "PCIe    : gen %s; width x%s / max x%s; busy-width-checks=%d\n", last_pg, last_pw, last_pmw, pcie_warn; printf "Throttle: hw_slowdown=%d sw_power_cap=%d; lowclk_obs=%d; memtemp_NA=%d/%d\n", hwc, swc, lowclk, memmiss, n}' "$CSV"
    else
      echo "GPU     : no CSV samples"
    fi
    if [[ -s "$OLLAMA_PS_FILE" || -s "$OLLAMA_API_PS_FILE" ]]; then
      loaded_cli="$(ollama_loaded_snapshot_count)"; loaded_api="$(ollama_api_loaded_snapshot_count)"; compute_apps="$(compute_app_snapshot_count)"
      if [[ "$loaded_cli" -gt 0 || "$loaded_api" -gt 0 ]]; then ex="model-load-seen"; else ex="no-model-load-seen"; fi
      echo "Exercise: $ex; ollama_cli_rows=$loaded_cli api_rows=$loaded_api compute_rows=$compute_apps"
      if [[ "$loaded_cli" -eq 0 && "$loaded_api" -eq 0 ]]; then echo "Note    : inference health is inconclusive without loaded-model snapshots"; fi
    fi
    echo "Files:"
    echo "  run : $RUN_DIR"
    echo "  md  : $REPORT"
    echo "  csv : $CSV"
    if [[ -n "${ARCHIVE_PATH:-}" ]]; then echo "  zip : $ARCHIVE_PATH"; fi
    echo "============================================================"
  } >"$TERMINAL_SUMMARY"
}

finish() {
  [[ "$FINALIZED" == "1" ]] && return 0
  FINALIZED=1
  log "Stopping monitor..."
  capture_static_snapshot end || true
  capture_gpu_error_scan || true
  if [[ "$ZIP_ON_EXIT" == "1" ]]; then
    ARCHIVE_PATH="$TMP_DIR/ollama-monitor-$RUN_ID.zip"
    printf '%s\n' "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  fi
  generate_report || warn "report generation failed"
  make_terminal_summary || warn "terminal summary generation failed"
  make_archive || warn "archive creation failed"
  if [[ -s "$TERMINAL_SUMMARY" ]]; then
    print_file_plain "$TERMINAL_SUMMARY"
  else
    log "Report: $REPORT"
    log "CSV:    $CSV"
    if [[ -n "${ARCHIVE_PATH:-}" ]]; then log "ZIP:    $ARCHIVE_PATH"; fi
    log "Run dir: $RUN_DIR"
  fi
}

run_self_test() {
  STOP_REASON="self-test"
  QUERY="$QUERY_DEEP"
  QUERY_HEADERS="$HEADERS_DEEP"
  printf '%s\n' "$QUERY_HEADERS" >"$CSV"
  cat >>"$CSV" <<'EOF_CSV'
2026/05/23 18:49:24.691,0,NVIDIA GeForce RTX 3090,34,N/A,21,16,7390,24576,16937,33.71,350.00,350.00,210,210,405,555,P8,30,3,8,3,16,Default,Enabled,N/A,0x1,Active,Not Active,Not Active,596.36,94.02.59.00.d6,00000000:BD:00.0,GPU-test,0,0
2026/05/23 18:49:37.599,0,NVIDIA GeForce RTX 3090,38,N/A,85,68,7392,24576,16935,141.26,350.00,350.00,780,780,5001,780,P3,30,3,8,3,16,Default,Enabled,N/A,0x1,Active,Not Active,Not Active,596.36,94.02.59.00.d6,00000000:BD:00.0,GPU-test,0,0
2026/05/23 18:50:03.424,0,NVIDIA GeForce RTX 3090,39,N/A,86,69,7393,24576,16934,103.85,350.00,350.00,780,780,5001,780,P3,30,3,8,3,16,Default,Enabled,N/A,0x1,Active,Not Active,Not Active,596.36,94.02.59.00.d6,00000000:BD:00.0,GPU-test,0,0
EOF_CSV
  write_meta
  capture_static_snapshot start || true
  snapshot_runtime || true
  finish
  grep -q "GPU telemetry summary" "$REPORT"
  grep -q "PCIe link warnings" "$REPORT"
}

trap 'STOP_REASON="interrupted"; finish; exit 130' INT
trap 'STOP_REASON="terminated"; finish; exit 143' TERM
trap 'rc=$?; if [[ $rc -ne 0 && "$FINALIZED" != "1" ]]; then STOP_REASON="error-$rc"; finish; fi' EXIT

choose_query

if [[ "${SELF_TEST:-0}" == "1" ]]; then
  run_self_test
  exit 0
fi

need_cmd nvidia-smi
printf '%s\n' "$QUERY_HEADERS" >"$CSV"
write_meta
capture_static_snapshot start || true
snapshot_runtime || true

log "ollama-monitor.sh v$VERSION"
log "$SCRIPT_SIGNATURE"
log "Monitoring GPU every ${INTERVAL}s. Press Ctrl+C to stop."
log "Run dir: $RUN_DIR"
log "CSV: $CSV"
log "Report will be generated at: $REPORT"
[[ "$ZIP_ON_EXIT" == "1" ]] && log "ZIP will be generated under: $TMP_DIR"

sample_no=0
while true; do
  if ! nvidia-smi --query-gpu="$QUERY" --format=csv,noheader,nounits >>"$CSV" 2>>"$ERRORS_FILE"; then
    warn "nvidia-smi sample failed"
  fi
  sample_no=$((sample_no + 1))
  if (( sample_no % SNAPSHOT_EVERY == 0 )); then
    snapshot_runtime || true
  fi
  if (( DURATION > 0 )); then
    now_epoch="$(date +%s)"
    if (( now_epoch - START_EPOCH >= DURATION )); then
      STOP_REASON="duration"
      break
    fi
  fi
  sleep "$INTERVAL"
done

finish
exit 0
