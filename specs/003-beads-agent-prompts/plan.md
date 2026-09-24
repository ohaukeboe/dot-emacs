# Implementation Plan: Prompt the Coding Agent from a Beads Issue

**Branch**: `main` | **Date**: 2026-09-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-beads-agent-prompts/spec.md`

## Summary

Add two commands to the beads transient (`#`) that hand the issue at point to the
repository's Claude Code session: `i` pastes `Beads issue <id>: ` into the
session's input and focuses it for the developer to finish; `e` submits a prepared,
configurable instruction that has the agent read the issue through `bd show`,
explore the code, and reply with its understanding and decision questions —
explicitly without implementing, editing, committing or starting a skill.

Technical approach: `beads.el` stays ignorant of `claude-code-ide`. It gains two
function-valued options — "is there a session" and "send TEXT, SUBMIT" — and the
literate config fills them with adapters over `claude-code-ide`'s own session
resolution. The adapter for sending is the review hand-off's existing paste
helper, lifted out so both features share it. The ERT suite drives the commands
through recorders in place of those options.

## Technical Context

**Language/Version**: Emacs Lisp, `lexical-binding: t`, GNU Emacs 31.1.

**Primary Dependencies**: `transient`, `magit-section`, `format-spec` (built in).
In config.org only: `claude-code-ide` at the pinned `claude-code-ide-src` flake
input, using `claude-code-ide--resolve-session`,
`claude-code-ide-mcp--sessions-for-project`,
`claude-code-ide--get-working-directory`, `claude-code-ide-mcp-session-buffer`,
`claude-code-ide--terminal-send-return` — all already relied on by the review
hand-off except `--sessions-for-project`, which the `C-c o c` wrappers already use.

**Storage**: none.

**Testing**: ERT in `workstation/emacs/packages/beads-test.el`, run by
`nix build .#test-beads -L`; manual steps in [quickstart.md](./quickstart.md) for
the adapter and SC-003.

**Target Platform**: NixOS + Home Manager, three machines; terminal backend
`ghostel`.

**Project Type**: Emacs Lisp package inside a Nix configuration repository.

**Performance Goals**: the transient's availability check is a hash lookup; no
`bd` call is added anywhere.

**Constraints**: every refusal must happen before any byte reaches the terminal
(FR-013). Multi-line text must arrive as one paste, never typed (research R2).

**Scale/Scope**: ~80 lines in `beads.el`, ~100 in `beads-test.el`, ~30 moved or
added in `config.org`.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1.*

### I. Evaluation-Time Verification

No Nix option or shell script is added. The behaviour added is covered where it
can be cheaply: the ERT suite, already a build (`packages.test-beads`), gains the
new cases. `defcustom`s carry the narrowest `:type` (`string`,
`(choice (const nil) function)`). **Pass.**

### II. Determinism and Reproducibility

No new source or pin. The adapter depends on private `claude-code-ide` functions
of the already-pinned input; the existing comment in the Claude Code section
("re-check them when bumping the flake input") is extended to name the new ones.
**Pass.**

### III. Fast Default Gate, Heavy Tests Opt-In

Tests go into the existing `packages.test-beads`; `checks.*` untouched. **Pass.**

### IV. Single Source of Truth

- `beads.el` edited directly; `config.org` holds only the adapters, the
  `use-package` settings and prose. No generated `.el` touched.
- The terminal paste logic stays in one place: the review helper is moved and
  shared, not copied (research R2).
- New domain terms — *agent session*, *quick prompt*, *explore prompt* — added to
  `CONTEXT.md` under "Emacs / beads". Required task.
- `AGENTS.md` / `CLAUDE.md`: subject matter unchanged; no mirror edit.

**Pass.**

### V. Toggleable Modules, Declarative Machines

Not a NixOS module. The inert-when-absent discipline holds: with the options nil
(any configuration that does not set them) the entries are inapt and no agent code
runs; a repository without `.beads/` still shows no section. **Pass.**

### Post-design re-check

Phase 1 added two `defcustom` strings, two function-valued options and one moved
helper. No dependency added to the test closure, no new module, no new flake
input. **All five principles pass; nothing in Complexity Tracking.**

## Project Structure

### Documentation (this feature)

```text
specs/003-beads-agent-prompts/
├── plan.md              # This file
├── spec.md
├── research.md          # R1..R8
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── commands.md      # Commands, options, agent seam, transient, adapters
│   └── explore-prompt.md# Default explore text and its required clauses
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks — not created here
```

### Source Code (repository root)

```text
workstation/emacs/
├── packages/
│   ├── beads.el         # New ";;; Prompting the agent" section; transient column
│   └── beads-test.el    # Recorder-driven cases for both commands
└── config.org           # Claude Code: shared paste helper + session predicate;
                         # Magit review: call the shared helper;
                         # Beads: set the two options, document `i` and `e`
CONTEXT.md               # Agent session, quick prompt, explore prompt
```

**Structure Decision**: no new file. `beads.el` gets one new section between
`;;; Acting on issues` and `;;; The transient`, holding the options, the two
commands and `beads--agent-available-p`; the transient gains an `Agent` column.
Everything that names `claude-code-ide` lives in `config.org`, next to the code
that already names it.

## Complexity Tracking

> No violation of the constitution or the spec.
