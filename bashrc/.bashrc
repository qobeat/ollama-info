# ~/.bashrc: executed by bash(1) for non-login shells.
# Safe for WSL2 + systemd-managed Ollama.
case $- in *i*) ;; *) return ;; esac
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then debian_chroot=$(cat /etc/debian_chroot); fi
case "$TERM" in xterm-color|*-256color) color_prompt=yes ;; esac
if [ -n "${force_color_prompt:-}" ]; then if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then color_prompt=yes; else color_prompt=; fi; fi
if [ "${color_prompt:-}" = yes ]; then PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '; else PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '; fi
unset color_prompt force_color_prompt
case "$TERM" in xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;; esac
if [ -x /usr/bin/dircolors ]; then test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"; alias ls='ls --color=auto'; alias grep='grep --color=auto'; alias fgrep='fgrep --color=auto'; alias egrep='egrep --color=auto'; fi
alias ll='ls -alF'; alias la='ls -A'; alias l='ls -CF'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
alias crs='cursor .'; alias uz=unzip-gpt.sh
[ -f ~/.bash_aliases ] && . ~/.bash_aliases
if ! shopt -oq posix; then [ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion; [ -f /etc/bash_completion ] && . /etc/bash_completion; fi

# Keep Ollama SERVER tuning in systemd overrides. This file only adds client helpers.
for __p in "$HOME/dev/ollama-info/scripts" "$HOME/dev/ollama-info" "$HOME/bin"; do
  if [ -d "$__p" ]; then case ":$PATH:" in *":$__p:"*) ;; *) PATH="$__p:$PATH" ;; esac; fi
done
unset __p
export PATH
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

