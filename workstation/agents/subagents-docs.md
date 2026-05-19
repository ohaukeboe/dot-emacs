## Subagents & Agent Teams

Claude Code can spawn lightweight workers (`Agent` tool) or full parallel
sessions (agent teams). Use them when delegation pays its coordination
overhead back in saved context or wall-clock time.

### Subagents (`Agent` / `Task` tool)

Spawn when:

- A side task would flood the main context with logs, search hits, or file
  contents not referenced again (research, broad codebase exploration, log
  triage).
- The work fits a specialized agent definition (`Explore`, `Plan`,
  `code-review-graph`, `cavecrew-*`).
- Multiple independent lookups can run in parallel — issue them in a single
  message with multiple `Agent` tool calls.

Do NOT spawn when:

- The target file or symbol is already known — use `Read` / `Grep` directly.
- The task is a single trivial edit where overhead exceeds benefit.

Write a self-contained prompt: the subagent has no view of the current
conversation. Cap response length when only a summary is needed.

### Agent teams (enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)

Propose a team when:

- Teammates must communicate with each other (adversarial debugging,
  cross-layer refactor, parallel review with shared findings).
- 3–5 independent workstreams each own a distinct file set.

Skip when: sequential dependencies dominate, same-file edits, or routine
single-track work. Token cost scales linearly per teammate.

Always confirm with the user before creating a team. Clean up via the lead
when done to avoid orphaned resources.

### Cavecrew shortcut

For caveman-compressed delegation (~60% smaller tool result, preserving main
context), prefer:

- `cavecrew-investigator` — locate code
- `cavecrew-builder` — 1–2 file edits
- `cavecrew-reviewer` — diff review

over vanilla `Explore` when context conservation matters mid-session.
