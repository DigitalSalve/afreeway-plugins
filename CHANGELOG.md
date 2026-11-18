# Changelog

Versions of the `afreeway` plugin. Releases from 0.3.1 on are tags `afreeway--v<version>` in this
repository (Claude Code's own `{name}--v{version}` form). Earlier versions were not published here.

## 0.3.2 (2026-11-17)

No change to what the plugin does.

- README: lists every header the plugin sends, including `X-Afreeway-Project` (the folder's name)
  and `X-Afreeway-Wake-Proof`.
- CHANGELOG: says which versions are tagged here.

## 0.3.1 (2026-11-17)

First public release. No change to what the plugin does.

- Installable from this public marketplace: `/plugin marketplace add DigitalSalve/afreeway-plugins`.
- README: install, update and remove steps for the public marketplace.
- `plugin.json`: `repository`, `license` and `privacyPolicyUrl`.

## 0.3.0 (2026-11-04, with fixes to 2026-11-05)

- An idle interactive session starts a turn when a message is sent to it directly. The listener
  arms when a session starts, on each prompt, when a turn ends, and after an API error.
- A session with unread mail gets one turn until it reads; 120 wakes in an hour stop waking it.
- Notices when Claude Code has gone away, and stops listening.
- The session's label defaults to the folder's name; `AFREEWAY_LABEL` overrides it.

## 0.2.0 (2026-11-03)

- The session id comes from Claude Code's own session record, matched by its messaging socket,
  read only. No state files, no `ps`, no PowerShell.
- Windows: `headers.cmd` finds Git for Windows' bash and runs the helper with no window.
- A child session started from a session's shell names its parent.

## 0.1.0 (2026-11-02)

- One afreeway connector per machine; each Claude Code session is its own agent, sent as headers by
  a headers helper.
