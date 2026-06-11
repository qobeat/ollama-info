#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.9"
SCRIPT_SIGNATURE="OLLAMA_INFO_WRAPPER_SIGNATURE=v1.9-compact-multimodel-readme"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
TEST_AND_MONITOR_SCRIPT="${OLLAMA_INFO_TEST_AND_MONITOR_SCRIPT:-$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh}"
DEFAULT_OUT_DIR="${OLLAMA_INFO_OUT_DIR:-$HOME/log/ollama-test-and-monitor-RTX3090}"
DEFAULT_TMP_DIR="${TMP_DIR:-$HOME/tmp}"

usage() {
  cat <<EOF_USAGE
ollama.sh v$VERSION
$SCRIPT_SIGNATURE

Primary ollama-info wrapper. Install bashrc/.bashrc to expose this as an ollama subcommand wrapper.

Usage:
  ollama.sh status|start|stop|models|gpu|logs [options]
  ollama.sh test MODEL [MODEL ...] [options]
  ollama.sh bench MODEL [MODEL ...] [options]
  ollama.sh embed-test MODEL [MODEL ...] [options]
  ollama.sh <native-ollama-subcommand> [args...]

Examples:
  ollama.sh test qwen3.6:35b qwen3.6:27b
  ollama.sh test qwen3.6:27b --profile perf --load-mode observed
  ollama.sh bench qwen3-embedding:4b qwen3.6:27b

Defaults:
  test/bench use the ADOS capability profile and --load-mode empty-card unless overridden.
  multi-model test/bench/embed-test writes one aggregate archive instead of one zip per model.
EOF_USAGE
}

need_cmd() { ollama_need_cmd "$1" || exit 2; }

show_models() {
  local cmd="${1:-ollama bench}"
  if ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
    ollama_print_available_model_commands "$BASE_URL" "$cmd" "$CONNECT_TIMEOUT_SEC"
  else
    ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true
    ollama_print_start_hint "$BASE_URL"
    return 3
  fi
}

option_takes_value() {
  case "$1" in
    --base-url|--out-dir|--tmp-dir|--run-id|--num-ctx|--long-ctx|--num-predict|--long-num-predict|--long-prompt-words|--temperature|--timeout-sec|--concurrency|--think|--profile|--load-mode|--prompt-prefix|--server-log-lines|--interval|--monitor-profile|--soak-minutes|--soak-num-predict|--vram-model|--vram-ctx|--vram-num-predict) return 0 ;;
    *) return 1 ;;
  esac
}

split_models_and_options() {
  MODELS=()
  PASS_ARGS=()
  ROUTE_ONLY=0
  FAIL_FAST=0
  ZIP_REQUESTED=1
  OUT_DIR_OVERRIDE=""
  TMP_DIR_OVERRIDE=""
  RUN_ID_OVERRIDE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --route-only|--dry-run) ROUTE_ONLY=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --continue-on-error) FAIL_FAST=0; shift ;;
      --zip) ZIP_REQUESTED=1; PASS_ARGS+=("$1"); shift ;;
      --no-zip) ZIP_REQUESTED=0; PASS_ARGS+=("$1"); shift ;;
      --base-url)
        BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"
        PASS_ARGS+=(--base-url "$BASE_URL")
        shift 2 ;;
      --out-dir)
        OUT_DIR_OVERRIDE="$(ollama_require_arg_value "$1" "${2-}")"
        shift 2 ;;
      --tmp-dir)
        TMP_DIR_OVERRIDE="$(ollama_require_arg_value "$1" "${2-}")"
        shift 2 ;;
      --run-id)
        RUN_ID_OVERRIDE="$(ollama_require_arg_value "$1" "${2-}")"
        shift 2 ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do PASS_ARGS+=("$1"); shift; done ;;
      --*)
        if option_takes_value "$1"; then
          local opt="$1" val
          val="$(ollama_require_arg_value "$1" "${2-}")"
          PASS_ARGS+=("$opt" "$val")
          shift 2
        else
          PASS_ARGS+=("$1")
          shift
        fi ;;
      *) MODELS+=("$1"); shift ;;
    esac
  done
}

