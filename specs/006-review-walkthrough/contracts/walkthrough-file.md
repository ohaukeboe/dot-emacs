# Contract: Walkthrough File

The draft the agent writes and the installed file Emacs keeps share one JSON
format. The draft lacks `repo`, finding `id` and `state`; Emacs adds them at
install. Entities and rules: [data-model.md](../data-model.md).

```json
{
  "version": 1,
  "title": "Add walkthrough buffer for agent reviews",
  "branch": "feat/walkthrough",
  "base": "3f2c…40 hex…",
  "head": "9ab1…40 hex…",
  "steps": [
    {
      "title": "The file format and its validator",
      "explanation": "Markdown. Why this step exists, what to look at, links to other steps.",
      "files": [
        "workstation/emacs/packages/walkthrough.el",
        { "file": "workstation/emacs/config.org", "ranges": [[995, 1040]] }
      ],
      "findings": [
        {
          "severity": "high",
          "title": "Range overlap off by one for pure deletions",
          "body": "Markdown.",
          "failure_scenario": "A hunk `+12,0` next to a range `[12, 20]` …",
          "verdict": "CONFIRMED",
          "category": "correctness",
          "anchor": { "file": "workstation/emacs/packages/walkthrough.el", "line": 120, "end_line": 124, "side": "new" }
        }
      ]
    }
  ]
}
```

Installed at `$(git rev-parse --git-common-dir)/walkthroughs/<branch>.json`. A
`/` in the branch name is replaced with `%2F`.

## Validation (research R4)

All errors are collected and returned together, one per line, as
`<where>: <problem>`. For example:

```text
steps[2].files[0]: config.org is owned by steps[0] as a whole file
hunk config.org @@ -1088,6 +1090,9 @@: owned by no step
hunk walkthrough.el @@ -0,0 +1,412 @@: owned by steps[0] and steps[3]
steps[1].findings[0].anchor.file: lib/x.el is not owned by this step
head: 9ab1… is not a commit
```

A draft with any error is not installed, and the existing file is untouched.
