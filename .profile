########################################################################
# ~/.profile
#
# This file is read by *login shells*.
# It is traditionally used by sh/bash and sometimes by batch systems.
#
# Purpose here:
# On many HPC clusters, R is started with user startup files disabled
# (--no-environ), so ~/.Renviron and ~/.Rprofile are ignored unless
# R_ENVIRON_USER and R_PROFILE_USER are set *before* R starts.
#
# These environment variables tell R where to find the user's
# startup files and must be exported in the shell environment.
#########################################################################

# Path to the user's R environment file
export R_ENVIRON_USER="$HOME/.R/.Renviron"

# Path to the user's R profile file
export R_PROFILE_USER="$HOME/.R/Rprofile"
