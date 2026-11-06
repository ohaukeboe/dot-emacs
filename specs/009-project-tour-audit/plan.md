# Implementation Plan: Project Tours and Project Audits

**Branch**: `main` | **Date**: 2026-11-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/009-project-tour-audit/spec.md`.

## Summary

Two agent skills, `project-tour` and `project-audit`, write a draft walkthrough
of a new `kind` (`tour` or `audit`) about one commit instead of a diff, and
hand it to the existing `open_walkthrough` MCP tool. `walkthrough.el` learns
the two kinds: it validates them against the commit (lines exist, excerpts
short, diagrams at most 90 columns, audit defects verified), installs them
beside branch walkthroughs, and renders each step's code excerpts as
synthetic context-only diffs washed by Magit. Because those are real Magit
hunks with the file's line numbers, `RET`, folding, syntax highlighting, `@`
comments and finding placement all work unchanged, and audit findings join
the existing marks, replies and hand-off (research R1, R2).

## Technical Context

**Language/Version**: Emacs Lisp, `lexical-binding: t`, `emacs-unstable-pgtk`;
Markdown for the skills.

**Primary Dependencies**: `magit` ≥ 4.6 (`magit-diff-wash-diffs`,
`magit-diff-fontify-hunk`), `markdown-mode` (optional), built-in `json`.
`config.org` only: `claude-code-ide`. Skills: `git`, optionally the
`codebase-memory` MCP and `Explore` subagents.

**Storage**: JSON in `<git-common-dir>/walkthroughs/`, `:tour[:<area>].json`
and `:audit[:<area>].json`, written only by Emacs, atomically (R6).

**Testing**: ERT, extending `workstation/emacs/packages/walkthrough-test.el`,
run by `nix build .#test-walkthrough -L`. Manual steps in
[quickstart.md](./quickstart.md) for the skills and hand-off.

**Target Platform**: NixOS + Home Manager, three machines.

**Project Type**: Emacs Lisp package extension and two agent skills inside a
Nix configuration repository.

**Performance Goals**: buffer within 5 s of the tool call for a 200-file
project (SC-002). Cost: one `git show <commit>:<file>` per excerpted file per
refresh; validation reads each referenced file once.

**Constraints**:
- Agents write only to `$TMPDIR`; Emacs is the only writer of installed files.
- An invalid draft never replaces an installed file.
- Existing `changes` walkthroughs and their files keep working unmodified
  (absent `kind`).
- `visual-line-mode` wraps; diagrams are bounded to 90 columns (R3).

**Scale/Scope**: about 250 lines added to `walkthrough.el`, 250 to its tests,
30 changed in `config.org`, two skills of about 120 lines, one ADR, three
glossary entries.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1.*

### I. Evaluation-Time Verification

No Nix option is added. Skills are Markdown under the existing `./skills`
path. Behaviour evaluation cannot see is covered by extending
`packages.test-walkthrough`. **Pass.**

### II. Determinism and Reproducibility

No new source or pin. Installed files live in `.git`, outside the flake
source. The two new `SKILL.md` files must be `git add`ed before building.
**Pass.**

### III. Fast Default Gate, Heavy Tests Opt-In

The ERT suite stays a `packages.*` attribute; `checks.*` unchanged. **Pass.**

### IV. Single Source of Truth

- `config.org` is edited; no generated `.el` is touched.
- One validator, one renderer, one hand-off: tours and audits are kinds of
  walkthrough, not copies (R1). One helper builds the synthetic hunk for both
  the buffer and the hand-off (R8).
- New terms **Project tour**, **Project audit** and **Code excerpt** go into
  `GLOSSARY.md`; **Walkthrough** and **Finding** are widened there.
- The decision to show code as synthetic diffs from the commit extends ADR
  0007 and is recorded as **ADR 0011** in the same change.
- `AGENTS.md`/`CLAUDE.md` unchanged.

**Pass.**

### V. Toggleable Modules, Declarative Machines

Not a NixOS module; the package is inert until a file exists. **Pass.**

### Post-design re-check

Phase 1 added two kinds to one file format, two skills, four commands and one
ADR. No module, no input, no new test package. **All five principles pass;
nothing in Complexity Tracking.**

## Project Structure

### Documentation (this feature)

```text
specs/009-project-tour-audit/
├── plan.md              # This file
├── spec.md
├── research.md          # R1..R11
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── walkthrough-file.md  # tour and audit drafts, validation messages
│   └── interfaces.md        # commands, config adapters, skill steps
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks — not created here
```

### Source Code (repository root)

```text
workstation/
├── emacs/
│   ├── packages/
│   │   ├── walkthrough.el       # kind dispatch: validate, install, render
│   │   │                        # excerpts, label, file names, open/request
│   │   └── walkthrough-test.el  # tour/audit cases
│   └── config.org               # @ "Project" column, hand-off wording,
│                                # :type in findings, MCP tool description
└── agents/skills/
    ├── project-tour/SKILL.md    # New
    └── project-audit/SKILL.md   # New
docs/adr/0011-tours-show-code-as-context-diffs.md  # New
GLOSSARY.md                                         # New and widened terms
```

**Structure Decision**: everything extends what 006 built. The two skills go
into the local skills directory that `skills.nix` already merges, so no Nix
change is needed.

## Implementation order

1. Spike R2's risk: a synthetic hunk in a `C..C` buffer; confirm `RET`,
   `magit-diff-fontify-hunk` and `my/magit-review--range` on it. Adjust R2's
   fallback if needed.
2. `walkthrough.el`: kind-aware validation and install, file names; tests.
3. Rendering excerpts and audit anchors; label; moved notice; tests.
4. Hand-off item for audit findings; `config.org` wording and `:type`; tests.
5. Open/request commands and the `@` column.
6. Skills, then quickstart manual run; ADR 0011 and glossary.

US1 (tour) is shippable after steps 1–3, 5 and its skill; US2/US3 (audit)
after step 4 and its skill.

## Complexity Tracking

> No violation of the constitution or the spec.
