## Memory limits on agents

Each Claude Code session runs in its own systemd scope (`claude-<pid>.scope`),
and each Bash tool command in its own `run-*.scope`, all under the user slice
`agents.slice`. The slice has a hard memory ceiling below the machine's RAM,
and each scope has its own smaller one.

A command that exceeds its limit is killed by the kernel's OOM killer, exits
143 or 137, and prints `[process-cap] killed after ...s, before the runtime
cap; most likely the memory limit`. Reduce parallelism (`-j`, test workers)
rather than retrying unchanged.

```bash
journalctl --user -g "OOM killer" --since -1d   # which scope was killed
systemd-cgtop /user.slice/user-$(id -u).slice/user@$(id -u).service/agents.slice
```

The limits live in `workstation/agents/memory-cap.nix`.
