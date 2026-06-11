#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VERSION="1.7.0"

usage() {
  cat <<EOF_USAGE
ollama-embed-test-RTX3090.sh v$VERSION

Run RTX 3090 + Ollama embedding health/performance tests through /api/embed and monitor telemetry. v1.7 includes batch, long-context, and RAG-profile embedding rows.

Usage:
  ./ollama-embed-test-RTX3090.sh MODEL_PATTERN [options]
  ./ollama-embed-test-RTX3090.sh --model MODEL_PATTERN [options]

Equivalent to:
  ./ollama-test-and-monitor-RTX3090.sh MODEL_PATTERN --embedding [options]

Examples:
  ./ollama-embed-test-RTX3090.sh bge-m3
  ./ollama-embed-test-RTX3090.sh bge-m3 --long-prompt-words 3200
EOF_USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

exec "$SCRIPT_DIR/ollama-test-and-monitor-RTX3090.sh" "$@" --embedding
