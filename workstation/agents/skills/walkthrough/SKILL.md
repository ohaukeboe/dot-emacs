---
name: walkthrough
description: Produce a guided walkthrough of a branch's committed changes, with the built-in review's findings attached, and open it in the user's Emacs. Use when the user runs /walkthrough or asks to "walk me through the changes", "give me a walkthrough of this branch" or "tour this PR".
disable-model-invocation: true
---

# Walkthrough

Turn the committed changes of the current branch into a **walkthrough**: steps
in reading order, each with an explanation and the diffs it owns, plus the
built-in review's **findings**. The user reads it in Emacs, where Magit shows
each step's diffs, and marks the findings to hand back to you.

This skill is read-only. Never edit code, stage, commit, push or post anything.
Don't run the project's tests or install dependencies.

## Arguments

`/walkthrough [BASE]`. `BASE` is an optional ref to compare against.

## 1. Pin the range

1. `HEAD` is the head. Resolve it: `git rev-parse HEAD`.
2. The base is `BASE` if given. Otherwise it is the merge-base with the
   remote's default branch:
   - `git symbolic-ref --quiet refs/remotes/origin/HEAD` names the default
     branch (`refs/remotes/origin/main`, for example).
   - The base is `git merge-base <that> HEAD`.
   - If there is no `origin/HEAD`, or several remotes and no clear answer, ask
     the user for the base. Don't assume `main`.
3. The branch is `git branch --show-current`. If `HEAD` is detached, ask the
   user what to call the walkthrough.
4. Check that `git diff --quiet <base> <head>` exits non-zero, i.e. there is
   something to review. If it exits 0, stop and say so.
5. If `git status --porcelain` shows uncommitted changes, tell the user they
   are left out. Only committed work is reviewed.

## 2. Run the built-in review

Run the built-in review through the Skill tool, with skill `code-review` and
args `<base>...<head>` (three dots). That name is the built-in review; the
two-axis review (Standards + Spec) is installed as `code-review-axes` so it
does not shadow it. Don't use `review`: the Skill tool doesn't know that name.

The review reports its findings through `ReportFindings`. Nothing comes back
as data, but you wrote that call's arguments, so keep them. If the Skill tool
cannot invoke `code-review`, **stop**. Tell the user the built-in review was not
reachable. Don't invent findings and don't review the code yourself instead.

## 3. Shape the steps

Read the changed files and the code around them, then group the changes into
steps. Each step is **one concept**. Order the steps for understanding, not by
commit order:

- definitions before the code that uses them;
- wiring after the parts it connects;
- tests beside or after their subjects.

Each changed file belongs to steps like this:

- Normally a step owns a **whole file**: list its path.
- When one file holds unrelated changes, split it. Each step lists
  `{"file": "<path>", "ranges": [[start, end], ...]}`, with line numbers on the
  **new** side. A step then shows only the hunks that overlap its ranges.
  Changes within about 6 lines of each other form one hunk and cannot be split.

Every hunk of `git diff -U3 <base> <head>` must belong to exactly one step. A
file without hunks (a binary file, a pure rename or a mode change) must be
owned whole by exactly one step. A deleted file is named by its old path.

Write each explanation in Markdown, usually 50–150 words. Cover what the step
does and why, the design choices and trade-offs, and how it connects to other
steps ("step 3 calls this").

## 4. Attach the findings

For each finding the review reported:

| Review field | Walkthrough field |
|---|---|
| short summary | `title` |
| summary | `body` (Markdown) |
| failure scenario | `failure_scenario` |
| verdict (CONFIRMED / PLAUSIBLE) | `verdict` |
| category slug | `category` |
| file, line | `anchor.file`, `anchor.line` |

The review has no severity. Set `severity` to `high`, `medium` or `low` from
the finding's rank and verdict: a confirmed correctness finding near the top of
the list is `high`. Map fields by meaning, not by exact name. If the review
reports a field this table doesn't name, keep it under its own key; it is shown
as text.

Put each finding in the step that owns its file. If you split that file, use
the step whose ranges cover the line. `anchor.line` is on the new side; add
`"side": "old"` only for a line that exists only in the base. A finding with no
file goes, unanchored, in the step it concerns most.

## 5. Write the draft and open it

Write the draft to `$TMPDIR/walkthrough-<branch with / replaced by ->.json`:

```json
{
  "version": 1,
  "title": "One line saying what the branch does",
  "branch": "<branch>",
  "base": "<base sha>",
  "head": "<head sha>",
  "steps": [
    {
      "title": "The concept",
      "explanation": "Markdown.",
      "files": ["path/whole.el", {"file": "path/split.el", "ranges": [[10, 40]]}],
      "findings": [
        {
          "severity": "high",
          "title": "One line",
          "body": "Markdown.",
          "failure_scenario": "Inputs or state, then the wrong result.",
          "verdict": "CONFIRMED",
          "category": "correctness",
          "anchor": {"file": "path/whole.el", "line": 120, "end_line": 124}
        }
      ]
    }
  ]
}
```

`findings` may be `[]`. `end_line` and `side` are optional. Don't add `id`,
`state` or `repo`; Emacs sets them.

Then call the `open_walkthrough` MCP tool with `path` set to the draft's
absolute path.

- `Opened <file>` means it is installed and on screen.
- Otherwise the result is one error per line, such as
  `hunk a.el @@ -7,7 +7,7 @@: owned by no step`. Fix the draft and call the
  tool again. Nothing was installed, and the previous walkthrough is untouched.

If the tool doesn't exist, Emacs is not connected. Say so and give the draft's
path.

## 6. Report

Report in a few lines:

- the range;
- how many steps and findings, with the count of high-severity findings;
- that the walkthrough is open in Emacs;
- any uncommitted changes you left out.

Mention that in the buffer `a`/`x`/`u` accept, dismiss or unmark a finding,
and that `@ s` sends the accepted ones back to you. Don't fix anything until
the user hands findings back.
