---
name: project-audit
description: Audit a whole project, or one area of it, for bugs and code smells, and open the findings in the user's Emacs, where they are marked and handed back. Use when the user runs /project-audit or asks to "audit this project", "find bugs in this codebase" or "look for code smells across the repo".
disable-model-invocation: true
---

# Project audit

Review the project as it stands at one commit, not a diff, for **defects**
and **code smells**. Deliver them as **findings**, grouped into steps by area.
The user reads the audit in Emacs, where each finding shows the code it is
about, and marks findings to hand back to you.

This skill is read-only. Never edit code, stage, commit, push or post anything.
Don't run the project's tests or install dependencies.

## Arguments

`/project-audit [AREA]`. `AREA` is an optional directory, relative to the
repository's toplevel. Without it, audit the whole project. With it, report
only findings inside it.

## What to look for

- A **defect** is code that behaves wrongly in some reachable situation:
  wrong results, crashes, lost or exposed data, races, resource leaks, broken
  error paths, wrong boundary conditions.
- A **smell** is code that works but costs too much to keep: duplication,
  dead code, needless complexity, missing error handling at a trust boundary,
  risky code with no tests, names that mislead, one function doing three jobs.

Security defects you happen to meet are defects. A dedicated security scan
is out of scope; don't hunt for one.

## 1. Pin the commit

1. The commit is `git rev-parse HEAD`.
2. If `git status --porcelain` shows uncommitted changes, tell the user they
   are left out. Only committed code is audited.

## 2. Split into areas

1. List the files: `git ls-files` (under `AREA`).
2. Drop generated, vendored and lock files (`_sources/`, `vendor/`,
   `node_modules/`, `*.lock`, `package-lock.json`, `flake.lock`, minified
   files). Record them in `skipped`.
3. Group the rest into **at most 6 areas**, by directory and purpose. Each
   area becomes one step.

## 3. Review each area

Launch one `general-purpose` subagent per area, **all in one message**. Give
each:

- the commit sha and that it reviews code at that commit, read-only;
- its list of files;
- the definitions of defect and smell above;
- this output contract: reply with only a JSON array of findings, each
  `{"severity", "type", "title", "body", "failure_scenario", "anchor"}`.
  `type` is `defect` or `smell`. `failure_scenario` (defects only) is the
  inputs or state, then the wrong result. `anchor` is `{"file", "line",
  "end_line"}` at the commit, or left out for a finding about no single place.
  At most 12 findings, most severe first. No findings is a valid answer.

## 4. Verify and merge

In this session, before you write anything:

1. For **every defect**, read the anchored code yourself
   (`git show <commit>:<file>`) and follow the path its failure scenario
   needs. Set `verdict` to `CONFIRMED` if you traced it, `PLAUSIBLE` if it
   depends on something you could not check. Drop it if it is wrong.
2. Check each anchor's line numbers against the file at the commit.
3. A smell found in several places becomes **one** finding: its body lists
   every place (`path:line`), and its anchor is the first.
4. Severity: a confirmed defect reachable in normal use is `high`; a defect
   behind unusual input, or a smell that has already caused bugs, is
   `medium`; everything else is `low`.
5. `category` is a short slug such as `correctness`, `error-handling`,
   `duplication`, `dead-code`, `complexity`, `test-coverage`.

## 5. Shape the steps

One step per area. The step's explanation (Markdown, 60 to 150 words) says
what the area does and how it fits into the project, so its findings can be
judged without reading other steps. A step may list extra excerpts in
`files` (`{"file", "ranges"}`) when context helps. Each anchored finding shows
its own lines anyway. An area with no findings is still a step: it says what
was checked.

`skipped` names everything not read, and why. A clean audit must be
distinguishable from a shallow one.

## 6. Write the draft and open it

Write the draft to `$TMPDIR/audit.json`, or `$TMPDIR/audit-<area with /
replaced by ->.json` for an area:

```json
{
  "version": 1,
  "kind": "audit",
  "title": "Audit of <project or area>",
  "commit": "<full sha>",
  "area": "<AREA, or leave this key out>",
  "skipped": ["package-lock.json: lock file"],
  "steps": [
    {
      "title": "Sandbox policy",
      "explanation": "What the area does, enough to judge its findings.",
      "findings": [
        {
          "severity": "high",
          "type": "defect",
          "title": "One line",
          "body": "Markdown.",
          "failure_scenario": "Inputs or state, then the wrong result.",
          "verdict": "CONFIRMED",
          "category": "correctness",
          "anchor": {"file": "path/x.nix", "line": 40, "end_line": 44}
        },
        {
          "severity": "low",
          "type": "smell",
          "title": "One line",
          "body": "Also at `a.nix:12`, `b.nix:30`.",
          "category": "duplication",
          "anchor": {"file": "path/x.nix", "line": 80}
        }
      ]
    }
  ]
}
```

A defect needs `failure_scenario` and `verdict`. Don't use `side` in an
anchor. Don't add `repo`, `base`, `head`, `id` or `state`; Emacs sets them.

Then call the `open_walkthrough` MCP tool with `path` set to the draft's
absolute path.

- `Opened <file>` means it is installed and on screen.
- Otherwise the result is one error per line, such as
  `steps[0].findings[1].verdict: a defect needs CONFIRMED or PLAUSIBLE`. Fix
  the draft and call the tool again. Nothing was installed.

If the tool doesn't exist, Emacs is not connected. Say so and give the draft's
path.

## 7. Report

Report in a few lines:

- the commit and the area;
- findings by severity and type (e.g. "2 high defects, 1 medium, 5 smells");
- what was skipped;
- that the audit is open in Emacs;
- any uncommitted changes you left out.

Mention that in the buffer `a`/`x`/`u` accept, dismiss or unmark a finding,
`@ c` on a finding replies to it, and `@ s` sends the accepted ones back to
you. Don't fix anything until the user hands findings back.
