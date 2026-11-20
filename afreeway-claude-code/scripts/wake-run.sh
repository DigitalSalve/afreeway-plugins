# afreeway wake listener, sourced in a subshell by wake-listen.sh, which turns exit 42 into exit 2.
# It runs on SessionStart, UserPromptSubmit, Stop and StopFailure, so an error or an interrupted turn recovers
# by the next prompt. The server keeps one per session. Holds one stream to the server until this session has
# mail. Exit 42 starts a turn, and that turn's Stop runs this again.
# README.md, "New mail while a session is idle", says what the user sees.
#
# The session id comes only from this hook's stdin, never from the environment or anything the
# model can set. The proof that this is that session's own listener is built from its session
# record, read only, the same way the helper builds it (lib.sh af_wake_proof). Both reach curl on
# stdin, so neither is in the process list, and neither ever goes in the log.
#
#   data: wake      exit 42, the only path that does, if this is still the session's id (not after /clear)
#   data: limit     exit 0. The next active turn listens again
#   data: replaced  exit 0. A newer listener took over
#   SIGTERM or SIGHUP (Claude Code exiting): one best-effort report, then exit 0. SessionEnd can't do this:
#   by then the session record is gone, so nothing there can build the proof. This process has it.
#   Its pipe to Claude Code closed (killed, say): the same, reported as "gone", not as an exit.
#   404             exit 0: unknown session, wrong proof, or wake is off. For a short while after
#                   SessionStart it tries again, as the helper's first call may not have landed
#   anything else   try again, backing off, until the limit would have passed
#
# Stdout is dropped: SessionStart stdout would be added to the model's context. Its pipe is kept as fd 4
# to notice Claude Code going away (below). Stderr is kept aside as fd 3 for the signal's one line, so
# a shell's "Terminated" can't reach it.
exec 4>&1 >/dev/null 3>&2 2>/dev/null
umask 077
[ -r "$here/lib.sh" ] || exit 0
. "$here/lib.sh" || exit 0

# A headless run has nobody to wake, and "claude -p" waits for this hook, so it would hang for up
# to a day (seen on 2.1.318). It also must not spend a catch-up signal on a run about to exit.
case ${CLAUDE_CODE_ENTRYPOINT:-} in
  sdk-*) exit 0 ;;
esac

input=$(cat 2>/dev/null)
sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9-]*\)".*/\1/p' | head -n 1)
if ! af_valid_id "$sid"; then
  af_log "wake: not listening: Claude Code gave no valid session id"
  exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
  af_log "wake: not listening: curl is not on PATH"
  exit 0
fi
event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n 1)
# A wake's own turn fires UserPromptSubmit too (seen on 2.1.318), with the notice as its prompt. It says
# nothing about a person being here. The server has its own guard, should this text ever change.
if [ "$event" = UserPromptSubmit ]; then
  case $input in
    *'<task-notification>'*) event=Wake ;;
  esac
fi

socket=${CLAUDE_CODE_MESSAGING_SOCKET:-}
if [ -z "$socket" ]; then
  af_log "wake: not listening: CLAUDE_CODE_MESSAGING_SOCKET is not set: Claude Code may have changed; update the plugin"
  exit 0
fi
# This session's record: the socket and the id must both match, and only one may. Claude Code
# writes the record in steps, and at startup this can run before it exists or before procStart
# and startedAt are in it, so it polls for about 15 seconds until the one record has both.
# AF_WAKE_RECORD_WAIT_S (whole seconds, 1..15, else 15) is for the tests; the headers helper has
# its own, AF_RECORD_WAIT_S. More than one match ends the wait: more waiting would not change it.
wait_n=${AF_WAKE_RECORD_WAIT_S:-15}
case $wait_n in
  '' | *[!0-9]* | 0) wait_n=15 ;;
esac
[ "$wait_n" -le 15 ] || wait_n=15
wait_n=$((wait_n * 4))
i=0
got=0
while :; do
  got=0
  rec_started=''
  rec_proc=''
  while IFS='|' read -r r_id _ _ r_started _ r_proc; do
    [ "$r_id" = "$sid" ] || continue
    got=$((got + 1))
    rec_started=$r_started
    rec_proc=$r_proc
  done <<EOF
$(af_record_lines "$socket")
EOF
  if [ "$got" -gt 1 ]; then break; fi
  if [ "$got" -eq 1 ] && [ -n "$rec_proc" ] && [ -n "$rec_started" ]; then break; fi
  if [ "$i" -ge "$wait_n" ]; then break; fi
  i=$((i + 1))
  sleep 0.25 2>/dev/null || { sleep 1; i=$((i + 3)); }
done
if [ "$got" -ne 1 ]; then
  af_log "wake: not listening: $got Claude Code session records match this session and its socket"
  exit 0
fi
if ! proof=$(af_wake_proof "$rec_proc" "$rec_started" "$socket"); then
  if [ -z "$rec_proc" ] || [ -z "$rec_started" ]; then
    af_log "wake: not listening: the session record lacks a field it needs: Claude Code may have changed; update the plugin"
  else
    af_log "wake: not listening: no working shasum, sha256sum or openssl"
  fi
  exit 0
fi

# The server is the connector's own URL, with /wake for /mcp: one place to change it.
url=$(sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\(https*:[^"]*\)\/mcp".*/\1/p' "$here/../.mcp.json" 2>/dev/null | head -n 1)
case $url in
  '' | *[!A-Za-z0-9:/._-]*)
    af_log "wake: not listening: no connector URL in the plugin's .mcp.json"
    exit 0
    ;;
esac
url=$url/wake

clock() {
  t=$(date +%s 2>/dev/null)
  case $t in
    '' | *[!0-9]*) echo 0 ;;
    *) echo "$t" ;;
  esac
}

