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
export PATH="$HOME/bin:$PATH"
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"

# Node/NVM for local coding tools
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# --- Ollama status: RTX 3090 local AI runtime ---
__ollama_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"; else "$@"; fi
}

__ollama_systemd_available() {
  command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= 2>/dev/null | grep -qx systemd
}

__ollama_api_url() {
  printf '%s\n' "${OLLAMA_URL:-http://127.0.0.1:11434}"
}

ollama_quick_status() {
  local url version
  url="$(__ollama_api_url)"
  echo "=== Ollama quick status ==="
  if command -v ollama >/dev/null 2>&1; then
    echo "cli     : $(command -v ollama)"
  else
    echo "cli     : NOT FOUND"
    return 1
  fi

  if __ollama_systemd_available; then
    printf 'service : '
    systemctl is-active ollama 2>/dev/null || true
    printf 'enabled : '
    systemctl is-enabled ollama 2>/dev/null || true
  fi

  printf 'api     : '
  if version="$(__ollama_timeout 1s curl -fsS "$url/api/version" 2>/dev/null)"; then
    printf '%s %s\n' "$url" "$version"
  else
    printf 'NOT RESPONDING at %s\n' "$url"
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    printf 'gpu     : '
    __ollama_timeout 1s nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -F',' '{gsub(/^ +| +$/, "", $1); gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4); gsub(/^ +| +$/, "", $5); printf "%s temp=%sC vram=%s/%sMiB util=%s%%\n", $1,$2,$3,$4,$5}' \
      || echo "nvidia-smi not responding"
  fi
  echo "commands: ollama_status | ollama_models | ollama_gpu | ollama_logs [N] | ollama_test <model-pattern>"
}

ollama_models() {
  ollama list
}

ollama_gpu() {
  nvidia-smi --query-gpu=timestamp,name,driver_version,temperature.gpu,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,memory.total,pcie.link.gen.current,pcie.link.width.current --format=csv
}

ollama_logs() {
  local lines="${1:-120}"
  if __ollama_systemd_available && systemctl list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    journalctl -u ollama -n "$lines" --no-pager
  elif __ollama_systemd_available && systemctl --user list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    journalctl --user -u ollama -n "$lines" --no-pager
  elif [ -f "$HOME/log/ollama-serve.log" ]; then
    tail -n "$lines" "$HOME/log/ollama-serve.log"
  else
    echo "No known Ollama log source found. Try: systemctl status ollama"
    return 1
  fi
}

ollama_status() {
  echo "=== Ollama full status ==="
  ollama_quick_status
  echo
  echo "Ollama CLI version:"
  ollama --version 2>/dev/null || true
  echo
  echo "Loaded models / runners:"
  ollama ps 2>/dev/null || true
  echo
  echo "Downloaded models:"
  ollama list 2>/dev/null || true
  echo
  echo "Recent service logs:"
  ollama_logs 40 2>/dev/null || true
}

ollama_test() {
  local pattern="${1:-}"
  if [ -z "$pattern" ]; then
    echo "Usage: ollama_test <model-pattern> [extra ollama-test-and-monitor-RTX3090.sh options]"
    echo "Example: ollama_test qwen3.6 --no-conc"
    return 2
  fi
  shift || true
  ollama-test-and-monitor-RTX3090.sh "$pattern" "$@"
}

alias os='ollama_status'
alias om='ollama_models'
alias og='ollama_gpu'
alias ol='ollama_logs'
alias ot='ollama_test'

# Show fast status once per interactive terminal. Disable with: export OLLAMA_BASHRC_STATUS=0
if [[ $- == *i* && "${OLLAMA_BASHRC_STATUS:-1}" == "1" && -z "${OLLAMA_STATUS_SHOWN:-}" ]]; then
  export OLLAMA_STATUS_SHOWN=1
  echo
  ollama_quick_status
fi