resolve_model_or_report() {
  local pattern="$1" command_hint="$2" resolved rc
  set +e
  resolved="$(ollama_resolve_model_common "$pattern" "$BASE_URL" "$CONNECT_TIMEOUT_SEC")"
  rc=$?
  set -e
  case "$rc" in
    0) printf '%s\n' "$resolved" ;;
    5)
      echo "ERROR: model pattern '$pattern' is ambiguous. Use one exact model name:" >&2
      ollama_print_model_commands "$command_hint" "$resolved" "  - " "$BASE_URL" "$CONNECT_TIMEOUT_SEC" >&2
      return 5 ;;
    *)
      echo "ERROR: no local Ollama model matched pattern '$pattern'." >&2
      ollama_print_available_model_commands "$BASE_URL" "$command_hint" "$CONNECT_TIMEOUT_SEC" >&2 || true
      return 4 ;;
  esac
}

model_role_for() {
  local model="$1" show_json role="unknown"
  show_json="$(ollama_api_show_json "$BASE_URL" "$model" "$CONNECT_TIMEOUT_SEC" false 2>/dev/null || true)"
  if [[ -n "$show_json" ]]; then
    role="$(printf '%s\n' "$show_json" | ollama_model_role_from_show_json 2>/dev/null || printf unknown)"
  fi
  printf '%s\n' "$role"
}

safe_id() {
  printf '%s' "$1" | tr '/:[:space:]' '____' | tr -cd 'A-Za-z0-9._-'
}

quote_cmd() {
  local arg
  for arg in "$@"; do printf ' %q' "$arg"; done
}

append_key_lines() {
  local file="$1" label="$2"
  [[ -s "$file" ]] || { echo "- $label: summary missing"; return 0; }
  awk -v label="$label" '
    BEGIN{print "### " label; print "```text"}
    /^(Run ID|Model|Role|Mode|Status|TTFT|Residency|Test|TTFTany|TTFTans|E2E500|Visible|FirstReqLoad|FirstTTFT|WarmTTFT|LongCtx|Output|Inference|Telemetry|Thermal|Power|VRAM|PCIe|Clocks|EmptyCard|LoadWarn|LoadNote)\s*:/ {print}
    END{print "```"; print ""}
  ' "$file"
}

make_multi_summary_and_archive() {
  local mode="$1" agg_dir="$2" agg_id="$3" archive_path="$4" final_rc="$5"
  local summary="$agg_dir/multi-model-summary.md" csv="$agg_dir/multi-model-index.csv" i subdir model role rc term csvp
  mkdir -p "$agg_dir"
  printf 'index,model,role,exit_code,run_dir,summary_csv,terminal_summary\n' >"$csv"
  {
    echo "# RTX 3090 Ollama Multi-Model Summary"
    echo
    echo "- command_mode: $mode"
    echo "- aggregate_run_id: $agg_id"
    echo "- final_exit_code: $final_rc"
    echo "- archive: ${archive_path:-not-created}"
    echo "- model_count: ${#SUBRUN_MODELS[@]}"
    echo
    echo "## Index"
    echo
    echo "| # | Model | Role | Exit | Run directory |"
    echo "|---:|---|---|---:|---|"
    for i in "${!SUBRUN_MODELS[@]}"; do
      model="${SUBRUN_MODELS[$i]}"; role="${SUBRUN_ROLES[$i]}"; rc="${SUBRUN_RCS[$i]}"; subdir="${SUBRUN_DIRS[$i]}"
      term="$subdir/terminal-summary.txt"
      csvp="$(find "$subdir" -path '*/test/*/summary.csv' -type f | head -1 || true)"
      printf '%s,%q,%q,%q,%q,%q,%q\n' "$((i+1))" "$model" "$role" "$rc" "$subdir" "$csvp" "$term" >>"$csv"
      printf '| %d | `%s` | %s | %s | `%s` |\n' "$((i+1))" "$model" "$role" "$rc" "$subdir"
    done
    echo
    echo "## Compact per-model summaries"
    echo
    for i in "${!SUBRUN_MODELS[@]}"; do
      subdir="${SUBRUN_DIRS[$i]}"
      append_key_lines "$subdir/terminal-summary.txt" "${SUBRUN_MODELS[$i]}"
    done
    echo "## Interpretation note"
    echo
    echo "The aggregate archive owns all sub-run directories. Individual model runs are executed with --no-zip so a multi-model command produces one ZIP by default. Detailed raw payloads, streaming NDJSON, summary CSV files, hardware telemetry, and monitor reports remain inside each sub-run directory."
  } >"$summary"

  if [[ "$ZIP_REQUESTED" == "1" ]]; then
    mkdir -p "$(dirname "$archive_path")"
    rm -f "$archive_path"
    if command -v zip >/dev/null 2>&1; then
      (cd "$(dirname "$agg_dir")" && zip -qr "$archive_path" "$(basename "$agg_dir")")
      printf '%s\n' "$archive_path" >"$agg_dir/archive.path"
    else
      echo "WARN: zip is missing; cannot create aggregate archive" >&2
    fi
  fi
}

