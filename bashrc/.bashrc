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
# v1.8: command logic lives in ollama-info/scripts/ollama.sh to avoid bashrc/script duplication.
for __p in "$HOME/dev/ollama-info/scripts" "$HOME/dev/ollama-info" "$HOME/bin"; do
  if [ -d "$__p" ]; then case ":$PATH:" in *":$__p:"*) ;; *) PATH="$__p:$PATH" ;; esac; fi
done
unset __p
export PATH
export OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

__ollama_info_cli() {
  if command -v ollama.sh >/dev/null 2>&1; then
    command ollama.sh "$@"
  elif command -v ollama >/dev/null 2>&1; then
    command ollama "$@"
  else
    echo "ERROR: ollama.sh and native ollama CLI are not available" >&2
    return 127
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
ollama_bench() { __ollama_info_cli bench "$@"; }
ollama_embed_test() { __ollama_info_cli embed-test "$@"; }

if [ "${OLLAMA_BASHRC_WRAP_CLI:-1}" = "1" ]; then
  ollama() { __ollama_info_cli "$@"; }
fi

alias os='ollama_status'
alias oq='ollama_quick_status'
alias ost='ollama_start'
alias osp='ollama_stop'
alias om='ollama_models'
alias og='ollama_gpu'
alias ol='ollama_logs'
alias ot='ollama_test'
alias ob='ollama_bench'
alias oet='ollama_embed_test'

if [[ $- == *i* && "${OLLAMA_BASHRC_STATUS:-1}" == "1" && -z "${OLLAMA_STATUS_SHOWN:-}" ]]; then
  export OLLAMA_STATUS_SHOWN=1
  echo
  ollama_quick_status || true
fi
