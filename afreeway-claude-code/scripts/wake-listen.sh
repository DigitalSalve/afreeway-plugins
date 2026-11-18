#!/bin/sh
# afreeway wake listener: the hook on SessionStart, UserPromptSubmit, Stop and StopFailure, with asyncRewake.
# Exit 2 starts a turn, so it must mean one thing only. A shell exits 2 by itself on its own errors (under dash:
# a missing or broken file sourced, a closed stdout redirected), and that would start turns with no server to
# stop them. So all the work is in wake-run.sh, in a subshell, and only its one real wake line exits 42.
here=$(dirname -- "$0")
(. "$here/wake-run.sh")
[ $? -eq 42 ] && exit 2
exit 0
