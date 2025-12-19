# --------------------------------------------------
# ~/.zshrc
# --------------------------------------------------
# zsh main configuration interactive shell entry point loads aliases,
# functions, and completions

# disable builtin log to avoid conflicts
disable log

# --------------------------------------------------
# history
# --------------------------------------------------

histfile=$HOME/.zsh_history
histsize=2000
savehist=1000
setopt complete_in_word 
setopt hist_ignore_dups
setopt hist_reduce_blanks
setopt share_history

# --------------------------------------------------
# key bindings
# --------------------------------------------------

# use emacs-style line editing with sane defaults
bindkey -e
# use vi-style line editing with sane defaults
# bindkey -v

# --------------------------------------------------
# prompt
# --------------------------------------------------

PS1="%n@%m %1~ %# "

# --------------------------------------------------
# system terminal integration
# --------------------------------------------------

[ -r "/etc/zshrc_$TERM_PROGRAM" ] && source "/etc/zshrc_$TERM_PROGRAM"

# Useful support for interacting with Terminal.app or other terminal programs
[ -r "/etc/zshrc_$TERM_PROGRAM" ] && . "/etc/zshrc_$TERM_PROGRAM"

# --------------------------------------------------
# dotfile management (bare git repo)
# --------------------------------------------------
# dotfile management with 'dotfiles' alias
# https://wiki.archlinux.org/index.php/Dotfiles
# use 'dotfiles status' to see the status of your dotfiles.
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
# the rest of the aliases live in ~/.zsh_aliases 

# --------------------------------------------------
# completion system (before custom completions)
# --------------------------------------------------

autoload -Uz compinit
compinit

# --------------------------------------------------
# persistent ssh agent (session-wide)
# --------------------------------------------------
# ensures exactly one ssh-agent per login session
# agent environment is reused across shells

SSH_AGENT_ENV="$HOME/.ssh/agent.env"

# load existing agent environment if present
if [ -f "$SSH_AGENT_ENV" ]; then
    . "$SSH_AGENT_ENV" >/dev/null
fi

# start a new agent if none is usable
if [ -z "$SSH_AUTH_SOCK" ] || ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
    echo "export SSH_AUTH_SOCK=$SSH_AUTH_SOCK" > "$SSH_AGENT_ENV"
    echo "export SSH_AGENT_PID=$SSH_AGENT_PID" >> "$SSH_AGENT_ENV"
    chmod 600 "$SSH_AGENT_ENV"
fi

# add github key if not already loaded
ssh-add -l | grep -q id_ed25519 2>/dev/null || \
    ssh-add "$HOME/.ssh/id_ed25519"


# --------------------------------------------------
# user aliases, functions, completions, paths
# --------------------------------------------------

[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases
[ -f ~/.zsh_functions ] && source ~/.zsh_functions
[ -f ~/.zsh_completions ] && source ~/.zsh_completions

# --------------------------------------------------
# rest goes here
# --------------------------------------------------
#
# ...
#
# --------------------------------------------------
# tmux auto-attach for interactive sessions
# --------------------------------------------------
# attach to existing tmux session or create one
# only for interactive shells and only if not already in tmux

if [[ -o interactive ]] && [[ -z "$TMUX" ]]; then
    tmux attach -t elwe || tmux new -s elwe
fi
