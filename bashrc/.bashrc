# ollama-info canonical wrapper functions
# Source this file or copy the relevant lines into ~/.bashrc.
export OLLAMA_INFO_HOME="${OLLAMA_INFO_HOME:-$HOME/dev/ollama-info}"
ollama-info-wrapper() { "$OLLAMA_INFO_HOME/scripts/ollama.sh" "$@"; }
ollama-status() { ollama-info-wrapper status "$@"; }
ollama-models() { ollama-info-wrapper models "$@"; }
ollama-gpu() { ollama-info-wrapper gpu "$@"; }
ollama-logs() { ollama-info-wrapper logs "$@"; }
ollama-test() { ollama-info-wrapper test "$@"; }
ollama-bench() { ollama-info-wrapper bench "$@"; }
ollama-embed-test() { ollama-info-wrapper embed-test "$@"; }
ollama-preload() { ollama-info-wrapper preload "$@"; }
