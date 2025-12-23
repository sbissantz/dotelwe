# --------------------------------------------------
# ~/.bash_profile
# --------------------------------------------------
# login shell initialization file for bash
# executed for ssh logins and login shells
# kept posix-compatible for cluster safety

# --------------------------------------------------
# source global login environment
# --------------------------------------------------
# .profile defines environment variables and
# hands off to zsh when appropriate

if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
elif [ -t 1 ]; then
    echo "note: ~/.profile not found"
fi

# --------------------------------------------------
# interactive bash fallback
# --------------------------------------------------
# if we remain in bash (e.g. zsh unavailable),
# source bashrc for interactive behavior

if [ -n "$BASH_VERSION" ] && [[ $- == *i* ]]; then
    [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi

