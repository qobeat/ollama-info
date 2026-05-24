# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# my aliases
alias crs='cursor .'
alias uz=unzip-gpt.sh

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Defaults for day-to-day coding
# Keep user-shell conveniences here. Keep Ollama SERVER tuning in systemd service overrides,
# because a systemd-managed ollama.service does not inherit ~/.bashrc.

# Prefer local project helpers first, then ~/bin. These checks avoid duplicate PATH entries.
for __p in "$HOME/dev/ollama-info" "$HOME/bin"; do
  if [ -d "$__p" ]; then
    case ":$PATH:" in
      *":$__p:"*) ;;
      *) PATH="$__p:$PATH" ;;
    esac
  fi
done
unset __p
export PATH

export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"

# Node/NVM for local coding tools
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# --- Ollama helpers: systemd-compatible client-side shortcuts only ---
__ollama_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"; else "$@"; fi
}

__ollama_api_ready() {
  __ollama_timeout 2s curl -fsS "${OLLAMA_URL:-http://127.0.0.1:11434}/api/version" >/dev/null 2>&1
}

__ollama_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

__ollama_systemctl_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1
}

__ollama_system_service_exists() {
  __ollama_systemctl_available || return 1
  local state out
  state="$(systemctl show -p LoadState --value ollama.service 2>/dev/null | awk 'NF{print; exit}' || true)"
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
  [ -f /etc/systemd/system/ollama.service ] && return 0
  [ -f /usr/lib/systemd/system/ollama.service ] && return 0
  [ -f /lib/systemd/system/ollama.service ] && return 0
  return 1
}

__ollama_sudo_systemctl() {
  local action="${1:-}" unit="${2:-ollama.service}"
  if [ -z "$action" ]; then echo "ERROR: missing systemctl action" >&2; return 2; fi
  if [ "$(id -u)" = "0" ]; then
    systemctl "$action" "$unit"
  elif command -v sudo >/dev/null 2>&1; then
    echo "Privilege required: sudo systemctl $action $unit"
    sudo -v && sudo systemctl "$action" "$unit"
  else
    echo "ERROR: sudo is required for: systemctl $action $unit" >&2
    return 126
  fi
}

ollama_start() {
  if __ollama_have_cmd ollama-start; then
    command ollama-start "$@"
  elif __ollama_system_service_exists; then
    __ollama_sudo_systemctl start ollama.service
  else
    mkdir -p "$HOME/log"
    nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 &
  fi
}

ollama_stop() {
  if __ollama_have_cmd ollama-stop; then
    command ollama-stop "$@"
  elif __ollama_system_service_exists; then
    __ollama_sudo_systemctl stop ollama.service
  else
    pkill -TERM -f "ollama runner" 2>/dev/null || true
    pkill -TERM -f "ollama serve" 2>/dev/null || true
  fi
}

ollama_quick_status() {
  if __ollama_have_cmd ollama-status; then
    command ollama-status --short
    return $?
  fi

  echo "=== Ollama quick status ==="
  if __ollama_system_service_exists; then
    printf 'service : '
    systemctl is-active ollama.service 2>/dev/null || true
    printf 'enabled : '
    systemctl is-enabled ollama.service 2>/dev/null || true
  fi
  printf 'api     : '
  if __ollama_api_ready; then
    echo "RUNNING ${OLLAMA_URL:-http://127.0.0.1:11434}"
  else
    echo "NOT RESPONDING at ${OLLAMA_URL:-http://127.0.0.1:11434}"
    if __ollama_have_cmd ollama-start; then echo "start   : ollama-start"; elif __ollama_system_service_exists; then echo "start   : sudo systemctl start ollama"; else echo "start   : ollama serve"; fi
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    printf 'gpu     : '
    __ollama_timeout 2s nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -F',' '{for(i=1;i<=NF;i++)gsub(/^ +| +$/, "", $i); printf "%s temp=%sC vram=%s/%sMiB util=%s%%\n", $1,$2,$3,$4,$5}' \
      || echo "nvidia-smi not responding"
  fi
}

ollama_status() {
  if __ollama_have_cmd ollama-status; then
    command ollama-status "$@"
  else
    ollama_quick_status
    echo
    ollama ps 2>/dev/null || true
    echo
    ollama list 2>/dev/null || true
  fi
}

