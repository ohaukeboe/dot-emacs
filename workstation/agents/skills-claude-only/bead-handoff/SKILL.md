---
name: bead-handoff
description: Write a tried/failed/next handoff note to the in-progress bead, then tell the user to /clear.
argument-hint: "[issue-id]"
disable-model-invocation: true
---

# Bead handoff

Save what this session learned to the in-progress beads issue, so the user
can `/clear` and a fresh session picks the work up from the note.

| Call                 | Target issue                             |
|----------------------|------------------------------------------|
| `/bead-handoff`      | the single `in_progress` issue, else ask |
| `/bead-handoff <id>` | `<id>`                                   |

Arguments: `$ARGUMENTS`

## Never

- Never run `bd update --notes`: it replaces every earlier note.
- Never run `bd close` or `bd update --status`. The issue stays
  `in_progress`.
- Never run `/clear` yourself. The user does that.

## Steps

1. **Check for a tracker.** Run `bd where`. If it exits non-zero, print the
   note (the shape in step 3) in the conversation, say it cannot be stored
   because there is no beads database here, and stop. Write nothing.

2. **Find the issue.**
   - If `$ARGUMENTS` names an issue id, use it.
   - Otherwise run `bd list --status in_progress --json --brief`.
     - **Exactly 1 issue:** use it.
     - **0 issues:** ask which issue to use, or offer to `bd create` one.
     - **More than 1 issue:** list each id and title and ask which one.
   - Write nothing until the user has answered.

3. **Append the note.** Write it from what this session actually did, at
   most 20 lines in total, in this shape (use today's date):

   ```text
   Handoff YYYY-MM-DD
   Tried: <approaches attempted>
   Failed: <what failed and why>
   Next: <the next thing to try>
   ```

   Append it with `bd note`, which keeps every earlier note:

   ```bash
   bd note <id> --stdin <<'EOF'
   Handoff YYYY-MM-DD
   Tried: ...
   Failed: ...
   Next: ...
   EOF
   ```

4. **Report.** Print exactly:

   `Note saved to <id>. You can now run /clear.`

   After `/clear`, the beads SessionStart hook runs `bd prime`, and the new
   session finds the note with `bd show <id>`.
