# --------------------------------------------------
# ~/.bash_profile
# --------------------------------------------------
# login shell initialization file
# executed for ssh logins and login shells
# this file is posix-compatible for cluster safety


# source profile if it exists
if [ -f ~/.profile ]; then
    . ~/.profile
elif [ -t 1 ]; then
    echo "note: ~/.profile not found"
fi

# --------------------------------------------------
# switch to zsh for interactive use
# --------------------------------------------------
# clusters often restrict chsh, so we exec zsh manually
# this replaces bash with zsh (no subshell)
# the -l flag starts zsh as a login shell
# the check prevents infinite recursion

# source bashrc if it exists
# this ensures aliases, paths, and environment are loaded
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
