# Contract: Tour and Audit Files

Same file format as
[006's walkthrough file](../../006-review-walkthrough/contracts/walkthrough-file.md),
version 1, with a `kind`. Entities and rules: [data-model.md](../data-model.md).

## Tour draft

````json
{
  "version": 1,
  "kind": "tour",
  "title": "How this NixOS + Home Manager flake fits together",
  "commit": "9885e73…40 hex…",
  "area": "workstation/agents",
  "skipped": ["_sources/: nvfetcher output"],
  "steps": [
    {
      "title": "Overview",
      "explanation": "Three layers …\n\n```text\nflake.nix ──▶ lib/mkNixosConfiguration.nix ──▶ machines/<host>\n    │\n    └────▶ workstation/ (home-manager)\n```\n",
      "files": [{"file": "flake.nix", "ranges": [[1, 30]]}]
    },
    {
      "title": "How a machine is composed",
      "explanation": "Markdown.",
      "files": [{"file": "lib/mkNixosConfiguration.nix", "ranges": [[10, 45]]}]
    }
  ]
}
````

## Audit draft

```json
{
  "version": 1,
  "kind": "audit",
  "title": "Audit of workstation/agents",
  "commit": "9885e73…",
  "area": "workstation/agents",
  "skipped": ["packages/*/package-lock.json"],
  "steps": [
    {
      "title": "Sandbox policy",
      "explanation": "What the area does, enough to judge its findings.",
      "files": [],
      "findings": [
        {
          "severity": "high",
          "type": "defect",
          "title": "Glob lets a sibling directory through",
          "body": "Markdown.",
          "failure_scenario": "Path `/home/x-evil` matches `/home/x*` …",
          "verdict": "CONFIRMED",
          "category": "correctness",
          "anchor": {"file": "workstation/agents/sandbox.nix", "line": 40, "end_line": 44}
        },
        {
          "severity": "low",
          "type": "smell",
          "title": "Same allowlist written in three places",
          "body": "Also at `a.nix:12`, `b.nix:30`.",
          "anchor": {"file": "workstation/agents/sandbox.nix", "line": 80}
        }
      ]
    }
  ]
}
```

Emacs adds `repo`, `base` = `head` = full `commit`, finding `id` and `state`
at install. The agent must not write them.

Installed at `$(git rev-parse --git-common-dir)/walkthroughs/:<kind>.json`, or
`:<kind>:<area>.json` with `/` in the area written `%2F`.

## Validation messages

Same shape as 006, all at once, nothing installed on any error:

```text
commit: 9885e73 is not a commit
steps[0].explanation: a tour's first step needs a diagram (a fenced block)
steps[1].explanation line 7: diagram is 104 columns wide, at most 90
steps[1].files[0]: lib/x.nix does not exist at 9885e73
steps[1].files[0].ranges[0]: [200, 260] ends after line 180 of lib/x.nix
steps[1].files[0].ranges[1]: [1, 120] spans 120 lines, at most 80
steps[2].findings: a tour has no findings
steps[0].findings[1].type: must be defect or smell
steps[0].findings[0].verdict: a defect needs CONFIRMED or PLAUSIBLE
steps[0].findings[0].failure_scenario: a defect needs one
steps[0].findings[2].anchor.side: not allowed in an audit
```