ollama_models() {
  if __ollama_api_ready; then
    if __ollama_have_cmd ollama-status; then command ollama-status --models; else ollama list; fi
  else
    echo "Ollama API is not reachable at ${OLLAMA_URL:-http://127.0.0.1:11434}."
    if __ollama_system_service_exists; then echo "Start: sudo systemctl start ollama"; else echo "Start: ollama serve"; fi
    return 3
  fi
}

ollama_gpu() {
  nvidia-smi --query-gpu=timestamp,name,driver_version,temperature.gpu,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,memory.total,pcie.link.gen.current,pcie.link.width.current --format=csv
}

ollama_logs() {
  local lines="${1:-120}"
  if command -v journalctl >/dev/null 2>&1 && __ollama_system_service_exists; then
    journalctl -u ollama -n "$lines" --no-pager
  elif command -v journalctl >/dev/null 2>&1 && systemctl --user list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    journalctl --user -u ollama -n "$lines" --no-pager
  elif [ -f "$HOME/log/ollama-serve.log" ]; then
    tail -n "$lines" "$HOME/log/ollama-serve.log"
  else
    echo "No known Ollama log source found. Try: systemctl status ollama --no-pager"
    return 1
  fi
}

ollama_test() {
  local pattern="${1:-}"
  if [ -z "$pattern" ]; then
    echo "Usage: ollama_test <model-pattern> [extra ollama-test-and-monitor-RTX3090.sh options]"
    echo "Example: ollama_test qwen3.6 --no-conc"
    return 2
  fi
  shift || true
  if __ollama_have_cmd ollama-test-and-monitor-RTX3090.sh; then
    command ollama-test-and-monitor-RTX3090.sh "$pattern" "$@"
  else
    echo "ERROR: ollama-test-and-monitor-RTX3090.sh not found in PATH"
    echo "Add package directory to PATH or run it from ~/dev/ollama-info."
    return 127
  fi
}

# Optional convenience wrapper: keeps normal Ollama CLI behavior, but adds shell-only
# subcommands that the upstream CLI does not provide, e.g. `ollama status`.
# Disable before sourcing this file with: export OLLAMA_BASHRC_WRAP=0
if [ "${OLLAMA_BASHRC_WRAP:-1}" = "1" ]; then
  ollama() {
    case "${1:-}" in
      status) shift; ollama_status "$@" ;;
      start)  shift; ollama_start "$@" ;;
      stop)   shift; ollama_stop "$@" ;;
      models) shift; ollama_models "$@" ;;
      logs)   shift; ollama_logs "$@" ;;
      gpu)    shift; ollama_gpu "$@" ;;
      test)   shift; ollama_test "$@" ;;
      *)      command ollama "$@" ;;
    esac
  }
fi

alias os='ollama_status'
alias oq='ollama_quick_status'
alias ost='ollama_start'
alias osp='ollama_stop'
alias om='ollama_models'
alias og='ollama_gpu'
alias ol='ollama_logs'
alias ot='ollama_test'

# Optional compatibility wrapper for the upstream Ollama CLI.
# It makes `ollama status`, `ollama start`, `ollama stop`, etc. call the
# local helper functions while preserving normal upstream commands such as
# `ollama list`, `ollama pull`, `ollama run`, `ollama serve`, and `ollama ps`.
# Disable with: export OLLAMA_BASHRC_WRAP_CLI=0
if [ "${OLLAMA_BASHRC_WRAP_CLI:-1}" = "1" ] && __ollama_have_cmd ollama; then
  ollama() {
    local __sub="${1:-}"
    case "$__sub" in
      status) shift; ollama_status "$@" ;;
      start)  shift; ollama_start "$@" ;;
      stop)   shift; ollama_stop "$@" ;;
      logs|log) shift; ollama_logs "$@" ;;
      models) shift; ollama_models "$@" ;;
      gpu)    shift; ollama_gpu "$@" ;;
      test)   shift; ollama_test "$@" ;;
      *) command ollama "$@" ;;
    esac
  }
fi

# Show fast status once per interactive terminal. Disable with: export OLLAMA_BASHRC_STATUS=0
if [[ $- == *i* && "${OLLAMA_BASHRC_STATUS:-1}" == "1" && -z "${OLLAMA_STATUS_SHOWN:-}" ]]; then
  export OLLAMA_STATUS_SHOWN=1
  echo
  ollama_quick_status
fi
