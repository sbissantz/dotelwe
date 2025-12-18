# --------------------------------------------------
# ~/.bashrc
# --------------------------------------------------
# bash initialization file for interactive shells
# this file is sourced for non-login interactive shells
# login shells source ~/.bash_profile, which in turn
# should source this file

# --------------------------------------------------
# system-wide configuration
# --------------------------------------------------
# source global bash definitions if provided by the system
# this may define default aliases, functions, or behavior
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# --------------------------------------------------
# user-specific environment
# --------------------------------------------------
# ensure user-local bin directories are in PATH
# prepend them only if not already present to avoid duplicates
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# --------------------------------------------------
# optional system behavior
# --------------------------------------------------
# uncomment to disable systemctl's automatic pager
# useful on minimal or remote systems
# export SYSTEMD_PAGER=

# --------------------------------------------------
# user-specific aliases and functions
# --------------------------------------------------
# aliases and functions may be defined below or sourced
# from separate files (recommended for maintainability)
