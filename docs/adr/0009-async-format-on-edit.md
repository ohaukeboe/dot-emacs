# ADR 0009: Format-on-edit queues a job in Emacs and the hook polls for it

**Status:** Accepted (2026-10-30).

## Context

The Claude Code format-on-edit hook (`workstation/agents/format-on-edit.nix`
and `.el`) formats each edited file through its language server and reports
the file's diagnostics to the agent. It used to do the work inside
`emacsclient --eval`. That call holds Emacs's main thread until it returns,
and the Elisp waited in `sit-for` loops for a server, for the format and for
the checkers. Every agent edit froze the user's Emacs for seconds, and up to
the 25 s timeout on a cold server. See spec `dot-emacs-555`.

## Decision

**Queue and poll.** `emacsclient --eval` only queues a job (a `run-at-time 0`
timer) and returns. Emacs then does the work through timers and server
callbacks. It starts the server without waiting for it, sends
`textDocument/formatting` with `lsp-request-async` or
`jsonrpc-async-request`, and applies the edits in the callback. It then
collects diagnostics by polling from timers. When it is done it writes the
report file, then a separate done marker. The hook's shell side polls for the
marker, then emits the report as `additionalContext`. Emacs waits at most
about 10 s for a cold server to offer formatting. Past that it skips
formatting but still reports. A watchdog finishes any job after 22 s, under
the shell's 24 s poll deadline and the hook's 30 s timeout.

Async work can finish after the file has moved on, so every job carries an ID
per file and the file's modification time when queued. Formatting is saved
only if the job is still the newest for its file, the modification time is
unchanged and the buffer has no unsaved edits.

**Rejected: fire and forget.** The hook could queue the job and exit at once,
which is simpler. But the agent would then never see diagnostics for the
edit it just made, only stale ones on a later edit. Getting errors before the
next step is the reason the hook exists, so the shell side waits and Emacs
does not.

**The lsp-mcp tools return early instead.** The lsp-mcp MCP tools have the
same freeze. They cannot use this design, because mcp-server-lib has no async
tools: a tool handler must return its result synchronously, inside Emacs. On
a cold server they therefore return "starting; retry in a few seconds" at
once, and cap requests at 3 s. The agent's retry stands in for the shell's
poll.

## Consequences

- The user's Emacs stays responsive during agent edits. A job costs only the
  short slices of work between timers and callbacks.
- The hook has two halves that must agree on the protocol: report first, then
  the marker, and a shell deadline above the Elisp one.
- Formatting can be dropped silently when edits overlap. The newest job still
  formats the final text.
- A cold server keeps starting after its job gives up, so the next edit
  usually finds it warm.
- `format-on-edit-test.el` (`nix build .#test-format-on-edit`) covers the
  Elisp side through its entry point. The shell polling is thin and has no
  separate test.