run_single_model() {
  local mode="$1" resolved="$2" role="$3" route="$4"
  local route_args=(--model "$resolved" "${PASS_ARGS[@]}")
  [[ -n "$OUT_DIR_OVERRIDE" ]] && route_args+=(--out-dir "$OUT_DIR_OVERRIDE")
  [[ -n "$RUN_ID_OVERRIDE" ]] && route_args+=(--run-id "$RUN_ID_OVERRIDE")
  [[ "$route" == "embedding" ]] && route_args+=(--embedding)
  if [[ "$ROUTE_ONLY" == "1" ]]; then
    printf 'route=%s model=%q command=%q' "$route" "$resolved" "$TEST_AND_MONITOR_SCRIPT"
    quote_cmd "${route_args[@]}"
    printf '\n'
  else
    TMP_DIR="${TMP_DIR_OVERRIDE:-$DEFAULT_TMP_DIR}" "$TEST_AND_MONITOR_SCRIPT" "${route_args[@]}"
  fi
}

run_multi_model_aggregate() {
  local mode="$1" command_hint="$2" rc=0 first_rc=0 idx=0 resolved role route sub_id sub_dir agg_id out_root tmp_root agg_dir archive_path
  out_root="${OUT_DIR_OVERRIDE:-$DEFAULT_OUT_DIR}"
  tmp_root="${TMP_DIR_OVERRIDE:-$DEFAULT_TMP_DIR}"
  agg_id="${RUN_ID_OVERRIDE:-$(date +%Y%m%d-%H%M%S)-multi}"
  agg_dir="$out_root/run-$agg_id"
  archive_path="$tmp_root/ollama-test-and-monitor-RTX3090-$agg_id.zip"
  SUBRUN_MODELS=(); SUBRUN_ROLES=(); SUBRUN_RCS=(); SUBRUN_DIRS=()
  mkdir -p "$agg_dir/runs"
  for idx in "${!MODELS[@]}"; do
    resolved="$(resolve_model_or_report "${MODELS[$idx]}" "$command_hint")" || { rc=$?; [[ "$first_rc" == 0 ]] && first_rc=$rc; [[ "$FAIL_FAST" == 1 ]] && break; continue; }
    role="generate"
    route="generate"
    if [[ "$mode" == "bench" ]]; then
      role="$(model_role_for "$resolved")"
      case "$role" in
        embedding) route="embedding" ;;
        generate) route="generate" ;;
        *) echo "ERROR: unable to classify model role for '$resolved' from /api/show; refusing to auto-route." >&2; rc=2; [[ "$first_rc" == 0 ]] && first_rc=$rc; [[ "$FAIL_FAST" == 1 ]] && break; continue ;;
      esac
    elif [[ "$mode" == "embed-test" ]]; then
      role="embedding"; route="embedding"
    fi
    sub_id="$agg_id-$((idx+1))-$(safe_id "$resolved")"
    sub_dir="$agg_dir/runs/run-$sub_id"
    SUBRUN_MODELS+=("$resolved"); SUBRUN_ROLES+=("$role"); SUBRUN_DIRS+=("$sub_dir")
    echo "$(date -Is) ollama $mode aggregate[$((idx+1))/${#MODELS[@]}] model=$resolved role=$role run_id=$sub_id"
    if [[ "$ROUTE_ONLY" == "1" ]]; then
      printf 'route=%s model=%q command=%q --model %q --out-dir %q --run-id %q --no-zip' "$route" "$resolved" "$TEST_AND_MONITOR_SCRIPT" "$resolved" "$agg_dir/runs" "$sub_id"
      [[ "$route" == "embedding" ]] && printf ' --embedding'
      quote_cmd "${PASS_ARGS[@]}"
      printf '\n'
      rc=0
    else
      local route_args=(--model "$resolved" --out-dir "$agg_dir/runs" --run-id "$sub_id" "${PASS_ARGS[@]}" --no-zip)
      [[ "$route" == "embedding" ]] && route_args+=(--embedding)
      set +e
      TMP_DIR="$tmp_root" "$TEST_AND_MONITOR_SCRIPT" "${route_args[@]}"
      rc=$?
      set -e
    fi
    SUBRUN_RCS+=("$rc")
    if [[ "$rc" != "0" ]]; then
      [[ "$first_rc" == 0 ]] && first_rc=$rc
      [[ "$FAIL_FAST" == "1" ]] && break
    fi
    rc=0
  done
  if [[ "$ROUTE_ONLY" != "1" ]]; then
    make_multi_summary_and_archive "$mode" "$agg_dir" "$agg_id" "$archive_path" "$first_rc"
    echo "$(date -Is) Multi-model archive: ${archive_path:-not-created}"
    echo "$(date -Is) Multi-model summary: $agg_dir/multi-model-summary.md"
  fi
  return "$first_rc"
}

