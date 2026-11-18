## Memory limits on agents

Each Claude Code session runs in its own systemd scope (`claude-<pid>.scope`)
under the user slice `agents.slice`. Bash tool commands run inside the session's
scope when sandboxed, and in their own `run-*.scope` in the slice otherwise.
The slice has one hard memory ceiling for all agents together, below the
machine's RAM. Sessions and commands have no limit of their own.

When the agents together exceed the ceiling, the kernel's OOM killer kills the
largest process in the slice. A command killed this way exits 143 or 137 and
prints `[process-cap] killed after ...s, before the runtime cap; most likely
the memory limit`. Reduce parallelism (`-j`, test workers) rather than retrying
unchanged.

```bash
journalctl --user -g "OOM killer" --since -1d   # what was killed
systemd-cgtop /user.slice/user-$(id -u).slice/user@$(id -u).service/agents.slice
```

The limit lives in `workstation/agents/memory-cap.nix`.
