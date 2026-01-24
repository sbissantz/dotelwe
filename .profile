# --------------------------------------------------
# ~/.profile
# --------------------------------------------------
# login shell initialization file
# read by login shells (sh, bash, zsh -l) and sometimes by batch systems

# --------------------------------------------------
# preferred interactive shell
# --------------------------------------------------
# exec zsh if available and not already running
# avoids subshells and infinite recursion
if [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then
    exec zsh -l
fi

# --------------------------------------------------
# r environment configuration
# --------------------------------------------------
# centralize r configuration files

export R_ENVIRON_USER="$HOME/.R/.Renviron"
export R_PROFILE_USER="$HOME/.R/Rprofile"
