#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMMON_SCRIPT="$SCRIPT_DIR/ollama-common.sh"
[[ -r "$COMMON_SCRIPT" ]] || { echo "ERROR: missing readable $COMMON_SCRIPT" >&2; exit 2; }
# shellcheck source=/dev/null
source "$COMMON_SCRIPT"

VERSION="1.7.0"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-5}"
MODEL="${1:-}"

usage() {
  cat <<EOF_USAGE
ollama-bench-RTX3090.sh v$VERSION

Auto-detect the local Ollama model role and route to the correct RTX 3090 benchmark.

Usage:
  ollama-bench-RTX3090.sh MODEL_PATTERN [options]

Routing:
  generation-capable model -> ollama-test-and-monitor-RTX3090.sh MODEL_PATTERN
  embedding-only model     -> ollama-test-and-monitor-RTX3090.sh MODEL_PATTERN --embedding
EOF_USAGE
}

case "${1:-}" in
  -h|--help|"") usage; [[ -n "${1:-}" ]] && exit 0 || exit 2 ;;
esac
shift || true

if ! ollama_api_ready "$BASE_URL" "$CONNECT_TIMEOUT_SEC"; then
  ollama_print_start_hint "$BASE_URL"
  exit 3
fi

resolved="$(ollama_resolve_model_common "$MODEL" "$BASE_URL" "$CONNECT_TIMEOUT_SEC")" || {
  rc=$?
  if [[ "$rc" == "5" ]]; then
    echo "ERROR: model pattern '$MODEL' is ambiguous. Use one exact model name:" >&2
    ollama_print_model_commands "ollama bench" "$resolved" "  - " "$BASE_URL" "$CONNECT_TIMEOUT_SEC" >&2
    exit 5
  fi
  echo "ERROR: no local Ollama model matched pattern '$MODEL'." >&2
  ollama_print_available_model_commands "$BASE_URL" "ollama bench" "$CONNECT_TIMEOUT_SEC" >&2 || true
  exit 4
}

role="$(ollama_model_role_common "$resolved" "$BASE_URL" "$CONNECT_TIMEOUT_SEC" 2>/dev/null || printf 'unknown')"
case "$role" in
  embedding)
    echo "Bench route: model=$resolved role=embedding endpoint=/api/embed"
    exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" --embedding "$@"
    ;;
  generate)
    echo "Bench route: model=$resolved role=generate endpoint=/api/generate"
    exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$resolved" "$@"
    ;;
  *)
    echo "ERROR: could not determine benchmark role for model '$resolved'." >&2
    echo "Evidence: /api/show role=$role. Use ollama test for known generation models or ollama embed-test for known embedding models." >&2
    exit 2
    ;;
esac
