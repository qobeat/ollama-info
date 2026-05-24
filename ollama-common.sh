#!/usr/bin/env bash
# Shared helpers for ollama-info scripts. Source this file; do not execute directly.

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
  local script_cmd="${1:-ollama-test-and-monitor-RTX3090.sh}" model="${2:-}"
  printf '%s %q\n' "$script_cmd" "$model"
}

ollama_print_model_commands() {
  local script_cmd="${1:-ollama-test-and-monitor-RTX3090.sh}" models="${2:-}" prefix="${3:-  - }" model
  if [[ -z "$models" ]]; then
    echo "  (none detected)"
    return 0
  fi
  while IFS= read -r model; do
    [[ -n "$model" ]] || continue
    printf '%s%s  ->  ' "$prefix" "$model"
    ollama_command_for_model "$script_cmd" "$model"
  done <<<"$models"
}

ollama_print_available_model_commands() {
  local base_url="${1:-${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}}" script_cmd="${2:-ollama-test-and-monitor-RTX3090.sh}" timeout_s="${3:-5}" names
  names="$(ollama_model_names_common "$base_url" "$timeout_s" 2>/dev/null || true)"
  echo "Available local Ollama models at $base_url:"
  ollama_print_model_commands "$script_cmd" "$names" "  - "
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
