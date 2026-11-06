---
name: project-tour
description: Produce a guided tour of a project's structure and of how its parts work together, with diagrams and code excerpts, and open it in the user's Emacs. Use when the user runs /project-tour or asks for "a tour of this project", "help me get to know this codebase" or "how does this project fit together".
disable-model-invocation: true
---

# Project tour

Turn the project as it stands at one commit into a **tour**: steps in reading
order that explain what the project is for, how it is structured and how its
parts work together, with diagrams and short code excerpts where they help.
The user reads it in Emacs, where each excerpt is a Magit hunk (`RET` visits
the line, `@ c` asks about it) and each diagram can be commented on.

This skill is read-only. Never edit code, stage, commit, push or post anything.
Don't run the project's tests or install dependencies.

## Arguments

`/project-tour [AREA]`. `AREA` is an optional directory, relative to the
repository's toplevel. Without it, tour the whole project.

## 1. Pin the commit

1. The commit is `git rev-parse HEAD`.
2. If `git status --porcelain` shows uncommitted changes, tell the user they
   are left out. Only committed code is toured: excerpts are read from the
   commit, not the work tree.

## 2. Explore

Read before you write. In order of value:

- the docs: `README*`, `AGENTS.md`/`CLAUDE.md`, `docs/` (ADRs explain why),
  a glossary if there is one;
- the build and entry points: `flake.nix`, `package.json`, `Cargo.toml`,
  `main` functions, CLI definitions, service definitions;
- the module layout: `git ls-tree -r --name-only HEAD` (under `AREA`), and the
  code that wires parts together.

If the `codebase-memory` MCP tools exist, `get_architecture` gives the overview
and `trace_path` follows a flow across files. For a large tree, delegate: one
`Explore` subagent per top-level area, all in one message, each asked for the
area's purpose, its main files, what it uses and what uses it, in under 300
words.

Skip generated, vendored and lock files. You may name what they are for, but
don't excerpt them. List what you did not cover in `skipped`.

With `AREA`, tour that area, and say in the overview how it connects to the
rest of the project.

## 3. Shape the steps

Write **6 to 15 steps**, in this order:

1. **Overview**: what the project is for, its main parts and how they relate.
   It must have a diagram of those parts.
2. **Foundations**: shared types, configuration, the core abstractions, before
   the parts that build on them.
3. **Parts**: one step per main part.
4. **Flows**: paths that cross several parts, such as a request, a build or a
   command from input to effect.

Each step explains how its part connects to the others: what it uses and what
uses it. Don't just list what it contains. Write the explanation in Markdown,
usually 80 to 200 words.

**Diagrams**: draw one wherever a step explains structure or interaction
between three or more parts. A diagram is a fenced block inside the
explanation:

````markdown
```text
flake.nix ──▶ lib/mkNixosConfiguration.nix ──▶ machines/<host>/
    │
    └──────▶ workstation/ (home-manager)
```
````

Lines inside a fenced block may be **at most 90 columns** wide: the view wraps
long lines and a wider diagram is rejected. Arrows show the direction of use
or data flow. Label boxes with real paths or names from the code.

**Code excerpts**: add one where a step's point depends on specific code. An
excerpt is `{"file": "<path>", "ranges": [[start, end]]}` in the step's
`files`, with line numbers at the commit. Aim for at most 40 lines; a range
over 80 lines is rejected. Several short ranges beat one long one. Don't add
excerpts that say nothing the explanation doesn't. Check line numbers with
`git show HEAD:<path> | sed -n '<start>,<end>p'` before you use them.

A tour carries **no findings**. If you notice a bug, mention it in your final
report, not in the tour.

## 4. Write the draft and open it

Write the draft to `$TMPDIR/tour.json`, or `$TMPDIR/tour-<area with / replaced
by ->.json` for an area:

```json
{
  "version": 1,
  "kind": "tour",
  "title": "One line naming what the project is",
  "commit": "<full sha>",
  "area": "<AREA, or leave this key out>",
  "skipped": ["_sources/: nvfetcher output"],
  "steps": [
    {
      "title": "Overview",
      "explanation": "Markdown, with a ```text diagram block.",
      "files": [{"file": "flake.nix", "ranges": [[1, 30]]}]
    },
    {
      "title": "How a machine is composed",
      "explanation": "Markdown.",
      "files": [{"file": "lib/mkNixosConfiguration.nix", "ranges": [[10, 45]]}]
    }
  ]
}
```

`files` may be left out of a step. Don't add `repo`, `base`, `head`, `id` or
`state`; Emacs sets them.

Then call the `open_walkthrough` MCP tool with `path` set to the draft's
absolute path.

- `Opened <file>` means it is installed and on screen.
- Otherwise the result is one error per line, such as
  `steps[1].files[0].ranges[0]: [200, 260] ends after line 180 of lib/x.nix`.
  Fix the draft and call the tool again. Nothing was installed.

If the tool doesn't exist, Emacs is not connected. Say so and give the draft's
path.

## 5. Report

Report in a few lines:

- the commit and the area;
- how many steps, and what you skipped;
- that the tour is open in Emacs;
- any uncommitted changes you left out.

Mention that `N`/`P` move between steps, `RET` on an excerpt opens the file,
and `@ c` or `@ d` on an excerpt, a passage or a diagram asks a question that
reaches you with its file, lines or step.