__ollama_timeout() { local seconds="$1"; shift; if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"; else "$@"; fi; }
__ollama_api_ready() { __ollama_timeout 2s curl -fsS "${OLLAMA_URL:-http://127.0.0.1:11434}/api/version" >/dev/null 2>&1; }
__ollama_have_cmd() { command -v "$1" >/dev/null 2>&1; }
__ollama_systemctl_available() { command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; }
__ollama_system_service_exists() {
  __ollama_systemctl_available || return 1
  local state out
  state="$(systemctl show -p LoadState --value ollama.service 2>/dev/null | awk 'NF{print; exit}' || true)"
  [ -n "$state" ] && [ "$state" != "not-found" ] && return 0
  systemctl cat ollama.service >/dev/null 2>&1 && return 0
  out="$(systemctl list-unit-files ollama.service --no-legend --no-pager 2>/dev/null || true)"; printf '%s\n' "$out" | awk '$1=="ollama.service"{found=1} END{exit found?0:1}' && return 0
  out="$(systemctl list-units --all ollama.service --no-legend --no-pager 2>/dev/null || true)"; printf '%s\n' "$out" | awk '$1=="ollama.service"{found=1} END{exit found?0:1}' && return 0
  out="$(systemctl status ollama.service --no-pager 2>/dev/null || true)"; printf '%s\n' "$out" | grep -Eq 'Loaded:[[:space:]]+loaded|ollama\.service[[:space:]]+-' && return 0
  [ -f /etc/systemd/system/ollama.service ] || [ -f /usr/lib/systemd/system/ollama.service ] || [ -f /lib/systemd/system/ollama.service ]
}
__ollama_sudo_systemctl() { local action="${1:-}" unit="${2:-ollama.service}"; [ -n "$action" ] || { echo "ERROR: missing systemctl action" >&2; return 2; }; if [ "$(id -u)" = "0" ]; then systemctl "$action" "$unit"; elif command -v sudo >/dev/null 2>&1; then echo "Privilege required: sudo systemctl $action $unit"; sudo -v && sudo systemctl "$action" "$unit"; else echo "ERROR: sudo required for systemctl $action $unit" >&2; return 126; fi; }
ollama_start() { if __ollama_have_cmd ollama-start; then command ollama-start "$@"; elif __ollama_system_service_exists; then __ollama_sudo_systemctl start ollama.service; else mkdir -p "$HOME/log"; nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 & fi; }
ollama_stop() { if __ollama_have_cmd ollama-stop; then command ollama-stop "$@"; elif __ollama_system_service_exists; then __ollama_sudo_systemctl stop ollama.service; else pkill -TERM -f "ollama runner" 2>/dev/null || true; pkill -TERM -f "ollama serve" 2>/dev/null || true; fi; }
ollama_quick_status() { if __ollama_have_cmd ollama-status; then command ollama-status --brief; return $?; fi; echo "Ollama quick status:"; if __ollama_system_service_exists; then printf '  service: '; systemctl is-active ollama.service 2>/dev/null || true; fi; printf '  api:     '; if __ollama_api_ready; then echo "RUNNING ${OLLAMA_URL:-http://127.0.0.1:11434}"; else echo "NOT RUNNING at ${OLLAMA_URL:-http://127.0.0.1:11434}"; fi; if command -v nvidia-smi >/dev/null 2>&1; then printf '  gpu:     '; __ollama_timeout 2s nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk -F',' '{for(i=1;i<=NF;i++)gsub(/^ +| +$/, "", $i); printf "%s temp=%sC vram=%s/%sMiB util=%s%%\n", $1,$2,$3,$4,$5}' || echo "nvidia-smi not responding"; fi; }
ollama_status() { if __ollama_have_cmd ollama-status; then command ollama-status "$@"; else ollama_quick_status; echo; command ollama ps 2>/dev/null || true; echo; command ollama list 2>/dev/null || true; fi; }
ollama_models() { if __ollama_api_ready; then if __ollama_have_cmd ollama-status; then OLLAMA_MODEL_COMMAND="ollama test" command ollama-status --models; else command ollama list; fi; else echo "Ollama API is not reachable at ${OLLAMA_URL:-http://127.0.0.1:11434}."; if __ollama_system_service_exists; then echo "Start: sudo systemctl start ollama"; else echo "Start: ollama serve"; fi; return 3; fi; }
ollama_gpu() { nvidia-smi --query-gpu=timestamp,name,driver_version,temperature.gpu,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,memory.total,pcie.link.gen.current,pcie.link.width.current --format=csv; }
ollama_logs() { local lines="${1:-120}"; if command -v journalctl >/dev/null 2>&1 && __ollama_system_service_exists; then journalctl -u ollama -n "$lines" --no-pager; elif [ -f "$HOME/log/ollama-serve.log" ]; then tail -n "$lines" "$HOME/log/ollama-serve.log"; else echo "No known Ollama log source found. Try: systemctl status ollama --no-pager"; return 1; fi; }
ollama_test() { local pattern="${1:-}"; if [ -z "$pattern" ]; then echo "Usage: ollama test <model-pattern> [extra options]"; echo "Example: ollama test qwen3.6"; return 2; fi; shift || true; if __ollama_have_cmd ollama-test-and-monitor-RTX3090.sh; then command ollama-test-and-monitor-RTX3090.sh "$pattern" "$@"; else echo "ERROR: ollama-test-and-monitor-RTX3090.sh not found. Add ~/dev/ollama-info/scripts to PATH." >&2; return 127; fi; }
ollama_embed_test() { local pattern="${1:-}"; if [ -z "$pattern" ]; then echo "Usage: ollama embed-test <model-pattern> [extra options]"; echo "Example: ollama embed-test bge-m3"; return 2; fi; shift || true; if __ollama_have_cmd ollama-embed-test-RTX3090.sh; then command ollama-embed-test-RTX3090.sh "$pattern" "$@"; elif __ollama_have_cmd ollama-test-and-monitor-RTX3090.sh; then command ollama-test-and-monitor-RTX3090.sh "$pattern" --embedding "$@"; else echo "ERROR: ollama-embed-test-RTX3090.sh not found. Add ~/dev/ollama-info/scripts to PATH." >&2; return 127; fi; }

if [ "${OLLAMA_BASHRC_WRAP_CLI:-1}" = "1" ] && __ollama_have_cmd ollama; then
  ollama() { local __sub="${1:-}"; case "$__sub" in status) shift; ollama_status "$@" ;; start) shift; ollama_start "$@" ;; stop) shift; ollama_stop "$@" ;; logs|log) shift; ollama_logs "$@" ;; models) shift; ollama_models "$@" ;; gpu) shift; ollama_gpu "$@" ;; test) shift; ollama_test "$@" ;; embed-test|embedtest|embedding-test) shift; ollama_embed_test "$@" ;; *) command ollama "$@" ;; esac; }
fi
alias os='ollama_status'; alias oq='ollama_quick_status'; alias ost='ollama_start'; alias osp='ollama_stop'; alias om='ollama_models'; alias og='ollama_gpu'; alias ol='ollama_logs'; alias ot='ollama_test'; alias oet='ollama_embed_test'
if [[ $- == *i* && "${OLLAMA_BASHRC_STATUS:-1}" == "1" && -z "${OLLAMA_STATUS_SHOWN:-}" ]]; then export OLLAMA_STATUS_SHOWN=1; echo; ollama_quick_status; fi
