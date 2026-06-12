#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
LOG_ROOT="${LOG_ROOT:-$HOME/log/ollama-test-and-monitor-RTX3090}"
cmd="${1:-status}"; [[ $# -gt 0 ]] && shift || true
usage(){ cat <<EOF_USAGE
ollama.sh commands:
  status                         show Ollama/API/GPU status
  models                         list local models and roles
  test MODEL [MODEL...] [opts]   generation diagnostics; multi-model creates one ZIP
  bench MODEL [MODEL...] [opts]  role-aware route: generation -> test, embedding -> embed-test
  embed-test MODEL [MODEL...]    embedding/RAG benchmark through /api/embed
  preload MODEL [--ctx N] [--keep-alive V]  preload and keep a model resident
  start|stop|logs|gpu            service/GPU helpers
  other args                     pass through to native ollama CLI
EOF_USAGE
}
split_models_opts(){
  MODELS=(); OPTS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in --*) OPTS+=("$1"); if [[ $# -ge 2 && "$2" != --* ]]; then OPTS+=("$2"); shift 2; else shift; fi;; *) MODELS+=("$1"); shift;; esac
  done
}
aggregate_generation(){
  split_models_opts "$@"
  [[ "${#MODELS[@]}" -gt 0 ]] || { "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh"; return; }
  if [[ "${#MODELS[@]}" -eq 1 ]]; then exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "${MODELS[0]}" "${OPTS[@]}"; fi
  local run_id agg idx failures unsupported
  run_id="$(date +%Y%m%d-%H%M%S)-multi"
  agg="$LOG_ROOT/run-$run_id"
  idx=0; failures=0; unsupported=0
  mkdir -p "$agg/runs" "$TMP_DIR"
  echo "model,role,status,run_dir,scorecard,settings" >"$agg/multi-model-index.csv"
  echo "# Multi-model Ollama diagnostic summary" >"$agg/multi-model-summary.md"
  echo >>"$agg/multi-model-summary.md"
  for m in "${MODELS[@]}"; do
    idx=$((idx+1)); local resolved role safe subid subrun status score settings
    resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo unknown)"; safe="$(ollama_sanitize_name "$resolved")"; subid="$run_id-$idx-$safe"
    echo "$(ollama_now_iso) ollama test aggregate[$idx/${#MODELS[@]}] model=$resolved role=$role run_id=$subid"
    set +e
    OUT_DIR="$agg/runs" RUN_ID="$subid" TMP_DIR="$TMP_DIR" BASE_URL="$BASE_URL" "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" "${OPTS[@]}" --no-zip
    rc=$?
    set -e
    subrun="$agg/runs/run-$subid"
    score="$subrun/model-scorecard.csv"; settings="$subrun/performance-settings.sh"
    status="UNKNOWN"
    [[ -f "$score" ]] && status="$(awk -F, 'NR==2{print $3}' "$score")"
    [[ "$role" == "embedding" && "$rc" -eq 2 ]] && unsupported=$((unsupported+1))
    [[ "$rc" -ne 0 && "$rc" -ne 2 ]] && failures=$((failures+1))
    echo "$resolved,$role,$status,$subrun,$score,$settings" >>"$agg/multi-model-index.csv"
    { echo "## $resolved"; echo; [[ -f "$subrun/terminal-summary.txt" ]] && sed 's/^/    /' "$subrun/terminal-summary.txt"; echo; } >>"$agg/multi-model-summary.md"
  done
  python3 - <<'PY' "$agg"
import csv,sys,glob,os
from pathlib import Path
agg=Path(sys.argv[1])
rows=[]
for p in agg.glob('runs/run-*/model-scorecard.csv'):
    with p.open(newline='',encoding='utf-8') as f:
        rr=list(csv.DictReader(f))
        if rr:
            rr[0]['scorecard_path']=str(p); rows.append(rr[0])
cols=['model','role','status','mode','residency','classifications','first_ttft_ms','first_load_s','warm_ttft_ms_avg','visible_tps_avg','vram_pct','recommended_context','keep_alive','max_loaded_models','num_parallel','flash_attention','kv_cache_type','scorecard_path']
with (agg/'model-scorecard.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=cols); w.writeheader(); w.writerows(rows)
# Simple use-case recommendations.
def num(x):
    try: return float(x)
    except: return -1
visible=[r for r in rows if r.get('role')=='generate' and 'CPU_GPU_OFFLOAD_RISK' not in r.get('classifications','')]
best_fast=sorted(visible,key=lambda r:(num(r.get('warm_ttft_ms_avg')) if num(r.get('warm_ttft_ms_avg'))>=0 else 999999, -num(r.get('visible_tps_avg'))))[:1]
best_code=sorted(visible,key=lambda r:-num(r.get('visible_tps_avg')))[:1]
best_general=sorted(visible,key=lambda r:(('THINKING_ONLY_OUTPUT_RISK' in r.get('classifications','')), num(r.get('vram_pct')) if num(r.get('vram_pct'))>=0 else 999, -num(r.get('visible_tps_avg'))))[:1]
md=['# Aggregate recommendations','']
md.append(f"OpenCode/Cursor fast coding: `{best_code[0]['model']}`" if best_code else 'OpenCode/Cursor: no generation candidate')
md.append(f"Hermes/ADOS balanced runtime: `{best_general[0]['model']}`" if best_general else 'Hermes/ADOS: no generation candidate')
md.append('')
md.append('Primary applyable settings are in each sub-run `performance-settings.sh`; compare all rows in `model-scorecard.csv`.')
(agg/'recommendations.md').write_text('\n'.join(md)+'\n')
# Concatenate setting snippets for convenience.
out=['# Performance settings by model','']
for r in rows:
    settings=Path(r['scorecard_path']).parent/'performance-settings.md'
    if settings.exists(): out.append(settings.read_text())
(agg/'performance-settings-all.md').write_text('\n\n---\n\n'.join(out))
PY
  local archive="$TMP_DIR/ollama-test-and-monitor-RTX3090-${#MODELS[@]}models-$run_id.zip"
  (cd "$(dirname "$agg")" && zip -qr "$archive" "$(basename "$agg")")
  echo "$archive" >"$agg/archive.path"
  echo "Aggregate zip: $archive"
  if [[ "$failures" -gt 0 ]]; then return 1; fi
  if [[ "$unsupported" -gt 0 ]]; then return 0; fi
}
aggregate_embed(){
  split_models_opts "$@"
  [[ "${#MODELS[@]}" -gt 0 ]] || { "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh"; return; }
  if [[ "${#MODELS[@]}" -eq 1 ]]; then exec "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "${MODELS[0]}" "${OPTS[@]}"; fi
  local run_id agg idx failures
  run_id="$(date +%Y%m%d-%H%M%S)-embed-multi"
  agg="$LOG_ROOT/run-$run_id"
  idx=0; failures=0
  mkdir -p "$agg/runs" "$TMP_DIR"
  echo "model,role,status,run_dir" >"$agg/multi-model-index.csv"
  for m in "${MODELS[@]}"; do
    idx=$((idx+1)); local resolved role safe subid subrun status
    resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo unknown)"; safe="$(ollama_sanitize_name "$resolved")"; subid="$run_id-$idx-$safe"
    set +e; OUT_DIR="$agg/runs" RUN_ID="$subid" TMP_DIR="$TMP_DIR" BASE_URL="$BASE_URL" "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "$resolved" "${OPTS[@]}" --no-zip; rc=$?; set -e
    subrun="$agg/runs/run-$subid"; status="$(grep -E '^- status:' "$subrun/summary.md" 2>/dev/null | awk '{print $3}' || echo UNKNOWN)"
    echo "$resolved,$role,$status,$subrun" >>"$agg/multi-model-index.csv"; [[ "$rc" -ne 0 ]] && failures=$((failures+1))
  done
  local archive="$TMP_DIR/ollama-embed-test-RTX3090-${#MODELS[@]}models-$run_id.zip"
  (cd "$(dirname "$agg")" && zip -qr "$archive" "$(basename "$agg")")
  echo "Aggregate zip: $archive"
  [[ "$failures" -eq 0 ]]
}

aggregate_bench(){
  split_models_opts "$@"
  [[ "${#MODELS[@]}" -gt 0 ]] || { usage; return 0; }
  local route_only=0
  for o in "${OPTS[@]}"; do [[ "$o" == "--route-only" || "$o" == "--dry-run" ]] && route_only=1; done
  if [[ "$route_only" -eq 1 ]]; then
    for m in "${MODELS[@]}"; do
      local resolved role
      resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo generate)"
      if [[ "$role" == "embedding" ]]; then echo "model=$resolved role=$role route=ollama-embed-test endpoint=/api/embed"; else echo "model=$resolved role=$role route=ollama-test endpoint=/api/generate"; fi
    done
    return 0
  fi
  if [[ "${#MODELS[@]}" -eq 1 ]]; then
    local resolved role
    resolved="$(ollama_resolve_model "${MODELS[0]}" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo generate)"
    if [[ "$role" == "embedding" ]]; then exec "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "$resolved" "${OPTS[@]}"; else exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" "${OPTS[@]}"; fi
  fi
  local run_id agg idx failures
  run_id="$(date +%Y%m%d-%H%M%S)-bench-multi"; agg="$LOG_ROOT/run-$run_id"; idx=0; failures=0
  mkdir -p "$agg/runs" "$TMP_DIR"
  echo "model,role,status,run_dir" >"$agg/multi-model-index.csv"
  echo "# Role-aware benchmark summary" >"$agg/multi-model-summary.md"
  for m in "${MODELS[@]}"; do
    idx=$((idx+1)); local resolved role safe subid subrun rc status
    resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo generate)"; safe="$(ollama_sanitize_name "$resolved")"; subid="$run_id-$idx-$safe"
    echo "$(ollama_now_iso) ollama bench aggregate[$idx/${#MODELS[@]}] model=$resolved role=$role run_id=$subid"
    set +e
    if [[ "$role" == "embedding" ]]; then
      OUT_DIR="$agg/runs" RUN_ID="$subid" TMP_DIR="$TMP_DIR" BASE_URL="$BASE_URL" "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "$resolved" "${OPTS[@]}" --no-zip
    else
      OUT_DIR="$agg/runs" RUN_ID="$subid" TMP_DIR="$TMP_DIR" BASE_URL="$BASE_URL" "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" "${OPTS[@]}" --no-zip
    fi
    rc=$?
    set -e
    subrun="$agg/runs/run-$subid"; status="UNKNOWN"
    [[ -f "$subrun/model-scorecard.csv" ]] && status="$(awk -F, 'NR==2{print $3}' "$subrun/model-scorecard.csv")"
    [[ -f "$subrun/summary.md" ]] && status="$(grep -E '^- status:' "$subrun/summary.md" | awk '{print $3}' | head -1 || echo "$status")"
    echo "$resolved,$role,$status,$subrun" >>"$agg/multi-model-index.csv"
    [[ "$rc" -ne 0 && "$rc" -ne 2 ]] && failures=$((failures+1))
  done
  python3 - <<'PYB' "$agg"
import csv, pathlib, sys
agg=pathlib.Path(sys.argv[1])
# Merge generation scorecards where present.
rows=[]
for p in agg.glob('runs/run-*/model-scorecard.csv'):
    with p.open(newline='',encoding='utf-8') as f:
        rr=list(csv.DictReader(f))
        if rr: rows.append(rr[0] | {'scorecard_path': str(p)})
if rows:
    cols=list(rows[0].keys())
    with (agg/'model-scorecard.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=cols); w.writeheader(); w.writerows(rows)
(agg/'recommendations.md').write_text('# Role-aware benchmark recommendations\n\nGeneration and embedding results are in `runs/`; generation scorecards are merged into `model-scorecard.csv` when available.\n')
PYB
  local archive="$TMP_DIR/ollama-bench-RTX3090-${#MODELS[@]}models-$run_id.zip"
  (cd "$(dirname "$agg")" && zip -qr "$archive" "$(basename "$agg")")
  echo "$archive" >"$agg/archive.path"
  echo "Aggregate zip: $archive"
  [[ "$failures" -eq 0 ]]
}

case "$cmd" in
  status) ollama_status_short_common "$BASE_URL" ;;
  models) ollama_print_available_model_commands "$BASE_URL" "ollama test" ;;
  gpu) command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || echo "nvidia-smi unavailable" ;;
  logs) journalctl -u ollama.service -n "${1:-120}" --no-pager 2>/dev/null || true ;;
  start) sudo systemctl start ollama.service ;;
  stop) sudo systemctl stop ollama.service ;;
  test|diagnose) aggregate_generation "$@" ;;
  embed-test) aggregate_embed "$@" ;;
  bench) aggregate_bench "$@" ;;
  preload)
    model="${1:-}"; [[ -n "$model" ]] || ollama_die "preload requires model"; shift || true
    ctx=4096; keep=24h
    while [[ $# -gt 0 ]]; do case "$1" in --ctx) ctx="$2"; shift 2;; --keep-alive) keep="$2"; shift 2;; *) shift;; esac; done
    model="$(ollama_resolve_model "$model" "$BASE_URL")"
    jq -nc --arg model "$model" --arg keep "$keep" --argjson ctx "$ctx" '{model:$model,prompt:"",stream:false,keep_alive:$keep,options:{num_ctx:$ctx,num_predict:1}}' | curl -fsS -H 'Content-Type: application/json' -d @- "$BASE_URL/api/generate" >/dev/null
    ollama ps
    ;;
  -h|--help|help) usage ;;
  *) if command -v ollama >/dev/null 2>&1; then exec ollama "$cmd" "$@"; else usage; fi ;;
esac
