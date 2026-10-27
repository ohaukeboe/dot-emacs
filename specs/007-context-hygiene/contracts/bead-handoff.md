# Contract: `/bead-handoff` skill

Location: `workstation/agents/skills-claude-only/bead-handoff/SKILL.md`. It
is installed into `~/.claude/skills` only, through `skillsWithPlugin`. It is
not installed for opencode or into `~/.agents/skills`.

## Frontmatter

```yaml
name: bead-handoff
description: Write a tried/failed/next handoff note to the in-progress bead, then tell the user to /clear.
argument-hint: "[issue-id]"
disable-model-invocation: true
```

## Invocation

| Call                 | Target issue                             |
|----------------------|------------------------------------------|
| `/bead-handoff`      | the single `in_progress` issue, else ask |
| `/bead-handoff <id>` | `<id>`                                   |

## Steps and observable effects

1. **Check for a tracker.** If `bd where` exits non-zero, the skill prints
   the three-part note in the conversation and says it cannot be stored. It
   writes nothing.
2. **Find the issue.** It runs `bd list --status in_progress --json --brief`.
   - **0 issues:** it asks which issue to use, or offers `bd create`.
   - **More than 1 issue:** it lists each id and title and asks.
   - It writes nothing until the user answers.
3. **Append the note.** It runs `bd note <id> --stdin` with the body defined
   in `data-model.md` ("Handoff note"), at most 20 lines. It never runs
   `bd update --notes`, `bd close` or `bd update --status`.
4. **Report.** It prints `Note saved to <id>. You can now run /clear.` It
   never runs `/clear` itself.

## Postconditions

- `bd show <id>` shows the new note after all earlier notes.
- The issue's status is unchanged.
- After `/clear`, the beads SessionStart hook runs `bd prime`, and the new
  session can find the note through the in-progress list.
