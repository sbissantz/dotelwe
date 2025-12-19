# --------------------------------------------------
# ~/.profile
# --------------------------------------------------
# login shell initialization file. this file is read by login shells (sh, bash,
# zsh -l) and sometimes by batch systems on clusters.

# --------------------------------------------------
# locale 
# --------------------------------------------------
# use the portable C locale to avoid missing-locale warnings
# on minimal or hpc systems
export LANG=C
export LC_ALL=C

# --------------------------------------------------
# shell
# --------------------------------------------------
# define zsh as the preferred interactive shell
# clusters often restrict chsh, so we exec zsh manually
#
# this replaces the current shell with zsh (no subshell)
# the -l flag starts zsh as a login shell
# the guard prevents infinite recursion
export SHELL="$(command -v zsh)"
[ -z "$ZSH_VERSION" ] && exec "$SHELL" -l

# --------------------------------------------------
# r environment configuration
# --------------------------------------------------
# keep r configuration files out of $HOME clutter
# and define their locations explicitly. 

# path to the user's r environment file
export R_ENVIRON_USER="$HOME/.R/.Renviron"

# path to the user's r profile file
export R_PROFILE_USER="$HOME/.R/Rprofile"

