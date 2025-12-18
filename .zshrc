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
# user aliases, functions, completions, paths
# --------------------------------------------------

[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases
[ -f ~/.zsh_functions ] && source ~/.zsh_functions
[ -f ~/.zsh_completions ] && source ~/.zsh_completions

# --------------------------------------------------
# environment paths
# --------------------------------------------------
