# --------------------------------------------------
# ~/.zshrc
# --------------------------------------------------
# interactive zsh configuration

# --------------------------------------------------
# interactive shell guard
# --------------------------------------------------
[[ -o interactive ]] || return

# --------------------------------------------------
# safety
# --------------------------------------------------

# disable builtin log to avoid conflicts
disable log

# --------------------------------------------------
# history
# --------------------------------------------------

histfile="$HOME/.zsh_history"
histsize=2000
savehist=1000

setopt hist_ignore_dups
setopt hist_reduce_blanks
setopt share_history

# --------------------------------------------------
# key bindings
# --------------------------------------------------

# emacs-style line editing
bindkey -e
# vi-style alternative:
# bindkey -v

# --------------------------------------------------
# prompt
# --------------------------------------------------

PS1="%n@%m %1~ %# "

# --------------------------------------------------
# system terminal integration
# --------------------------------------------------

if [[ -n "$TERM_PROGRAM" ]] && [[ -r "/etc/zshrc_$TERM_PROGRAM" ]]; then
    source "/etc/zshrc_$TERM_PROGRAM"
fi

# --------------------------------------------------
# completion system
# --------------------------------------------------
#
autoload -Uz compinit
compinit

# --------------------------------------------------
# dotfile management (bare git repo)
# --------------------------------------------------
# note: order of commands matters here!

setopt complete_in_word
setopt complete_aliases

alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# --------------------------------------------------
# persistent ssh agent (session-wide)
# --------------------------------------------------

SSH_AGENT_ENV="$HOME/.ssh/agent.env"
mkdir -p "$HOME/.ssh"

# load existing agent environment
if [[ -f "$SSH_AGENT_ENV" ]]; then
    source "$SSH_AGENT_ENV" >/dev/null
fi

# start agent only if none exists
if [[ -z "$SSH_AUTH_SOCK" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
    {
        echo "export SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
        echo "export SSH_AGENT_PID=$SSH_AGENT_PID"
    } >| "$SSH_AGENT_ENV"
    chmod 600 "$SSH_AGENT_ENV"
fi

# add key only once, never inside tmux
if [[ -z "$TMUX" ]]; then
    ssh-add -l 2>/dev/null | grep -q id_ed25519 || \
        ssh-add "$HOME/.ssh/id_ed25519"
fi

# --------------------------------------------------
# user aliases, functions, completions
# --------------------------------------------------

[[ -f ~/.zsh_aliases ]]     && source ~/.zsh_aliases
[[ -f ~/.zsh_functions ]]   && source ~/.zsh_functions
[[ -f ~/.zsh_completions ]] && source ~/.zsh_completions

# --------------------------------------------------
# tmux auto-attach (last!)
# --------------------------------------------------

if [[ -z "$TMUX" ]] && [[ -n "$SSH_CONNECTION" ]]; then
    tmux attach -t elwe || tmux new -s elwe
fi