run_multi() {
  local mode="$1" command_hint="$2" rc=0 first_rc=0 model resolved role route
  shift 2
  split_models_and_options "$@"
  if [[ "${#MODELS[@]}" -eq 0 ]]; then
    usage
    echo
    show_models "$command_hint" || true
    return 2
  fi
  need_cmd curl
  need_cmd jq
  if ! ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
    ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true
    ollama_print_start_hint "$BASE_URL"
    return 3
  fi
  if [[ "${#MODELS[@]}" -gt 1 ]]; then
    run_multi_model_aggregate "$mode" "$command_hint"
    return $?
  fi
  model="${MODELS[0]}"
  resolved="$(resolve_model_or_report "$model" "$command_hint")" || return $?
  role="generate"; route="generate"
  case "$mode" in
    test) role="generate"; route="generate" ;;
    embed-test) role="embedding"; route="embedding" ;;
    bench)
      role="$(model_role_for "$resolved")"
      case "$role" in
        embedding) route="embedding" ;;
        generate) route="generate" ;;
        *) echo "ERROR: unable to classify model role for '$resolved' from /api/show; refusing to auto-route." >&2; echo "Evidence: role=unknown endpoint=/api/show model=$resolved" >&2; return 2 ;;
      esac
      echo "$(date -Is) ollama bench model=$resolved role=$role" ;;
    *) echo "ERROR: unknown wrapper mode $mode" >&2; return 2 ;;
  esac
  run_single_model "$mode" "$resolved" "$role" "$route"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 2; }
shift || true
case "$cmd" in
  -h|--help|help) usage ;;
  status|stat) exec "$SCRIPT_DIR/ollama-status" "$@" ;;
  start) exec "$SCRIPT_DIR/ollama-start" "$@" ;;
  stop) exec "$SCRIPT_DIR/ollama-stop" "$@" ;;
  models|list-models) show_models "ollama bench" "$@" ;;
  gpu) nvidia-smi "$@" ;;
  logs|log)
    if command -v journalctl >/dev/null 2>&1; then journalctl -u ollama -n "${1:-120}" --no-pager; else echo "journalctl not available" >&2; exit 2; fi ;;
  test) run_multi test "ollama test" "$@" ;;
  bench) run_multi bench "ollama bench" "$@" ;;
  embed-test|embedtest|embedding-test) run_multi embed-test "ollama embed-test" "$@" ;;
  *)
    if command -v ollama >/dev/null 2>&1; then command ollama "$cmd" "$@"; exit $?; fi
    echo "ERROR: unknown ollama-info command '$cmd' and native ollama CLI is not available" >&2
    exit 2 ;;
esac
