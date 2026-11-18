#!/bin/sh
# afreeway SessionStart hook. Passes this session's id on to its children: Claude Code
# sources CLAUDE_ENV_FILE before each Bash command, so a claude started there inherits
# AFREEWAY_PARENT_SESSION. Prints nothing: SessionStart stdout would be added to the
# model's context.
exec >/dev/null 2>&1
umask 077
here=$(dirname -- "$0")
. "$here/lib.sh" || exit 0

input=$(cat 2>/dev/null)
# The hook's input first: it is this event's own, where the environment can hold a value
# a child inherited.
sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9-]*\)".*/\1/p' | head -n 1)
af_valid_id "$sid" || sid=${CLAUDE_CODE_SESSION_ID:-}
if ! af_valid_id "$sid"; then
  af_log "session-start: children get no parent link: Claude Code gave no valid session id"
  exit 0
fi
if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
  af_log "session-start: children get no parent link: CLAUDE_ENV_FILE is not set"
  exit 0
fi

# Skipped when it is already the last line, as on a resume. The id is checked above, so
# the line holds nothing a shell would act on.
line="export AFREEWAY_PARENT_SESSION=$sid"
if [ "$(tail -n 1 "$CLAUDE_ENV_FILE" 2>/dev/null)" != "$line" ]; then
  printf '\n%s\n' "$line" >>"$CLAUDE_ENV_FILE" || af_log "session-start: children get no parent link: could not write CLAUDE_ENV_FILE"
fi
exit 0
