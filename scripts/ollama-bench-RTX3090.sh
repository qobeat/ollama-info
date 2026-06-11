#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.7.1"
SCRIPT_SIGNATURE="OLLAMA_BENCH_RTX3090_SCRIPT_SIGNATURE=v1.7.1-auto-route-role-aware-loadstate"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
MODEL=""
PASS_ARGS=()
ROUTE_ONLY=0

usage() {
  cat <<EOF_USAGE
ollama-bench-RTX3090.sh v$VERSION
$SCRIPT_SIGNATURE

Auto-route an Ollama model to the correct RTX 3090 benchmark by model role.

Usage:
  ./ollama-bench-RTX3090.sh MODEL_PATTERN [options]
  ./ollama-bench-RTX3090.sh --model MODEL_PATTERN [options]

Behavior:
  generation-capable model  -> ollama-test-and-monitor-RTX3090.sh MODEL
  embedding-only model      -> ollama-test-and-monitor-RTX3090.sh MODEL --embedding
  unknown role              -> preflight refusal with evidence

Most options are passed through to ollama-test-and-monitor-RTX3090.sh.

Verification option:
  --route-only / --dry-run  Resolve role and print selected route without executing benchmark
EOF_USAGE
}

need_cmd() { ollama_need_cmd "$1" || exit 2; }
script_display_cmd() { ollama_display_cmd "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="$(ollama_require_arg_value "$1" "${2-}")"; shift 2 ;;
    --base-url)
      BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; PASS_ARGS+=(--base-url "$BASE_URL"); shift 2 ;;
    --out-dir|--run-id|--interval|--monitor-profile|--num-ctx|--long-ctx|--num-predict|--long-num-predict|--long-prompt-words|--concurrency|--think|--load-mode|--server-log-lines|--soak-minutes|--soak-num-predict|--vram-model|--vram-ctx|--vram-num-predict|--timeout-sec)
      local_opt="$1"; local_val="$(ollama_require_arg_value "$1" "${2-}")"; PASS_ARGS+=("$local_opt" "$local_val"); shift 2 ;;
    --route-only|--dry-run)
      ROUTE_ONLY=1; shift ;;
    --stream|--no-stream|--ensure-server|--no-ensure-server|--full-model-show|--no-full-model-show|--wsl-diagnostics|--no-wsl-diagnostics|--stress|--run-conc|--no-conc|--run-cpu|--no-cpu|--run-vram-pressure|--no-vram-pressure|--pull|--no-pull|--terminal-summary|--no-terminal-summary|--zip|--no-zip)
      PASS_ARGS+=("$1"); shift ;;
    --embedding|--embed|--no-embedding|--no-embed)
      echo "ERROR: ollama bench auto-routes role; do not pass $1. Use ollama test or ollama embed-test to force a mode." >&2
      exit 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      echo "ERROR: unknown argument for bench wrapper: $1" >&2
      usage >&2
      exit 2 ;;
    *)
      if [[ -z "$MODEL" ]]; then MODEL="$1"; shift; else echo "ERROR: unexpected extra positional argument: $1" >&2; usage >&2; exit 2; fi ;;
  esac
done

if [[ -z "$MODEL" ]]; then
  usage
  echo
  ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true
  echo
  if ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
    ollama_print_available_model_commands "$BASE_URL" "ollama bench" "$CONNECT_TIMEOUT_SEC"
  fi
  exit 2
fi

need_cmd curl
need_cmd jq

if ! ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
  ollama_status_short_common "$BASE_URL" "$CONNECT_TIMEOUT_SEC" || true
  ollama_print_start_hint "$BASE_URL"
  exit 3
fi

set +e
resolved="$(ollama_resolve_model_common "$MODEL" "$BASE_URL" "$CONNECT_TIMEOUT_SEC")"
rc=$?
set -e
case "$rc" in
  0) ;;
  5)
    echo "ERROR: model pattern '$MODEL' is ambiguous. Use one exact model name:" >&2
    ollama_print_model_commands "ollama bench" "$resolved" "  - " "$BASE_URL" "$CONNECT_TIMEOUT_SEC" >&2
    exit 5 ;;
  *)
    echo "ERROR: no local Ollama model matched pattern '$MODEL'." >&2
    ollama_print_available_model_commands "$BASE_URL" "ollama bench" "$CONNECT_TIMEOUT_SEC" >&2 || true
    exit 4 ;;
esac

show_json="$(ollama_api_show_json "$BASE_URL" "$resolved" "$CONNECT_TIMEOUT_SEC" false 2>/dev/null || true)"
role="unknown"
if [[ -n "$show_json" ]]; then
  role="$(printf '%s\n' "$show_json" | ollama_model_role_from_show_json 2>/dev/null || printf unknown)"
fi

echo "$(date -Is) ollama-bench-RTX3090.sh v$VERSION"
echo "$(date -Is) $SCRIPT_SIGNATURE"
echo "$(date -Is) model=$resolved role=$role"

if [[ "$ROUTE_ONLY" == "1" ]]; then
  case "$role" in
    embedding)
      printf 'route=embedding command=%q --model %q' "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved"
      for arg in "${PASS_ARGS[@]}"; do printf ' %q' "$arg"; done
      printf ' --embedding\n'
      exit 0 ;;
    generate)
      printf 'route=generate command=%q --model %q' "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved"
      for arg in "${PASS_ARGS[@]}"; do printf ' %q' "$arg"; done
      printf '\n'
      exit 0 ;;
  esac
fi

case "$role" in
  embedding)
    exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" --model "$resolved" "${PASS_ARGS[@]}" --embedding ;;
  generate)
    exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" --model "$resolved" "${PASS_ARGS[@]}" ;;
  *)
    echo "ERROR: unable to classify model role for '$resolved' from /api/show; refusing to auto-route." >&2
    echo "Evidence: role=unknown endpoint=/api/show model=$resolved" >&2
    echo "Next: run ollama test $resolved for generation-only mode, or ollama embed-test $resolved for embedding mode if you know the model role." >&2
    exit 2 ;;
esac
