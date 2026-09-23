## Runtime cap on shell commands

Every command you run through the Bash tool runs inside a transient systemd
scope with a runtime limit. When the limit is reached the command gets a
`SIGTERM`, and a hard `SIGKILL` a few seconds later if it is still alive. The
whole process tree goes with it, including children that outlived their parent.

- Foreground commands: 1 hour.
- Commands started with `run_in_background`: 4 hours.

A command killed this way exits 143 (or 137) and prints a
`[process-cap] terminated after the ... runtime cap` line on stderr, so a capped
hang is distinguishable from an ordinary failure.

This exists because a hung command used to survive its session indefinitely —
the Bash tool's own timeout moves a slow command to a background task rather
than killing it, and three orphans were once found burning two cores for five
days.

### Opting a command out

Prefix the command with `nocap ` when it genuinely must outlive the cap, for
example when starting a daemon on purpose:

```bash
nocap emacs --daemon=scratch
```

The token is stripped before the command runs. Use it sparingly: an
agent-started daemon is usually disposable, and the cap is what stops it from
being forgotten.

### Reading kills back

```bash
journalctl --user -g claude-cap --since -7d
```

Each entry names the command, the allowance that applied, and whether it hit
the limit. If a legitimate build was killed, that is the evidence for raising
the allowance in `workstation/agents/process-cap.nix`.
