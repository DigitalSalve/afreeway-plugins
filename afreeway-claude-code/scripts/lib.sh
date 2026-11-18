# Shared by the plugin's scripts. POSIX sh: macOS, Linux, Git Bash (MSYS).
# Sourced, never run.
#
# One path. The session id comes from Claude Code's own record, read only:
# <config dir>/sessions/<pid>.json, the one whose messagingSocketPath is
# CLAUDE_CODE_MESSAGING_SOCKET. The parent comes from AFREEWAY_PARENT_SESSION, which
# the session that started this one exported through CLAUDE_ENV_FILE. Both are
# undocumented or internal to Claude Code: with no fallback, if they change, sessions
# fail with a reason in the log until the plugin is updated. See the README.

af_valid_id() {
  case $1 in
    '' | *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 80 ]
}

# The inherited AFREEWAY_PARENT_SESSION when it is a valid session id, else nothing.
af_inherited() {
  if af_valid_id "${AFREEWAY_PARENT_SESSION:-}"; then
    printf '%s' "$AFREEWAY_PARENT_SESSION"
  fi
}

# Appends one line to plugin.log: 0600, cut short past 32 KB. It says why something
# failed, and never holds a session id. Writes to stderr if there is nowhere to put it.
af_log() {
  dir=${AFREEWAY_STATE_DIR:-}
  if [ -z "$dir" ]; then
    base=${XDG_STATE_HOME:-}
    case $base in
      /*) ;;
      *) base=${HOME:+$HOME/.local/state} ;;
    esac
    dir=${base:+$base/afreeway}
  fi
  if [ -z "$dir" ] || ! (umask 077 && mkdir -p -- "$dir") 2>/dev/null || [ -L "$dir/plugin.log" ]; then
    printf 'afreeway plugin: %s\n' "$1" >&2
    return 0
  fi
  log=$dir/plugin.log
  if [ -f "$log" ] && [ "$(wc -c <"$log" 2>/dev/null || echo 0)" -gt 32768 ]; then
    tail -n 100 "$log" >"$log.tmp" 2>/dev/null && mv -f -- "$log.tmp" "$log"
  fi
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$1" >>"$log" 2>/dev/null
  chmod 600 "$log" 2>/dev/null
  return 0
}

# Prints one line, id|pid|entrypoint|startedAt|folder|procStart, for each of Claude Code's session
# records whose messagingSocketPath is the value in AF_SOCK. folder is the last part of cwd, never the
# path. procStart is last, so a | in it stays in it. A strict JSON scan, so a partial or
# mid-write file matches nothing; only top-level fields count, so text in another field
# can't pass for one. A file past 64 KB is dropped unread: the scan would outlast Claude
# Code's 10-second limit on it. Nothing but these six fields is kept or printed.
# shellcheck disable=SC2016 # awk's own variables
AF_RECORD_AWK='
function skip() { while (i <= n && index(" \t\r\n", substr(t, i, 1)) > 0) i++ }
function str(   c, s, h) {
  if (substr(t, i, 1) != "\"") return 0
  s = ++i
  while (i <= n) {
    c = substr(t, i, 1)
    if (c == "\"") { raw = substr(t, s, i - s); i++; kind = "s"; return 1 }
    if (c < " ") return 0
    if (c == "\\") {
      c = substr(t, i + 1, 1)
      if (c == "u") {
        h = substr(t, i + 2, 4)
        if (h !~ /^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) return 0
        i += 6
      } else {
        if (index("\"\\/bfnrt", c) == 0 || c == "") return 0
        i += 2
      }
    } else i++
  }
  return 0
}
function value(depth,   c, rest) {
  if (depth > 32) return 0
  skip()
  c = substr(t, i, 1)
  if (c == "{") return object(depth + 1)
  if (c == "[") return array(depth + 1)
  if (c == "\"") return str()
  rest = substr(t, i, 40)
  if (match(rest, /^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?)/) != 1) return 0
  raw = substr(rest, 1, RLENGTH)
  kind = (raw ~ /^[0-9]+$/) ? "n" : "l"
  i += RLENGTH
  return 1
}
function array(depth) {
  i++
  skip()
  if (substr(t, i, 1) == "]") { i++; kind = "o"; return 1 }
  while (1) {
    if (!value(depth)) return 0
    skip()
    if (substr(t, i, 1) == "]") { i++; kind = "o"; return 1 }
    if (substr(t, i, 1) != ",") return 0
    i++
  }
}
function object(depth,   key) {
  i++
  skip()
  if (substr(t, i, 1) == "}") { i++; kind = "o"; return 1 }
  while (1) {
    skip()
    if (!str()) return 0
    key = raw
    skip()
    if (substr(t, i, 1) != ":") return 0
    i++
    if (!value(depth)) return 0
    if (depth == 1 && (key == "messagingSocketPath" || key == "sessionId" || key == "pid" || key == "entrypoint" || key == "procStart" || key == "startedAt" || key == "cwd")) {
      if (key in val) return 0
      val[key] = (kind == "s" || kind == "n") ? raw : ""
      typ[key] = kind
    }
    skip()
    if (substr(t, i, 1) == "}") { i++; kind = "o"; return 1 }
    if (substr(t, i, 1) != ",") return 0
    i++
  }
}
function unescape(s,   out, j, c, h) {
  out = ""
  j = 1
  while (j <= length(s)) {
    c = substr(s, j, 1)
    if (c != "\\") { out = out c; j++; continue }
    c = substr(s, j + 1, 1)
    if (c == "u") {
      h = substr(s, j + 2, 4)
      if (h ~ /^00[0-7]/) out = out sprintf("%c", hexval(substr(h, 3, 1)) * 16 + hexval(substr(h, 4, 1)))
      else out = out "\\u" h
      j += 6
      continue
    }
    if (c == "n") c = "\n"
    else if (c == "t") c = "\t"
    else if (c == "r") c = "\r"
    else if (c == "b") c = "\b"
    else if (c == "f") c = "\f"
    out = out c
    j += 2
  }
  return out
}
function hexval(c) { return index("0123456789abcdef", tolower(c)) - 1 }
function done(   base, entry, pid, started, proc, folder) {
  if (name == "" || big) return
  base = name
  sub(/.*\//, "", base)
  if (base !~ /^[0-9]+\.json$/) return
  n = length(t)
  i = 1
  split("", val)
  split("", typ)
  skip()
  if (substr(t, i, 1) != "{" || !object(1)) return
  skip()
  if (i <= n) return
  if (typ["messagingSocketPath"] != "s" || typ["sessionId"] != "s") return
  if (unescape(val["messagingSocketPath"]) != ENVIRON["AF_SOCK"]) return
  if (val["sessionId"] !~ /^[A-Za-z0-9-]+$/ || length(val["sessionId"]) > 80) return
  entry = (typ["entrypoint"] == "s" && val["entrypoint"] ~ /^[A-Za-z0-9_-]+$/) ? val["entrypoint"] : ""
  pid = (typ["pid"] == "n") ? val["pid"] : ""
  started = (typ["startedAt"] == "s" || typ["startedAt"] == "n") ? val["startedAt"] : ""
  if (started ~ /[^0-9A-Za-z.:+-]/) started = ""
  proc = (typ["procStart"] == "s" || typ["procStart"] == "n") ? val["procStart"] : ""
  folder = (typ["cwd"] == "s") ? unescape(val["cwd"]) : ""
  gsub(/\\/, "/", folder)
  sub(/\/+$/, "", folder)
  sub(/.*\//, "", folder)
  gsub(/[^ -~]|\|/, "", folder)
  print val["sessionId"] "|" pid "|" entry "|" started "|" folder "|" proc
}
FNR == 1 { done(); name = FILENAME; t = ""; big = 0 }
big { next }
length(t) + length($0) > 65536 { big = 1; t = ""; next }
{ t = t $0 "\n" }
END { done() }
'

# Runs that over the records in CLAUDE_CONFIG_DIR, else ~/.claude, for the value in $1.
# Only <pid>.json; the .key files beside them are never opened. We never write there.
af_record_lines() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    cfg=$CLAUDE_CONFIG_DIR
    case $cfg in
      /* | [A-Za-z]:*) ;;
      *) cfg=./$cfg ;;
    esac
  elif [ -n "${HOME:-}" ]; then
    cfg=$HOME/.claude
  else
    return 0
  fi
  sock=$1
  set -- "$cfg"/sessions/[0-9]*.json
  [ -f "$1" ] || return 0
  AF_SOCK=$sock LC_ALL=C awk "$AF_RECORD_AWK" "$@" 2>/dev/null
}

# SHA-256 of stdin as 64 lowercase hex characters, with whichever tool is here. Fails, printing
# nothing, when none works. The input never goes in a tool's arguments.
af_sha256() {
  af_in=$(cat; printf x)
  af_in=${af_in%x}
  for af_tool in 'shasum -a 256' sha256sum 'openssl dgst -sha256'; do
    command -v "${af_tool%% *}" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2086 # the tool and its flags
    af_h=$(printf '%s' "$af_in" | $af_tool 2>/dev/null) || continue
    case $af_tool in
      openssl*) af_h=${af_h##*= } ;;
      *) af_h=${af_h%% *} ;;
    esac
    case $af_h in
      '' | *[!0-9a-f]*) continue ;;
    esac
    if [ "${#af_h}" -eq 64 ]; then
      printf '%s' "$af_h"
      return 0
    fi
  done
  return 1
}

# The proof a listener is this session's, from fields of its record: $1 procStart, $2 startedAt,
# $3 messagingSocketPath. The one place this string is built: the helper sends the result on signed-in
# calls and the wake hook presents it, so they can't drift. Never log the result or its inputs.
# Fails, printing nothing, when a field is missing or nothing can hash.
af_wake_proof() {
  [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return 1
  printf 'afreeway-wake-proof-v1\n%s\n%s\n%s' "$1" "$2" "$3" | af_sha256
}

# True on Git Bash and the like, where $PPID is an MSYS pid and the record's is a Windows
# one (pidDomain win32:...), so they can't be compared.
af_is_windows() {
  case $(uname -s 2>/dev/null) in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac
  return 1
}

# The parent of $PPID when $PPID is a shell, from /proc: a dash that runs the helper
# without exec stands between it and Claude Code. Only a shell, or a child claude run
# directly by its parent would pass for it. Prints nothing where there is no /proc.
# AF_PROC is for the tests.
af_shell_parent() {
  stat=${AF_PROC:-/proc}/$PPID/stat
  [ -r "$stat" ] || return 0
  line=''
  IFS= read -r line <"$stat"
  comm=${line#*\(}
  comm=${comm%\)*}
  case $comm in
    sh | dash | bash | ash | zsh | ksh | mksh | busybox) ;;
    *) return 0 ;;
  esac
  # shellcheck disable=SC2086 # the fields after the name: state, then ppid
  set -- ${line##*\) }
  case ${2:-} in
    '' | *[!0-9]*) return 0 ;;
  esac
  printf '%s' "$2"
}

# The label: AFREEWAY_LABEL when it is 1-40 printable ASCII characters, else the working
# directory's name (cut to 40).
af_session_label() {
  if [ -n "${AFREEWAY_LABEL:-}" ]; then
    clean=$(af_clean_label "$AFREEWAY_LABEL")
    if [ "$clean" = "$AFREEWAY_LABEL" ]; then
      printf '%s' "$clean"
      return 0
    fi
  fi
  # The session's folder, from its record ($1). This script's own folder is the plugin's.
  af_clean_label "${1:-$(basename -- "$PWD")}"
}

# Printable ASCII only, at most 40 characters; empty when nothing is left.
af_clean_label() {
  printf '%s' "$1" | LC_ALL=C tr -cd ' -~' | cut -c1-40
}

# The surface this Claude Code runs in, for X-Afreeway-Surface: CLAUDE_CODE_ENTRYPOINT (cli,
# claude-desktop, sdk-ts, ...) or, when that is unset, $1, the entrypoint from Claude Code's
# record, as one lowercase token of a-z 0-9 -, at most 32 characters, starting with a letter,
# plus "+remote" when CLAUDE_CODE_REMOTE is "true" (a cloud session). Prints nothing and fails
# when neither leaves a valid token. Display only; the server never trusts it.
af_surface() {
  s=$(printf '%s' "${CLAUDE_CODE_ENTRYPOINT:-${1:-}}" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -cd 'a-z0-9-' | cut -c1-32)
  case $s in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  [ "${CLAUDE_CODE_REMOTE:-}" = true ] && s=$s+remote
  printf '%s' "$s"
}

af_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
