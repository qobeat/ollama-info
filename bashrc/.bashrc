# ollama-info v1.13 Bash integration snippet.
# Source this file from ~/.bashrc, or copy the block below into ~/.bashrc.
# It intercepts only ollama-info package subcommands and passes native Ollama
# commands such as `ollama list`, `ollama pull`, and `ollama run` through.

export OLLAMA_INFO_HOME="${OLLAMA_INFO_HOME:-$HOME/dev/ollama-info}"
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"

for __ollama_info_path in "$OLLAMA_INFO_HOME/scripts" "$OLLAMA_INFO_HOME" "$HOME/bin"; do
  if [ -d "$__ollama_info_path" ]; then
    case ":$PATH:" in
      *":$__ollama_info_path:"*) ;;
      *) PATH="$__ollama_info_path:$PATH" ;;
    esac
  fi
done
unset __ollama_info_path
export PATH

__ollama_info_cli() {
  if [ -x "$OLLAMA_INFO_HOME/scripts/ollama.sh" ]; then
    "$OLLAMA_INFO_HOME/scripts/ollama.sh" "$@"
  elif command -v ollama.sh >/dev/null 2>&1; then
    command ollama.sh "$@"
  elif command -v ollama >/dev/null 2>&1; then
    command ollama "$@"
  else
    echo "ERROR: neither ollama-info scripts nor native ollama CLI are available" >&2
    return 127
  fi
}

__ollama_info_is_subcommand() {
  case "${1:-}" in
    status|start|stop|logs|gpu|models|test|compare|diagnose|context-test|vision-test|bench|embed-test|preload|help|-h|--help)
      return 0 ;;
    *) return 1 ;;
  esac
}

# Native-compatible wrapper. Disable with: export OLLAMA_INFO_WRAP_CLI=0
ollama() {
  if [ "${OLLAMA_INFO_WRAP_CLI:-1}" = "1" ] && __ollama_info_is_subcommand "${1:-status}"; then
    __ollama_info_cli "$@"
  else
    command ollama "$@"
  fi
}

ollama_status() { __ollama_info_cli status "$@"; }
ollama_quick_status() { __ollama_info_cli status --brief "$@"; }
ollama_start() { __ollama_info_cli start "$@"; }
ollama_stop() { __ollama_info_cli stop "$@"; }
ollama_models() { __ollama_info_cli models "$@"; }
ollama_gpu() { __ollama_info_cli gpu "$@"; }
ollama_logs() { __ollama_info_cli logs "$@"; }
ollama_test() { __ollama_info_cli test "$@"; }
ollama_context_test() { __ollama_info_cli context-test "$@"; }
ollama_vision_test() { __ollama_info_cli vision-test "$@"; }
ollama_bench() { __ollama_info_cli bench "$@"; }
ollama_embed_test() { __ollama_info_cli embed-test "$@"; }
ollama_preload() { __ollama_info_cli preload "$@"; }

# Backward-compatible hyphenated names.
ollama-status() { ollama_status "$@"; }
ollama-context-test() { ollama_context_test "$@"; }
ollama-vision-test() { ollama_vision_test "$@"; }
ollama-embed-test() { ollama_embed_test "$@"; }

alias os='ollama_status'
alias oq='ollama_quick_status'
alias ost='ollama_start'
alias osp='ollama_stop'
alias om='ollama_models'
alias og='ollama_gpu'
alias ol='ollama_logs'
alias ot='ollama_test'
alias oct='ollama_context_test'
alias ovt='ollama_vision_test'
alias ob='ollama_bench'
alias oet='ollama_embed_test'