# Is Claude Code still there? The one way that works on every OS with no process lookup: it holds the read
# end of our stdout pipe, so once it is gone a write there fails. $PPID won't do: on Git Bash it doesn't
# name Claude Code, and a dash that didn't exec stands between on Linux. A newline and one sleep every 2
# minutes is what it costs, and blank output from a hook is ignored. AF_WATCH_S is for the tests.
watch_s=${AF_WATCH_S:-120}
alive() {
  printf '\n' >&4
}

# Is the record still this session's? /clear gives the same process a new id, and a listener left from the old
# one must not wake the new conversation.
still_mine() {
  j=0
  while [ "$j" -lt 4 ]; do
    while IFS='|' read -r r_id _; do
      [ "$r_id" = "$sid" ] && return 0
    done <<EOF
$(af_record_lines "$socket")
EOF
    j=$((j + 1))
    sleep 0.25 2>/dev/null || sleep 1
  done
  return 1
}

# The report that this session is exiting, or with "gone" that only its pipe closed, which a Claude Code
# release could do to a live session, so it must not read as dead. Best effort: a second at most, and any
# later contact outranks it.
report_end() {
  printf 'url = "%s"\nheader = "X-Afreeway-Session: %s"\nheader = "X-Afreeway-Wake-Proof: %s"\nheader = "X-Afreeway-Wake-End: %s"\n' "$url" "$sid" "$proof" "${1:-ended}" |
    curl -s -X POST -o /dev/null -K - --max-time 1 2>/dev/null
}
trap 'report_end; exit 0' TERM HUP

started=$(clock)
until=0
delay=1
tries=0
nl='
'
while :; do
  now=$(clock)
  age=0
  [ "$started" -gt 0 ] && [ "$now" -ge "$started" ] && age=$((now - started))
  # No pipe on curl's output: it must exit by itself when the stream ends. No --fail: the status is needed.
  # A watcher ends it if Claude Code is killed outright, since nothing else would, for up to a day.
  # The watcher's output goes nowhere, or this capture would wait for it.
  out=$(
    printf 'url = "%s"\nheader = "X-Afreeway-Session: %s"\nheader = "X-Afreeway-Wake-Started: %s"\nheader = "X-Afreeway-Wake-Age: %s"\nheader = "X-Afreeway-Wake-Proof: %s"\nheader = "X-Afreeway-Wake-Event: %s"\n' \
      "$url" "$sid" "$started" "$age" "$proof" "$event" | curl -sN -K - -w '\n%{http_code}\n' --connect-timeout 30 --max-time 90000 2>/dev/null &
    c=$!
    (
      trap 'kill "$s" 2>/dev/null; exit 0' TERM
      trap '' PIPE
      while alive; do
        sleep "$watch_s" &
        s=$!
        wait "$s"
      done
      kill "$c" 2>/dev/null
    ) >/dev/null 2>&1 &
    w=$!
    wait "$c"
    rc=$?
    kill "$w" 2>/dev/null
    exit "$rc"
  )
  rc=$?
  code=${out##*"$nl"}
  # With curl killed there is no status line, but what the stream already said still counts.
  case $code in
    [0-9][0-9][0-9]) ;;
    *) code='' ;;
  esac
  if [ "$code" = 200 ] || [ -z "$code" ]; then
    case $out in
      *"data: wake"*)
        if ! still_mine; then
          af_log "wake: not waking: this session's id has changed (/clear), so its mail stays on the old id"
          report_end
          exit 0
        fi
        echo "You have new afreeway mail. Call bridge_read to read it." >&3
        exit 42
        ;;
      *"data: limit"* | *"data: replaced"*) exit 0 ;;
    esac
    case $out in
      *": ready limit="*)
        left=${out#*": ready limit="}
        left=${left%%"$nl"*}
        case $left in
          '' | *[!0-9]*) ;;
          *) until=$((now + left)) ;;
        esac
        ;;
    esac
  fi
  # A 404 ends it, but for a short while after SessionStart, when this can beat the helper's first
  # signed-in call to the server. It backs off below, so this is a handful of tries.
  if [ "$code" = 404 ]; then
    if [ "$event" != SessionStart ] || [ "$started" -eq 0 ] || [ $(($(clock) - started)) -ge 30 ]; then exit 0; fi
    [ "$delay" -gt 4 ] && delay=4
  fi

  # Lost, or the server failed. Never a wake from here.
  if ! (trap '' PIPE; alive); then
    af_log "wake: not listening: the pipe to Claude Code closed"
    report_end gone
    exit 0
  fi
  t=$(clock)
  [ "$until" -gt 0 ] && [ "$t" -ge "$until" ] && exit 0
  # Whatever the server said, a listener lasts no longer than a hook may: a day, or about that many
  # tries at the longest backoff if there is no clock.
  [ "$started" -gt 0 ] && [ $((t - started)) -ge 86400 ] && exit 0
  [ "$tries" -ge 1500 ] && exit 0
  [ $((t - now)) -ge 60 ] && delay=1
  [ "$tries" -eq 0 ] && [ "$code" != 404 ] && af_log "wake: stream lost (curl $rc, http ${code:-none}), trying again"
  tries=$((tries + 1))
  # Half fixed, half spread by this process's id, so sessions don't come back together.
  half=$((delay / 2 + 1))
  sleep $((half + ($$ + tries * 13) % half))
  delay=$((delay * 2))
  [ "$delay" -gt 60 ] && delay=60
done
