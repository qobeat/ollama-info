#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.8"
SCRIPT_SIGNATURE="OLLAMA_INFO_WRAPPER_SIGNATURE=v1.8-empty-card-multimodel"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"

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
  test/bench use the v1.8 ADOS capability profile and --load-mode empty-card unless overridden.
EOF_USAGE
}

need_cmd() { ollama_need_cmd "$1" || exit 2; }

script_path() { printf '%s/%s\n' "$SCRIPT_DIR" "$1"; }

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

split_models_and_options() {
  MODELS=()
  PASS_ARGS=()
  ROUTE_ONLY=0
  FAIL_FAST=0
  local in_opts=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --route-only|--dry-run) ROUTE_ONLY=1; shift ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --continue-on-error) FAIL_FAST=0; shift ;;
      --base-url)
        BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"
        PASS_ARGS+=(--base-url "$BASE_URL")
        in_opts=1
        shift 2 ;;
      --)
        in_opts=1
        shift
        while [[ $# -gt 0 ]]; do PASS_ARGS+=("$1"); shift; done ;;
      --*) in_opts=1; PASS_ARGS+=("$1"); shift ;;
      *)
        if [[ "$in_opts" == "0" ]]; then MODELS+=("$1"); else PASS_ARGS+=("$1"); fi
        shift ;;
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

run_multi() {
  local mode="$1" command_hint="$2" rc=0 first_rc=0 model resolved role route_args=()
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
  for model in "${MODELS[@]}"; do
    resolved="$(resolve_model_or_report "$model" "$command_hint")" || { rc=$?; [[ "$first_rc" == 0 ]] && first_rc=$rc; [[ "$FAIL_FAST" == 1 ]] && return "$rc"; continue; }
    route_args=(--model "$resolved" "${PASS_ARGS[@]}")
    case "$mode" in
      test)
        if [[ "$ROUTE_ONLY" == "1" ]]; then
          printf 'route=test model=%q command=%q' "$resolved" "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh"
          for arg in "${route_args[@]}"; do printf ' %q' "$arg"; done
          printf '\n'
        else
          "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "${route_args[@]}" || rc=$?
        fi ;;
      embed-test)
        route_args+=(--embedding)
        if [[ "$ROUTE_ONLY" == "1" ]]; then
          printf 'route=embedding model=%q command=%q' "$resolved" "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh"
          for arg in "${route_args[@]}"; do printf ' %q' "$arg"; done
          printf '\n'
        else
          "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "${route_args[@]}" || rc=$?
        fi ;;
      bench)
        role="$(model_role_for "$resolved")"
        case "$role" in
          embedding) route_args+=(--embedding); route="embedding" ;;
          generate) route="generate" ;;
          *)
            echo "ERROR: unable to classify model role for '$resolved' from /api/show; refusing to auto-route." >&2
            echo "Evidence: role=unknown endpoint=/api/show model=$resolved" >&2
            rc=2
            [[ "$first_rc" == 0 ]] && first_rc=$rc
            [[ "$FAIL_FAST" == 1 ]] && return "$rc"
            continue ;;
        esac
        echo "$(date -Is) ollama bench model=$resolved role=$role"
        if [[ "$ROUTE_ONLY" == "1" ]]; then
          printf 'route=%s model=%q command=%q' "$route" "$resolved" "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh"
          for arg in "${route_args[@]}"; do printf ' %q' "$arg"; done
          printf '\n'
        else
          "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "${route_args[@]}" || rc=$?
        fi ;;
      *) echo "ERROR: unknown wrapper mode $mode" >&2; return 2 ;;
    esac
    if [[ "${rc:-0}" != "0" ]]; then
      [[ "$first_rc" == 0 ]] && first_rc=$rc
      [[ "$FAIL_FAST" == 1 ]] && return "$rc"
      rc=0
    fi
  done
  return "$first_rc"
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
