# --------------------------------------------------
# ~/.bashrc
# --------------------------------------------------
# bash initialization file for interactive shells
# non-login interactive shells source this file
# login shells should source ~/.bash_profile

# --------------------------------------------------
#  interactive shell guard
# --------------------------------------------------
[[ $- != *i* ]] && return

# --------------------------------------------------
# system-wide configuration
# --------------------------------------------------
# source global bash definitions if provided by the system
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# --------------------------------------------------
# user-specific environment (PATH)
# --------------------------------------------------
# ensure user-local bin directories are in PATH
case ":$PATH:" in
    *":$HOME/.local/bin:$HOME/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$HOME/bin:$PATH" ;;
esac
export PATH

# --------------------------------------------------
# shell behavior & history (cluster-safe)
# --------------------------------------------------
HISTFILE="$HOME/.bash_history"
HISTSIZE=2000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# append history, preserve any system PROMPT_COMMAND
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# --------------------------------------------------
# editor
# --------------------------------------------------
if [[ -n "$SSH_CONNECTION" ]]; then
    export EDITOR=nvim
else
    export EDITOR=vim
fi

# --------------------------------------------------
# dotfiles (bare git repo)
# --------------------------------------------------

# dotfiles: git wrapper
dotfiles() { /usr/bin/git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"; }

# dotfiles: git-style tab completion (git completion already loaded)
if declare -F __git_complete >/dev/null 2>&1; then
  if ! declare -F _dotfiles_complete >/dev/null 2>&1; then
    _dotfiles_complete() { GIT_DIR="$HOME/.dotfiles" GIT_WORK_TREE="$HOME" __git_main; }
  fi
  __git_complete dotfiles _dotfiles_complete
fi

# --------------------------------------------------
# persistent ssh-agent (login nodes only)
# --------------------------------------------------
SSH_AGENT_ENV="$HOME/.ssh/agent.env"

if [[ -n "$SSH_CONNECTION" ]]; then
    mkdir -p "$HOME/.ssh"

    # load existing agent environment
    if [[ -f "$SSH_AGENT_ENV" ]]; then
        source "$SSH_AGENT_ENV" >/dev/null
    fi

    # start agent only if missing or dead
    if [[ -z "$SSH_AUTH_SOCK" ]] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
        eval "$(ssh-agent -s)" >/dev/null
        {
            echo "export SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
            echo "export SSH_AGENT_PID=$SSH_AGENT_PID"
        } > "$SSH_AGENT_ENV"
        chmod 600 "$SSH_AGENT_ENV"
    fi

    # add key only once, never inside tmux
    if [[ -z "$TMUX" ]]; then
        ssh-add -l 2>/dev/null | grep -q id_ed25519 || \
            ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null
    fi
fi

# --------------------------------------------------
# user aliases / functions
# --------------------------------------------------
[[ -f ~/.bash_aliases ]]   && source ~/.bash_aliases
[[ -f ~/.bash_functions ]] && source ~/.bash_functions

# --------------------------------------------------
# tmux auto-attach (SSH only, never nest)
# --------------------------------------------------
if [[ -n "$SSH_CONNECTION" ]]; then
    if [[ ! -d "$HOME/.tmux" ]]; then
        mkdir -p "$HOME/.tmux"
        chmod 700 "$HOME/.tmux"
    fi
    export TMUX_TMPDIR="$HOME/.tmux"

    if [[ -z "$TMUX" ]]; then
        tmux attach -t elwe || tmux new -s elwe
    fi
fi

# -----------------------------------------------------------------------
# filename expansion & tab completion (interactive safety)
# -----------------------------------------------------------------------

# safer globbing: fail if a pattern matches nothing
shopt -s failglob

# enable recursive globbing with **
shopt -s globstar

# improve tab completion behavior
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'
bind 'TAB:menu-complete'

