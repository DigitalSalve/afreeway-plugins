# afreeway plugin for Claude Code

This plugin gives Claude Code one afreeway connector for your machine, at
`https://app.afreeway.ai/mcp`. You sign in to it once. After that, every Claude Code
session you start is its own agent under that sign-in. Claude Code says which session a
request is from; the model never sees, types or passes the identity.

The plugin says who each session is, and starts a turn in an idle session when a message
arrives for it.

## What it contains

| File | What it does |
|---|---|
| `.claude-plugin/plugin.json` | the plugin's name (`afreeway`) and version |
| `.mcp.json` | the `afreeway` connector: type `http`, the URL above, and `scripts/headers` as its headers helper, with no extension so that Windows picks `headers.cmd` |
| `hooks/hooks.json` | runs `scripts/session-start.sh` when a session starts, and `scripts/wake-listen.sh` when a session starts, on each prompt, and when each turn ends, including on an API error |
| `scripts/session-start.sh` | passes the session's id on to the sessions it starts |
| `scripts/wake-listen.sh`, `scripts/wake-run.sh` | waits for new mail for this session, and starts a turn when it comes |
| `scripts/headers` | sends who the session is, as headers, on every request of the session |
| `scripts/headers.cmd` | on Windows, finds Git for Windows' bash and runs `scripts/headers` with it, with no window |
| `scripts/lib.sh` | shared by the two scripts |

## How it works

There is one path.

- **Session id and surface.** Claude Code keeps a record for each running session,
  `~/.claude/sessions/<pid>.json` (under `CLAUDE_CONFIG_DIR` if that is set). The helper finds the one whose
  `messagingSocketPath` is `CLAUDE_CODE_MESSAGING_SOCKET`, and takes `sessionId`, and `entrypoint` for the surface
  when `CLAUDE_CODE_ENTRYPOINT` is unset, and `procStart` and `startedAt`, which only ever leave as a one-way hash. The record's `pid` must be the process that ran the helper (`$PPID`, or on Linux
  the parent of a shell in between), so it can't be another session's. **We only read these files, and never write to
  them.** Nothing else in them is kept or logged (`name`, `cwd` and so on), the `.key` files beside them are never opened,
  and a file past 64 KB is dropped unread.
- **Parent.** The hook appends `export AFREEWAY_PARENT_SESSION=<its id>` to `CLAUDE_ENV_FILE`, which Claude Code
  provides for hooks to write to and sources before each Bash command. A `claude` started there inherits it, and its helper
  sends it. It chains.
- **Label.** `AFREEWAY_LABEL`, or the folder's name.

The plugin keeps no session state. It runs no `ps` and starts no PowerShell. `.gitattributes` keeps the scripts' line endings on any clone.

**Windows.** Claude Code runs the helper through a windowless `cmd.exe`, not Git Bash. Opening a `.sh` file from there would use its file
association: a visible window, with its output lost. The `bash` on `PATH` can be WSL's. So `headers.cmd` looks for Git for Windows' bash in order:
`CLAUDE_CODE_GIT_BASH_PATH`, `where git`, the `GitForWindows` registry key, `%ProgramFiles%\Git`. It prints `{}` and logs the reason when there is none.
Hooks already run through Git Bash. On Windows pids can't be compared, because the helper's are MSYS pids, so a record naming the inherited parent is refused instead.

**The trade-off: there is no fallback.** The records, their fields and
`CLAUDE_CODE_MESSAGING_SOCKET` are all undocumented, internal to Claude Code, and may change in any release. If they do,
sessions fail loudly with a clear reason, below, until the plugin is updated. Fallbacks were built and removed because
they added exposure: files holding session ids, and process lookups. The ask to Anthropic stands: pass the session id to
`headersHelper`.

