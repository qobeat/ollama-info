#!/usr/bin/env bash
# Shared helpers for ollama-info scripts. Source this file; do not execute directly.

ollama_now_iso() {
  date -Is
}

ollama_log() {
  printf '%s %s\n' "$(ollama_now_iso)" "$*"
}

ollama_warn_to_file() {
  local file="${1:-}"; shift || true
  printf '%s WARN: %s\n' "$(ollama_now_iso)" "$*" >&2
  if [[ -n "$file" ]]; then
    printf '%s WARN: %s\n' "$(ollama_now_iso)" "$*" >>"$file" 2>/dev/null || true
  fi
}

ollama_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: missing command: %s\n' "$1" >&2; return 127; }
}

ollama_is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

ollama_require_arg_value() {
  local opt="${1:-option}" val="${2-}"
  if [[ -z "$val" || "$val" == --* ]]; then
    printf 'ERROR: %s requires a value. Use -h for full help.\n' "$opt" >&2
    return 2
  fi
  printf '%s\n' "$val"
}

ollama_script_dir() {
  cd -- "$(dirname -- "$1")" && pwd -P
}

ollama_display_cmd() {
  local cmd="${1:-}"
  case "$cmd" in
    */*) printf '%s\n' "$cmd" ;;
    *) printf '%s\n' "$(basename "$cmd")" ;;
  esac
}

ollama_timestamp_stream() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
      printf '%s\n' "$line"
    else
      printf '%s %s\n' "$(ollama_now_iso)" "$line"
    fi
  done
}

ollama_print_file_plain() {
  local file="${1:-}"
  [[ -n "$file" && -r "$file" ]] || return 0
  cat -- "$file"
}

ollama_curl_generate() {
  local timeout_sec="$1" connect_timeout_sec="$2" payload_file="$3" raw_file="$4" http_file="$5" stderr_file="$6" base_url="$7"
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 10s "$timeout_sec" curl -sS --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" --output "$raw_file" --write-out '%{http_code}' "$base_url/api/generate" >"$http_file" 2>"$stderr_file"
  else
    curl -sS --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" --output "$raw_file" --write-out '%{http_code}' "$base_url/api/generate" >"$http_file" 2>"$stderr_file"
  fi
}


ollama_curl_embed() {
  local timeout_sec="$1" connect_timeout_sec="$2" payload_file="$3" raw_file="$4" http_file="$5" stderr_file="$6" base_url="$7"
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 10s "$timeout_sec" curl -sS --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" --output "$raw_file" --write-out '%{http_code}' "$base_url/api/embed" >"$http_file" 2>"$stderr_file"
  else
    curl -sS --connect-timeout "$connect_timeout_sec" --max-time "$timeout_sec" -H 'Content-Type: application/json' -H 'Accept: application/json' -d "@$payload_file" --output "$raw_file" --write-out '%{http_code}' "$base_url/api/embed" >"$http_file" 2>"$stderr_file"
  fi
}

ollama_api_show_json() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" model="${2:-}" timeout_s="${3:-5}" verbose="${4:-false}"
  [[ -n "$model" ]] || return 2
  jq -nc --arg model "$model" --argjson verbose "$verbose" '{model:$model, verbose:$verbose}'     | ollama_timeout_cmd "${timeout_s}s" curl -fsS --connect-timeout "$timeout_s" --max-time "$timeout_s" -H 'Content-Type: application/json' -d @- "$base_url/api/show" 2>/dev/null
}

ollama_model_role_from_show_json() {
  jq -r '
    def lcaps: [(.capabilities // [])[] | ascii_downcase];
    def hascap($c): (lcaps | index($c)) != null;
    def arch: ((.model_info["general.architecture"] // "") | ascii_downcase);
    if ((hascap("embedding") or (.model_info["bert.embedding_length"] != null) or (arch == "bert"))
        and ((hascap("completion") | not) and (hascap("generate") | not) and (hascap("chat") | not))) then
      "embedding"
    elif (hascap("completion") or hascap("generate") or hascap("chat") or hascap("vision") or hascap("tools")) then
      "generate"
    elif ((.capabilities // []) | length) == 0 then
      "unknown"
    else
      "generate"
    end
  ' 2>/dev/null
}

ollama_model_role_common() {
  local model="${1:-}" base_url="${2:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${3:-5}" show
  [[ -n "$model" ]] || { printf 'unknown
'; return 2; }
  show="$(ollama_api_show_json "$base_url" "$model" "$timeout_s" false 2>/dev/null || true)"
  if [[ -z "$show" ]]; then printf 'unknown
'; return 0; fi
  printf '%s
' "$show" | ollama_model_role_from_show_json
}

ollama_model_show_slim() {
  local model="${1:-}"
  jq --arg model "$model" '{
    model: (.model // $model),
    capabilities: (.capabilities // []),
    details: (.details // {}),
    architecture: (.model_info["general.architecture"] // null),
    context_length: (.model_info["llama.context_length"] // .model_info["bert.context_length"] // .model_info["gemma3.context_length"] // .model_info["qwen2.context_length"] // .model_info["mpt.context_length"] // null),
    embedding_length: (.model_info["bert.embedding_length"] // .model_info["llama.embedding_length"] // .model_info["general.embedding_length"] // null),
    parameter_count: (.model_info["general.parameter_count"] // null),
    quantization_version: (.model_info["general.quantization_version"] // null)
  }' 2>/dev/null
}

ollama_model_role_is_embedding_only() {
  local role="${1:-unknown}"
  [[ "$role" == "embedding" ]]
}

ollama_timeout_cmd() {
  local seconds="${1:-3}"; shift || true
  if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"; else "$@"; fi
}

ollama_systemctl_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1
}

ollama_has_systemd() {
  ollama_systemctl_available
}

ollama_system_service_load_state() {
  local state out
  ollama_systemctl_available || return 1
  state="$(systemctl show -p LoadState --value ollama.service 2>/dev/null | awk 'NF{print; exit}' || true)"
  if [[ -n "$state" && "$state" != "not-found" ]]; then
    printf '%s\n' "$state"
    return 0
  fi
  out="$(systemctl status ollama.service --no-pager 2>/dev/null || true)"
  if printf '%s\n' "$out" | grep -Eq 'Loaded:[[:space:]]+loaded'; then
    printf 'loaded\n'
    return 0
  fi
  out="$(systemctl list-unit-files ollama.service --no-legend --no-pager 2>/dev/null || true)"
  if printf '%s\n' "$out" | awk '$1=="ollama.service"{found=1} END{exit found?0:1}'; then
    printf 'detected\n'
    return 0
  fi
  [[ -n "$state" ]] && printf '%s\n' "$state" || printf 'unknown\n'
}

ollama_system_service_exists() {
  local state out
  ollama_systemctl_available || return 1

  # Prefer cheap machine-readable checks, but do not trust only one code path.
  # Some WSL/systemd combinations allow `systemctl status ollama` while other
  # discovery forms are blank or restricted.
  state="$(ollama_system_service_load_state || true)"
  case "$state" in
    loaded|linked|linked-runtime|alias|generated|transient|static|indirect|enabled|disabled|masked) return 0 ;;
  esac

  systemctl cat ollama.service >/dev/null 2>&1 && return 0

  out="$(systemctl list-unit-files ollama.service --no-legend --no-pager 2>/dev/null || true)"
  printf '%s\n' "$out" | awk '$1=="ollama.service"{found=1} END{exit found?0:1}' && return 0

  out="$(systemctl list-units --all ollama.service --no-legend --no-pager 2>/dev/null || true)"
  printf '%s\n' "$out" | awk '$1=="ollama.service"{found=1} END{exit found?0:1}' && return 0

  out="$(systemctl status ollama.service --no-pager 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -Eq '(^|[[:space:]])ollama\.service[[:space:]]+-|Loaded:[[:space:]]+loaded' && return 0

  [[ -f /etc/systemd/system/ollama.service || -f /usr/lib/systemd/system/ollama.service || -f /lib/systemd/system/ollama.service ]] && return 0

  return 1
}

ollama_user_service_exists() {
  local state
  ollama_systemctl_available || return 1
  state="$(systemctl --user show -p LoadState --value ollama.service 2>/dev/null | awk 'NF{print; exit}' || true)"
  [[ -n "$state" && "$state" != "not-found" ]] && return 0
  systemctl --user cat ollama.service >/dev/null 2>&1 && return 0
  systemctl --user status ollama.service >/dev/null 2>&1 && return 0
  return 1
}

ollama_sudo_hint() {
  local cmd="$*"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    printf '%s\n' "$cmd"
  else
    printf 'sudo %s\n' "$cmd"
  fi
}

ollama_systemctl_privileged() {
  local action="${1:-}" unit="${2:-ollama.service}"
  if [[ $# -ge 2 ]]; then shift 2; elif [[ $# -ge 1 ]]; then shift; fi
  [[ -n "$action" ]] || { echo "ERROR: missing systemctl action" >&2; return 2; }
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    systemctl "$action" "$unit" "$@"
    return $?
  fi
  if command -v sudo >/dev/null 2>&1; then
    echo "Privilege required: sudo systemctl $action $unit"
    sudo -v || return $?
    sudo systemctl "$action" "$unit" "$@"
    return $?
  fi
  echo "ERROR: sudo is required for: systemctl $action $unit" >&2
  echo "Install sudo or run this command as root." >&2
  return 126
}

ollama_systemctl_nonprivileged() {
  local action="${1:-}" unit="${2:-ollama.service}"
  if [[ $# -ge 2 ]]; then shift 2; elif [[ $# -ge 1 ]]; then shift; fi
  [[ -n "$action" ]] || { echo "ERROR: missing systemctl action" >&2; return 2; }
  systemctl "$action" "$unit" "$@"
}

ollama_api_version_json() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${2:-3}"
  ollama_timeout_cmd "${timeout_s}s" curl -fsS --connect-timeout "$timeout_s" --max-time "$timeout_s" "$base_url/api/version" 2>/dev/null
}

ollama_api_ready() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${2:-3}"
  ollama_api_version_json "$base_url" "$timeout_s" >/dev/null 2>&1
}

ollama_tags_json() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${2:-5}"
  ollama_timeout_cmd "${timeout_s}s" curl -fsS --connect-timeout "$timeout_s" --max-time "$timeout_s" "$base_url/api/tags" 2>/dev/null
}

ollama_model_names_common() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${2:-5}"
  ollama_tags_json "$base_url" "$timeout_s" | jq -r '.models[]? | (.name // .model // empty)' | awk 'NF' | sort -u
}

ollama_matching_models_common() {
  local pattern="${1:-}" base_url="${2:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${3:-5}" names matches
  [[ -n "$pattern" ]] || return 2
  names="$(ollama_model_names_common "$base_url" "$timeout_s" 2>/dev/null || true)"
  [[ -n "$names" ]] || return 4
  matches="$(printf '%s\n' "$names" | awk -v p="$pattern" '
    BEGIN{pl=tolower(p)}
    {n=$0; nl=tolower(n); split(n,a,":"); bl=tolower(a[1]); if(n==p || nl==pl || a[1]==p || bl==pl) print n}
  ' | sort -u)"
  if [[ -z "$matches" ]]; then
    matches="$(printf '%s\n' "$names" | awk -v p="$pattern" '
      BEGIN{pl=tolower(p)}
      {n=$0; if(index(tolower(n),pl)>0) print n}
    ' | sort -u)"
  fi
  [[ -n "$matches" ]] || return 4
  printf '%s\n' "$matches"
}

ollama_resolve_model_common() {
  local pattern="${1:-}" base_url="${2:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${3:-5}" matches count
  matches="$(ollama_matching_models_common "$pattern" "$base_url" "$timeout_s")" || return $?
  count="$(printf '%s\n' "$matches" | awk 'NF{c++} END{print c+0}')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$matches" | awk 'NF{print; exit}'
    return 0
  fi
  printf '%s\n' "$matches"
  return 5
}

ollama_command_for_model() {
  local script_cmd="${1:-ollama-test-and-monitor-RTX3090.sh}" model="${2:-}" role="${3:-generate}" cmd
  if [[ "$role" == "embedding" ]]; then
    case "$script_cmd" in
      "ollama test"|ollama\ test) cmd="ollama embed-test" ;;
      *ollama-test-and-monitor-RTX3090.sh*) cmd="$script_cmd"; printf '%s %q --embedding
' "$cmd" "$model"; return 0 ;;
      *) cmd="$script_cmd"; printf '%s %q --embedding
' "$cmd" "$model"; return 0 ;;
    esac
    printf '%s %q
' "$cmd" "$model"
  else
    printf '%s %q
' "$script_cmd" "$model"
  fi
}

ollama_print_model_commands() {
  local script_cmd="${1:-ollama-test-and-monitor-RTX3090.sh}" models="${2:-}" prefix="${3:-  - }" base_url="${4:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${5:-5}" model role
  if [[ -z "$models" ]]; then
    echo "  (none detected)"
    return 0
  fi
  while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    role="$(ollama_model_role_common "$model" "$base_url" "$timeout_s" 2>/dev/null || printf 'unknown')"
    printf '%s%s  role=%s  ->  ' "$prefix" "$model" "$role"
    ollama_command_for_model "$script_cmd" "$model" "$role"
  done <<<"$models"
}

ollama_print_available_model_commands() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" script_cmd="${2:-ollama-test-and-monitor-RTX3090.sh}" timeout_s="${3:-5}" tags names model role size_bytes size_gib cmd
  tags="$(ollama_tags_json "$base_url" "$timeout_s" 2>/dev/null || true)"
  names="$(printf '%s
' "$tags" | jq -r '.models[]? | (.name // .model // empty)' 2>/dev/null | awk 'NF' | sort -u || true)"
  echo "Available local Ollama models at $base_url:"
  if [[ -z "$names" ]]; then
    echo "  (none detected)"
    return 0
  fi
  printf '  %-32s %-10s %-8s %s
' "MODEL" "ROLE" "SIZE" "SUGGESTED COMMAND"
  printf '  %-32s %-10s %-8s %s
' "-----" "----" "----" "-----------------"
  while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    role="$(ollama_model_role_common "$model" "$base_url" "$timeout_s" 2>/dev/null || printf 'unknown')"
    size_bytes="$(printf '%s
' "$tags" | jq -r --arg m "$model" '.models[]? | select((.name // .model)==$m or .model==$m or .name==$m) | (.size // empty)' 2>/dev/null | head -1)"
    if [[ -n "$size_bytes" && "$size_bytes" =~ ^[0-9]+$ ]]; then
      size_gib="$(awk -v b="$size_bytes" 'BEGIN{printf "%.1fGB", b/1000000000}')"
    else
      size_gib="n/a"
    fi
    cmd="$(ollama_command_for_model "$script_cmd" "$model" "$role")"
    printf '  %-32s %-10s %-8s %s
' "$model" "$role" "$size_gib" "$cmd"
  done <<<"$names"
}

ollama_status_short_common() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" timeout_s="${2:-3}" version service_state service_enabled load_state
  echo "Ollama status:"
  if ollama_system_service_exists; then
    service_state="$(systemctl is-active ollama.service 2>/dev/null || true)"
    service_enabled="$(systemctl is-enabled ollama.service 2>/dev/null || true)"
    load_state="$(ollama_system_service_load_state || true)"
    echo "  service: system ollama.service load=${load_state:-unknown} active=${service_state:-unknown} enabled=${service_enabled:-unknown}"
  elif ollama_user_service_exists; then
    service_state="$(systemctl --user is-active ollama.service 2>/dev/null || true)"
    service_enabled="$(systemctl --user is-enabled ollama.service 2>/dev/null || true)"
    echo "  service: user ollama.service active=${service_state:-unknown} enabled=${service_enabled:-unknown}"
  elif ollama_systemctl_available; then
    echo "  service: ollama.service not found by systemctl"
  else
    echo "  service: systemctl not available"
  fi

  if version="$(ollama_api_version_json "$base_url" "$timeout_s" 2>/dev/null)"; then
    if command -v jq >/dev/null 2>&1; then
      echo "  api:     RUNNING $base_url version=$(jq -r '.version // "unknown"' <<<"$version" 2>/dev/null)"
    else
      echo "  api:     RUNNING $base_url"
    fi
  else
    echo "  api:     NOT RUNNING at $base_url"
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    local gpu_line
    gpu_line="$(ollama_timeout_cmd 2s nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -F',' 'NR==1{for(i=1;i<=NF;i++)gsub(/^ +| +$/, "", $i); printf "%s temp=%sC vram=%s/%sMiB util=%s%%", $1,$2,$3,$4,$5}')"
    [[ -n "$gpu_line" ]] && echo "  gpu:     $gpu_line" || echo "  gpu:     nvidia-smi not responding"
  else
    echo "  gpu:     nvidia-smi not found"
  fi
}

ollama_print_start_hint() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}"
  echo "Ollama API is not reachable at $base_url. Tests were not run."
  if ollama_system_service_exists; then
    echo "Start:  sudo systemctl start ollama"
    echo "Check:  systemctl status ollama --no-pager"
    echo "Logs:   journalctl -u ollama -n 120 --no-pager"
  elif ollama_user_service_exists; then
    echo "Start:  systemctl --user start ollama"
    echo "Check:  systemctl --user status ollama --no-pager"
    echo "Logs:   journalctl --user -u ollama -n 120 --no-pager"
  elif command -v ollama >/dev/null 2>&1; then
    echo "Start:  ollama serve"
    echo "Check:  curl -fsS $base_url/api/version && echo"
  else
    echo "Install/check Ollama CLI first: command not found: ollama"
  fi
}
