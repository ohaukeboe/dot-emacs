# Implementation Plan: Review Threads

**Branch**: `016-review-threads` | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/016-review-threads/spec.md`

## Summary

Two new switches in the `@` menu, `--thread` and `--new-thread`, send review
hand-offs (`@ s`, `@ p`, `@ d`) to a **thread**: a Claude instance forked from
the main conversation with `claude --resume <id> --fork-session`. magit-review
stays agent-agnostic. It partitions each hand-off's items by thread, remembers
per-item thread links in memory, and passes a new optional THREAD argument
(`nil`, `new` or a buffer) to `magit-review-send-function`. The Claude glue in
`config.org` does the forking: it finds the main instance's conversation id in
`~/.claude/sessions/<cli-pid>.json`, starts the fork as instance `review-N`,
and delivers the prompt.

## Technical Context

**Language/Version**: Emacs Lisp (Emacs 30), literate in `workstation/emacs/config.org`

**Primary Dependencies**: magit, transient (20261101, has `:remember-value`),
claude-code-ide (flake input `claude-code-ide-src`, its internals as already
used by the paste helper), Claude Code CLI (`--resume`, `--fork-session`,
positional prompt)

**Storage**: In memory only: comment plists and a finding link hash. Read-only
use of `~/.claude/sessions/<pid>.json`.

**Testing**: ERT. `nix build .#test-magit-review -L` (`tests/magit-review.nix`).
The glue is checked by hand through [quickstart.md](quickstart.md).

**Target Platform**: NixOS workstations, Emacs with the ghostel terminal backend

**Project Type**: Emacs package (magit-review.el) plus config glue

**Performance Goals**: A hand-off to a live thread is as fast as today. A fork
returns once the CLI process has started. A no-submit fork waits at most
`my/claude-review-thread-timeout` (30 s).

**Constraints**: magit-review names no agent (FR-013). With `--thread` off,
behaviour is byte-identical to today (FR-012, SC-005). Items are marked sent
only after delivery (FR-011).

**Scale/Scope**: About 3 functions and 2 infixes in magit-review.el, one
extended helper plus a fork helper in `config.org`, and a handful of ERT tests.

All unknowns are resolved in [research.md](research.md) (R1–R7).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                    | Status | Note                                      |
|------------------------------|--------|-------------------------------------------|
| I. Evaluation-time checks    | N/A    | No Nix options added; elisp is ERT-tested |
| II. Determinism              | Pass   | No new inputs; `~/.claude` read at Emacs  |
|                              |        | runtime, not at evaluation                |
| III. Fast default gate       | Pass   | ERT stays `packages.test-magit-review`    |
| IV. Single source of truth   | Pass   | Glue in `config.org`; add **Thread** to   |
|                              |        | `GLOSSARY.md`; no ADR contradicted        |
| V. Toggleable modules        | N/A    | No module; feature off by default         |
| Docs parity (AGENTS/CLAUDE)  | N/A    | Neither needs a change                    |

Post-design re-check: unchanged, pass. The dependency on
`~/.claude/sessions/*.json` is a runtime coupling to a Claude Code internal,
recorded as a risk in research R2. It is not a constitution violation.

## Project Structure

### Documentation (this feature)

```text
specs/016-review-threads/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── send-function.md
│   └── menu.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
workstation/emacs/packages/
├── magit-review.el        # options, partition, links, THREAD arg to send function
└── magit-review-test.el   # ERT: partition, links, options, sent marking, no-thread parity
workstation/emacs/config.org
                           # "Claude Code" section: my/claude-code-ide-paste gains THREAD,
                           # fork helper, thread list, main-instance resolution
                           # magit-review prose: document -t / -n
GLOSSARY.md                # new term: Thread
tests/magit-review.nix     # unchanged unless new files are added
```

**Structure Decision**: No new files. magit-review.el owns the review side,
and `config.org` owns the Claude side, matching the existing split.

## Complexity Tracking

None.
