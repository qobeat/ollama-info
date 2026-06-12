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
  status                                show Ollama/API/GPU status
  models                                list local models and roles
  test [--full] MODEL [MODEL...] [opts] resident-warm by default; --full runs all lanes
  compare MODEL [MODEL...] [opts]       alias for multi-model generation comparison
  diagnose MODEL [MODEL...] [opts]      full diagnostic alias; includes context testing
  context-test MODEL [MODEL...] --min-context 65536
                                        context-window validation only
  bench MODEL [MODEL...] [opts]         role-aware route: generation -> test, embedding -> embed-test
  embed-test MODEL [MODEL...]           embedding/RAG benchmark through /api/embed
  preload MODEL [--ctx N] [--keep-alive V]
                                        preload and keep a model resident
  start|stop|logs|gpu                   service/GPU helpers
  other args                            pass through to native ollama CLI
EOF_USAGE
}

split_models_opts(){
  MODELS=(); OPTS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full|--quick|--force-context-pressure|--strict-exit|--zip|--no-zip|--route-only|--dry-run|--terminal-summary|--no-terminal-summary)
        OPTS+=("$1"); shift ;;
      --model|--base-url|--out-dir|--run-id|--mode|--profile|--num-ctx|--num-predict|--min-context|--context-steps|--min-context-eval|--min-context-chars|--min-context-fill|--keep-alive|--temperature|--timeout-sec|--think|--evidence-level)
        OPTS+=("$1" "$(ollama_require_arg_value "$1" "${2-}")"); shift 2 ;;
      --*) OPTS+=("$1"); shift ;;
      *) MODELS+=("$1"); shift ;;
    esac
  done
}

has_opt(){ local x; for x in "${OPTS[@]:-}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }

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
    if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then failures=$((failures+1)); fi
    case "$status" in TOOL_FAILURE|FAIL|NO_ROWS) failures=$((failures+1));; esac
    echo "$resolved,$role,$status,$subrun,$score,$settings" >>"$agg/multi-model-index.csv"
    { echo "## $resolved"; echo; [[ -f "$subrun/terminal-summary.txt" ]] && sed 's/^/    /' "$subrun/terminal-summary.txt"; echo; } >>"$agg/multi-model-summary.md"
  done
  python3 "$SCRIPT_DIR/ollama-aggregate-summary.py" "$agg" --mode test
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
  run_id="$(date +%Y%m%d-%H%M%S)-embed-multi"; agg="$LOG_ROOT/run-$run_id"; idx=0; failures=0
  mkdir -p "$agg/runs" "$TMP_DIR"; echo "model,role,status,run_dir" >"$agg/multi-model-index.csv"
  for m in "${MODELS[@]}"; do
    idx=$((idx+1)); local resolved role safe subid subrun status
    resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo unknown)"; safe="$(ollama_sanitize_name "$resolved")"; subid="$run_id-$idx-$safe"
    set +e; OUT_DIR="$agg/runs" RUN_ID="$subid" TMP_DIR="$TMP_DIR" BASE_URL="$BASE_URL" "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "$resolved" "${OPTS[@]}" --no-zip; rc=$?; set -e
    subrun="$agg/runs/run-$subid"; status="$(grep -E '^- status:' "$subrun/summary.md" 2>/dev/null | awk '{print $3}' || echo UNKNOWN)"
    echo "$resolved,$role,$status,$subrun" >>"$agg/multi-model-index.csv"; [[ "$rc" -ne 0 ]] && failures=$((failures+1))
  done
  local archive="$TMP_DIR/ollama-embed-test-RTX3090-${#MODELS[@]}models-$run_id.zip"; (cd "$(dirname "$agg")" && zip -qr "$archive" "$(basename "$agg")"); echo "Aggregate zip: $archive"; [[ "$failures" -eq 0 ]]
}

aggregate_bench(){
  split_models_opts "$@"
  [[ "${#MODELS[@]}" -gt 0 ]] || { usage; return 0; }
  local route_only=0; for o in "${OPTS[@]}"; do [[ "$o" == "--route-only" || "$o" == "--dry-run" ]] && route_only=1; done
  if [[ "$route_only" -eq 1 ]]; then
    for m in "${MODELS[@]}"; do
      local resolved role; resolved="$(ollama_resolve_model "$m" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo generate)"
      if [[ "$role" == "embedding" ]]; then echo "model=$resolved role=$role route=ollama-embed-test endpoint=/api/embed"; else echo "model=$resolved role=$role route=ollama-test endpoint=/api/generate"; fi
    done; return 0
  fi
  if [[ "${#MODELS[@]}" -eq 1 ]]; then
    local resolved role; resolved="$(ollama_resolve_model "${MODELS[0]}" "$BASE_URL")"; role="$(ollama_model_role "$resolved" "$BASE_URL" 2>/dev/null || echo generate)"
    if [[ "$role" == "embedding" ]]; then exec "$SCRIPT_DIR/ollama-embed-test-RTX3090.sh" "$resolved" "${OPTS[@]}"; else exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" "${OPTS[@]}"; fi
  fi
  # For mixed multi-model bench, reuse generation aggregate for generation models and embed aggregate separately is out of scope; keep prior route behavior through aggregate_generation.
  aggregate_generation "${MODELS[@]}" "${OPTS[@]}"
}

context_test(){
  split_models_opts "$@"
  if ! has_opt --min-context; then OPTS=(--mode context-pressure --min-context 65536 "${OPTS[@]}"); else OPTS=(--mode context-pressure "${OPTS[@]}"); fi
  aggregate_generation "${MODELS[@]}" "${OPTS[@]}"
}

diagnose(){
  split_models_opts "$@"
  if ! has_opt --full; then OPTS=(--full "${OPTS[@]}"); fi
  aggregate_generation "${MODELS[@]}" "${OPTS[@]}"
}

case "$cmd" in
  status) ollama_status_short_common "$BASE_URL" ;;
  models) ollama_print_available_model_commands "$BASE_URL" "ollama test" ;;
  gpu) command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || echo "nvidia-smi unavailable" ;;
  logs) journalctl -u ollama.service -n "${1:-120}" --no-pager 2>/dev/null || true ;;
  start) sudo systemctl start ollama.service ;;
  stop) sudo systemctl stop ollama.service ;;
  test|compare) aggregate_generation "$@" ;;
  diagnose) diagnose "$@" ;;
  context-test) context_test "$@" ;;
  embed-test) aggregate_embed "$@" ;;
  bench) aggregate_bench "$@" ;;
  preload)
    model="${1:-}"; [[ -n "$model" ]] || ollama_die "preload requires model"; shift || true
    ctx=4096; keep=24h
    while [[ $# -gt 0 ]]; do case "$1" in --ctx) ctx="$2"; shift 2;; --keep-alive) keep="$2"; shift 2;; *) shift;; esac; done
    model="$(ollama_resolve_model "$model" "$BASE_URL")"
    jq -nc --arg model "$model" --arg keep "$keep" --argjson ctx "$ctx" '{model:$model,prompt:"",stream:false,keep_alive:$keep,options:{num_ctx:$ctx,num_predict:1}}' | curl -fsS -H 'Content-Type: application/json' -d @- "$BASE_URL/api/generate" >/dev/null
    ollama ps ;;
  -h|--help|help) usage ;;
  *) if command -v ollama >/dev/null 2>&1; then exec ollama "$cmd" "$@"; else usage; fi ;;
esac