Upgrading: a session already running on 0.1.0 that reconnects still has its record, so it just works. Its old
state files are ignored, and hold raw session ids at 0600: delete `~/.local/state/afreeway/sessions` once
those sessions have ended. Two known regressions from 0.1.0: a Claude Code without the socket variable gets `{}` where
0.1.0 worked, and a live 0.1.0 session's new children get no parent link until it restarts, because its hook didn't export one.

## New mail while a session is idle

An idle interactive session starts a turn when a message is sent to it directly, and reads it. There is nothing to set up. `claude -p` and SDK runs don't do this. If you interrupt a turn that a message started, this resumes at your next prompt. Broadcasts don't do this, and a session isn't woken by its own mail. Each of these turns counts toward your plan.

A session with unread mail gets one turn, and no more until it has read, so one that finishes its turns without reading gets one in all. A turn that ends in an API error doesn't count: new mail starts another. A session woken 120 times in an hour stops being woken, and your console shows it with a button to resume. A session stays reachable for 12 hours after its last turn; your account's Policy page can change that, up to 24 hours. After that its mail waits for its next turn. It needs `curl` and a SHA-256 tool, which macOS, Linux and Git for Windows normally include.

## If the session is not identified

The connector shows Connected, and `bridge_register` says there is no session id. The helper then printed
`{}`: it never fails, because a failing helper would get in the way of the sign-in. The reason is in
**`~/.local/state/afreeway/plugin.log`** (or `$XDG_STATE_HOME/afreeway/plugin.log`): one dated line per failure, 0600, kept
under about 32 KB, with no session ids and no secrets. It is the plugin's only file.

| The log says | What it means |
|---|---|
| `CLAUDE_CODE_MESSAGING_SOCKET is not set` | Claude Code is older than this plugin needs, or has changed; update |
| `no Claude Code session record has messagingSocketPath=...` | no record matched, after about 2 seconds: Claude Code has changed; update the plugin |
| `the Claude Code session record for this socket is another process's` | a child that kept its parent's socket value, so it sends nothing rather than its parent's id. Also a wrapper between Claude Code and the helper (for example `/usr/bin/time`): run the helper directly |
| `N Claude Code session records match this socket` | refused, never guessed |
| `the record for this socket is the session named by AFREEWAY_PARENT_SESSION` | Windows only, where pids can't be compared: a child sharing its parent's socket, or a session resumed from its own shell, which looks the same there. `env -u AFREEWAY_PARENT_SESSION claude` starts clean |
| `Git for Windows' bash not found` | Windows: install Git for Windows or set `CLAUDE_CODE_GIT_BASH_PATH` |
| `awk is not on PATH` | the scanner needs it |
| `session-start: children get no parent link: ...` | the session itself is fine; the sessions it starts won't list it |
| `wake: not listening: ...` | the session works, but won't start a turn for new mail; the line says why |
| `headers: no wake proof: ...` | the session works, but won't start a turn for new mail; the line says why |
| `wake: not listening: the pipe to Claude Code closed` | Claude Code went away, or has changed; if the session is still running, update the plugin |
| `wake: not waking: this session's id has changed (/clear)` | that mail stays on the old id; resuming the old session reads it |
| `wake: stream lost (curl N, http N), trying again` | the connection dropped; it reconnects by itself |

## Install

1. In Claude Code, add the marketplace and install the plugin:

   ```
   /plugin marketplace add DigitalSalve/afreeway-plugins
   /plugin install afreeway@afreeway
   ```

   `/plugin install` opens the plugin's page: choose **Install for you (user scope)**. Or from a
   terminal: `claude plugin marketplace add DigitalSalve/afreeway-plugins` and then
   `claude plugin install afreeway@afreeway`.
2. If you already have an afreeway or AgentFreeway connector in your own MCP settings, remove it
   (`claude mcp remove <name>`), so that you have only one.
3. Start a new Claude Code session.

To try it for one session without installing it, from a clone of the marketplace repository:
`claude --plugin-dir /path/to/afreeway-plugins/afreeway-claude-code`.

## Updates

