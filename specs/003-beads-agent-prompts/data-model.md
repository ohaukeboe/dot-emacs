# Data Model: Prompt the Coding Agent from a Beads Issue

No persistent state. The feature holds no data of its own between calls; every
value below is either configuration or computed per invocation.

## Issue reference

- **id**: string, `<prefix>-<suffix>` as `bd` issues it. Taken from the section
  value, the region's sections, or `beads--issue` in a show buffer.
- Validation: non-empty list for the quick prompt; exactly one for explore.

## Agent session (external, owned by claude-code-ide)

- Identified to beads only through the seam in
  [contracts/commands.md](./contracts/commands.md): existence (available
  function) and a buffer (returned by the send function).
- Cardinality per repository: 0, 1 or many. 0 ⇒ entries inapt, commands refuse.
  Many ⇒ the adapter's resolution chooses (research R2).

## Quick prompt

- **text**: `(format beads-agent-quick-prompt-format (string-join ids ", "))`.
- **submit**: always nil.
- Lifecycle: pasted → developer completes it in the agent's input → developer
  submits. Beads is not involved after the paste.

## Explore instruction

- **template**: `beads-agent-explore-prompt`, `%i` = id.
- **text**: `format-spec` expansion; prefixed with `"Beads issue <id>:\n\n"` when
  the expansion lacks the id.
- **submit**: always t.
- Lifecycle: sent → agent explores and replies with understanding + questions →
  stops. Beads is not involved after the send.
