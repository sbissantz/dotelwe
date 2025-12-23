# --------------------------------------------------
# ~/.bashrc
# --------------------------------------------------
# bash initialization file for interactive shells
# non-login interactive shells source this file
# login shells should source ~/.bash_profile

# --------------------------------------------------
# interactive shell guard
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
# user-specific environment
# --------------------------------------------------
# ensure user-local bin directories are in PATH
case ":$PATH:" in
    *":$HOME/.local/bin:$HOME/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$HOME/bin:$PATH" ;;
esac
export PATH

# --------------------------------------------------
# optional system behavior
# --------------------------------------------------
# disable systemctl's automatic pager if desired
# export SYSTEMD_PAGER=

# --------------------------------------------------
# user-specific aliases and functions
# --------------------------------------------------
# define aliases and functions here
# or source separate files for maintainability

