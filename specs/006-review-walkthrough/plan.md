# Implementation Plan: Review Walkthroughs

**Branch**: `main` | **Date**: 2026-10-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/006-review-walkthrough/spec.md`;
bead `dot-emacs-6ni` and its children.

## Summary

An agent skill, `walkthrough`, runs the built-in review on `<base>...<head>`,
groups the changed files into steps in reading order, and writes a draft. Emacs
validates the draft (every hunk owned exactly once), installs it under the
repository's git directory, and opens it in `walkthrough-mode`, a mode derived
from `magit-diff-mode`. Each step shows its explanation, its findings and its
diffs, rebuilt live from the two commits (ADR 0007). Since the diffs are Magit's
own sections, review comments, RET and folding work unchanged. The user marks
findings with `a`/`x`/`u`, and `@ s` hands the accepted ones off together with
pending review comments.

Technical approach: a new package `walkthrough.el` with its own ERT suite, the
same seam as `beads.el`. `config.org` holds the adapters: the MCP tool
`open_walkthrough`, the extended hand-off and `magit_review_comments`, two `@`
keys. It also fixes the `magit-buffer-range` rename that currently mislabels
every range-diff review comment (research R6).

## Technical Context

**Language/Version**: Emacs Lisp, `lexical-binding: t`, `emacs-unstable-pgtk`
from emacs-overlay (`home.nix`). Markdown for the skill.

**Primary Dependencies**: `magit` 20261005 / `magit-section` 20260926 (via the
derived mode, `magit-setup-buffer`, `magit-diff-wash-diffs`, `magit-git-insert`),
`markdown-mode` (optional, for rendering), built-in `json`. In `config.org`
only: `claude-code-ide` (`claude-code-ide-make-tool`,
`claude-code-ide-mcp-server-get-session-context`, `my/claude-code-ide-paste`).

**Storage**: JSON files at `<git-common-dir>/walkthroughs/<branch>.json`, written
only by Emacs, atomically (research R4).

**Testing**: ERT in `workstation/emacs/packages/walkthrough-test.el`, run by
`nix build .#test-walkthrough -L` (`tests/walkthrough.nix`, an Emacs with magit
and markdown-mode, plus git). Manual steps in [quickstart.md](./quickstart.md)
for the skill, the MCP tool and the hand-off.

**Target Platform**: NixOS + Home Manager, three machines.

**Project Type**: an Emacs Lisp package and an agent skill inside a Nix
configuration repository.

**Performance Goals**: the buffer appears within 5 s of the tool call for about
30 files (SC-001). Cost: one `git diff` for validation plus one per step.

**Constraints**:
- Agents write only to `$TMPDIR`; `git-common-dir` may lie outside the sandbox.
- An invalid draft never replaces an installed walkthrough.
- `ReportFindings` field names are undocumented (research R5).

**Scale/Scope**: about 550 lines in `walkthrough.el`, 450 in the tests, 80
changed or added in `config.org`, a 120-line skill.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1.*

### I. Evaluation-Time Verification

No Nix option is added. The skill is a Markdown file picked up by the existing
`./skills` path. The behaviour evaluation cannot see is covered by a new
`packages.test-walkthrough`. Its `defcustom` carries the narrowest type,
`(choice (const nil) function)`. **Pass.**

### II. Determinism and Reproducibility

No new source or pin: `markdown-mode` comes from the pinned nixpkgs
`emacsPackages`. The walkthrough files live in `.git`, outside the flake source.
New files (`walkthrough.el`, `walkthrough-test.el`, `tests/walkthrough.nix`, the
skill) must be `git add`ed before building. **Pass.**

### III. Fast Default Gate, Heavy Tests Opt-In

The ERT suite is a `packages.*` attribute with the run command in a comment,
like `test-beads`; `checks.*` stays untouched. The `magit-buffer-range` bug
(R6) is one evaluation cannot catch. The fix gets a regression case in the new
suite, which asserts the label `walkthrough-mode` produces for `:where`
through the same helper. **Pass.**

### IV. Single Source of Truth

- `config.org` is edited; no generated `.el` is touched.
- One validator, in Emacs (R4). One hand-off and one formatter for comments and
  findings (R9).
- Terms are already in `GLOSSARY.md` (Walkthrough, Step, Finding, Review
  hand-off). The decision is ADR 0007. `AGENTS.md` and `CLAUDE.md` are
  unchanged.

**Pass.**

### V. Toggleable Modules, Declarative Machines

Not a NixOS module. The package is inert until a walkthrough exists. With
`walkthrough-request-function` nil, `W` says no agent is configured. **Pass.**

### Post-design re-check

Phase 1 added one package with one `defcustom`, one MCP tool, one skill and one
test package. No module, no flake input. **All five principles pass; nothing in
Complexity Tracking.**

## Project Structure

### Documentation (this feature)

```text
specs/006-review-walkthrough/
├── plan.md              # This file
├── spec.md
├── research.md          # R1..R10
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── walkthrough-file.md  # JSON format and validation messages
│   └── interfaces.md        # Package API, config adapters, skill steps
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks — not created here
```

### Source Code (repository root)

```text
workstation/
├── emacs/
│   ├── packages/
│   │   ├── walkthrough.el       # New: file format, validator, mode, marks, hand-off items
│   │   └── walkthrough-test.el  # New: ERT suite against a throwaway repo
│   └── config.org               # Magit review: :where fix, hand-off + MCP tool include
│                                # findings, @ column; Claude Code: open_walkthrough tool;
│                                # use-package walkthrough
└── agents/skills/walkthrough/
    └── SKILL.md                 # New: the /walkthrough skill
tests/walkthrough.nix            # New: runs the ERT suite
flake.nix                        # packages.test-walkthrough
```

**Structure Decision**: one new package beside `beads.el`, deployed by the
existing `./emacs/packages` copy in `home.nix` and loaded through the existing
`load-path` entry. Everything that names `claude-code-ide` or `my/magit-review-*`
stays in `config.org`. The skill goes in the existing local skills directory,
which `skills.nix` already merges.

## Mapping to beads

| Bead | Plan part |
|---|---|
| `dot-emacs-6ni.1` schema + validator | `walkthrough-file.md`, R3, R4 |
| `dot-emacs-6ni.3` buffer | R2, R3, R7 |
| `dot-emacs-6ni.4` marks | data-model states, R8 |
| `dot-emacs-6ni.5` hand-off | R6, R9 |
| `dot-emacs-6ni.6` MCP tool + `@` keys | R4, R10 |
| `dot-emacs-6ni.2` skill | R5, `interfaces.md` |

The R6 fix (`magit-buffer-range` rename) belongs with `.5`, but it is a live
bug today, so it may land first on its own.

## Complexity Tracking

> No violation of the constitution or the spec.
