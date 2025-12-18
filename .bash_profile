# --------------------------------------------------
# ~/.bash_profile
# --------------------------------------------------
# login shell initialization file
# executed for ssh logins and login shells
# this file is posix-compatible for cluster safety

# source bashrc if it exists
# this ensures aliases, paths, and environment are loaded
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

# On many HPC clusters, R is started with user startup files disabled
# (--no-environ), so ~/.Renviron and ~/.Rprofile are ignored unless
# R_ENVIRON_USER and R_PROFILE_USER are set *before* R starts.

# Path to the user's R environment file
export R_ENVIRON_USER="$HOME/.R/.Renviron"

# Path to the user's R profile file
export R_PROFILE_USER="$HOME/.R/Rprofile"

# --------------------------------------------------
# switch to zsh for interactive use
# --------------------------------------------------
# clusters often restrict chsh, so we exec zsh manually
# this replaces bash with zsh (no subshell)
# the -l flag starts zsh as a login shell
# the check prevents infinite recursion

export SHELL="$(command -v zsh)"
[ -z "$ZSH_VERSION" ] && exec "$SHELL" -l

