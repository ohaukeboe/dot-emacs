# ADR 0008: Agent context hygiene: one memory store, a handoff reset, opt-in servers

**Status:** Accepted (2026-10-27).

## Context

A Claude Code session here started with a large, partly contradictory
context. Two memory stores were live: Claude Code's auto memory
(`MEMORY.md`) and `bd remember`, which `bd prime` injects. The beads rules
reached the agent from the bd-managed block in `CLAUDE.md` and `AGENTS.md`,
from `bd prime`, and from the vendored beads skill. Every repository connected
the `mobile-mcp` and `chrome-devtools` servers, whose tool lists and
instruction blocks loaded whether or not the repository drives a phone or a
browser. Long sessions had no visible sign of their size and no cheap way to
start over without losing the thread. See `specs/007-context-hygiene/` and
its `research.md`.

## Decision

**`bd remember` is the single memory store.** `autoMemoryEnabled = false` in
`workstation/agents/default.nix`. Memories reach every session through
`bd prime`, which the beads plugin runs on SessionStart (including after
`/clear`) and on PreCompact. Auto memory's existing directories are left in
place; with the setting off they are not read.

**A reset is `/bead-handoff`, then `/clear`, then `bd prime`.** The
`bead-handoff` skill appends a dated note with `Tried:`, `Failed:` and
`Next:` lines to the in-progress bead with `bd note`, which appends, never
`bd update --notes`, which replaces. It leaves the bead `in_progress`, and it
never runs `/clear`: the user does. The SessionStart hook then runs
`bd prime`, which points the new session at its in-progress bead and so at
the note. The skill carries `disable-model-invocation: true` and is installed
for Claude Code only (`skills-claude-only/`), because opencode and
`~/.agents/skills` readers may not honour that key. The status line shows the
context size, yellow above 200K and bold red above 400K, and
`autoCompactWindow` summarizes at 400K as the backstop.

**Per-repository servers are default-off skills-dir plugins.**
`agents.mcp.optIn.servers` lists the servers that Claude Code loads only on
opt-in. Each becomes a plugin under `~/.claude/skills` (`hm-mobile`,
`hm-browser`) with `defaultEnabled: false` and one server in its `.mcp.json`.
The user setting writes `enabledPlugins."<plugin>@skills-dir" = false` so the
default is visible. A repository opts in with `true` in its
`.claude/settings.local.json`, which outranks user scope. No user-level
setting is scoped by path, so the switch has to live in the repository.
Opencode has no such switch and keeps both servers everywhere. Tool names
change: `mcp__plugin_hm_mobile-mcp__*` becomes
`mcp__plugin_hm-mobile_mobile-mcp__*`.

**The built-in task tools are denied.** `TodoWrite`, `TaskCreate`,
`TaskGet`, `TaskList` and `TaskUpdate` are in `permissions.deny`
(`workstation/agents/beads.nix`), so beads is the only task tracker.
`TaskStop`, `TaskOutput` and `SendMessage` stay allowed. On Opus 5.x the
harness does not offer the task tools unless opted in, so the rule mostly
covers older models and subagents. The `CLAUDE.md` and `AGENTS.md` beads
blocks are replaced by one line outside any markers, and `bd prime` becomes
the single source of the beads workflow rules.

**Some duplicates stay on purpose (FR-015).** Each repeats a rule that has
another source, and each is kept for the reason given:

- `bd prime` hard-codes a "Prohibited: TodoWrite/TaskCreate" line
  (`prime.go`). It now repeats the deny rule. It is upstream output that
  this config cannot edit, and it is harmless.
- The vendored beads skill (`beads:beads`) still has text that
  contradicts the ban. It loads only when the skill is invoked, and the deny
  rule wins if the agent follows it. Patching upstream prose would have to
  be redone on every bump.
- `bd prime` prints its agent-profile text on git (conservative by default,
  team-maintainer by opt-in). The global git policy in the user `CLAUDE.md`
  and the commit gate (ADR 0006) are stricter and win. The profile text is
  upstream output.

## Consequences

- Denying the task tools also turns off the agent teams' shared task list.
  Teammates coordinate through messages only. This is accepted: beads is
  the shared tracker, and teams are opt-in.
- `bd init` and `bd setup` regenerate the managed `BEGIN/END BEADS
  INTEGRATION` block in `CLAUDE.md` and `AGENTS.md`. Running either in this
  repository re-adds the block and its duplicate rules. Delete it again, or
  pass the option that skips the agent files if a future bd has one.
- `bd prime` grows with each `bd remember`. Above 10 000 characters the
  harness would truncate it to a preview. `prime.max-memory-chars` can cap
  it; this is tracked as a follow-up.
- A repository that needs a phone or browser server must edit its own
  `.claude/settings.local.json`. The sandbox write-denies that file, so the
  user makes the edit.
- A plugin with an unchanged version is not re-copied into Claude Code's
  cache, so the patched beads marketplace carries a `+hm1` version suffix.
  An upstream bump keeps the suffix.
- The single-store and handoff decisions rely on the beads plugin's
  SessionStart hook. If upstream drops it, a fresh session no longer sees
  memories or the handoff note until the agent runs `bd prime` itself.