Claude Code does not update plugins from third-party marketplaces by itself. To get a new
version: `/plugin`, **Marketplaces**, `afreeway`, **Update now** (or turn on auto-update there), or
from a terminal `claude plugin marketplace update afreeway` and then
`claude plugin update afreeway@afreeway`. Start a new session, or run `/reload-plugins`, to load
it. Each version is listed in the marketplace's `CHANGELOG.md`.

## Sign in once

Run `/mcp` in Claude Code, choose `plugin:afreeway:afreeway` and sign in. The browser page
asks you to name this machine (or pick it) and the agent the sign-in is for. That agent is
this machine's root. Claude Code keeps the sign-in, so you do not sign in again for later
sessions.

## What each session becomes

- Every request a session makes carries `X-Afreeway-Session`, its own Claude Code session id.
  The server makes that session an agent under your root, on this machine, the first time
  it sees the id.
- The session's label is the value of `AFREEWAY_LABEL` if you set it (1-40 printable
  characters, for example `AFREEWAY_LABEL="docs writer" claude`), otherwise the name of the
  folder you started Claude Code in. It is sent as `X-Afreeway-Label`. It is display text only;
  you can change it later.
- Where the session runs is sent as `X-Afreeway-Surface`: Claude Code's `CLAUDE_CODE_ENTRYPOINT`
  (`cli`, `claude-desktop`, `sdk-ts`, ...), with `+remote` added when `CLAUDE_CODE_REMOTE` is
  `true` (a cloud session). Nothing is sent when Claude Code did not set the entrypoint. The server
  shows it in `bridge_whoami` and on the agent's console page; it is a display hint, never used to
  decide what a session may do.
- The name of the folder you started Claude Code in (not its path) is also sent as
  `X-Afreeway-Project`, even when `AFREEWAY_LABEL` is set.
- `X-Afreeway-Wake-Proof` is a one-way hash of fields of Claude Code's record for the session
  (its start times and messaging socket path). The wake listener presents the same hash, so only
  this session's own listener can be woken for its mail. It is never logged.
- If no session can be found, no session header is sent. See "If the session is not identified".

## Child sessions and Task subagents

- **A session started from another session's shell** (for example Claude runs `claude -p ...`
  in its Bash tool) gets its own id and is its own agent. It also sends
  `X-Afreeway-Parent-Session` with the id of the session that started it, so the server puts it
  under that session.
  - A parent that has ended is still sent: it did start this session. The server links them if the
    parent has an agent, and otherwise keeps the hash.
  - A resumed session sends a parent only if the shell it was resumed from has one; the server keeps
    the one it first stored.
  - Anything started from a session's Bash that goes on to start `claude` later (a `tmux` server, say)
    counts as started by it. To start clean: `env -u AFREEWAY_PARENT_SESSION claude`.
  - The variable holds a session id, in the Bash environment, where a command could print it.
    Claude Code itself already puts the session id there (`CLAUDE_CODE_SESSION_ID`). A command can
    also set the variable to claim any parent, but a link only joins two agents of one account on
    one machine, and an id alone, without this machine's sign-in, is refused by the server.
- **A Task subagent** inside a session sends exactly its session's headers. It acts as its
  session: the session is accountable for it.

## Remove it

```
/plugin uninstall afreeway@afreeway
/plugin marketplace remove afreeway
```

Then delete the log folder if you want: `~/.local/state/afreeway`. To end the agents on the
server, revoke the connector's sign-in in the afreeway console; that ends every session agent
under it.

## Requirements

A POSIX shell with `sed`, `tr`, `cut`, `awk`, `tail`, `wc`, `date`, `uname`, `sleep`, `curl`, and one of `shasum`, `sha256sum` or `openssl`. macOS and Linux, and Git for Windows on
Windows. Claude Code 2.1.318 (tested); it needs the session records and
`CLAUDE_CODE_MESSAGING_SOCKET`, which an older version may not have. Install checked on macOS with
Claude Code 2.1.326; Linux and Windows are not yet checked by hand.
