# Implementation Plan: Beads Issue Relations in Magit

**Branch**: `magit-beads` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-beads-issue-relations/spec.md`

## Summary

Mark each issue the Magit beads section already lists with the relations it takes
part in — its parent, the issues blocking it, and how many issues depend on it —
and give four commands to move along those relations and back again.

Technical approach: keep the section's two existing `bd` calls unchanged, and add
two more that fire only when relations actually exist. `bd blocked --json` is the
single authority on what is blocked and by what, so blocker resolution is never
reimplemented in Emacs; one `bd list --id=… --all --json` resolves every relation
target's title and status in a single flat query. Relations are held in a
buffer-local table keyed by issue id, leaving the `magit-section` value a bare id
so every existing command keeps working. Marks are compact glyphs in the
collapsed heading and full `Parent:` / `Blocked by:` lines in the body. The four
commands hang off the existing `#` transient rather than taking Magit keys.

## Technical Context

**Language/Version**: Emacs Lisp, `lexical-binding: t`, GNU Emacs 31.1 (the
version this configuration installs; `defvar-keymap`, `and-let*` and `natnum`
are already used, so nothing older is targeted)

**Primary Dependencies**: `magit` / `magit-section`, `transient`, `json-parse-string`
(built in), `seq`, `cl-lib`, `ansi-color`. External: the `bd` CLI, 1.2.2 (dev).

**Storage**: none. The tracker's Dolt database under `.beads/` is the only
durable state and this feature only reads it.

**Testing**: ERT in `workstation/emacs/packages/beads-test.el`, against a fake
`bd` shell script on `PATH`; exposed as `nix build .#test-beads -L`, a new
`packages.*` attribute modelled on `tests/emacs-sops-save.nix`.

**Target Platform**: NixOS with Home Manager, three machines. The package is
installed by `workstation/home.nix` copying `workstation/emacs/packages/` into
`~/.config/emacs/packages/`.

**Project Type**: an Emacs Lisp package inside a Nix configuration repository.

**Performance Goals**: no extra `bd` call when the listed issues have no
relations (measured: the section stays at today's 0.29 s); at most two extra
calls, 0.27 s, when they do — flat in the number of issues, never per issue.

**Constraints**: the section is drawn synchronously during
`magit-status-sections-hook`, including from the auto-refresh timer, so every
call on that path is felt. Issue sections start collapsed, so anything that must
be seen at a glance belongs in the heading. `window-body-width` must keep being
used rather than `window-max-chars-per-line` — see the comment on
`beads--width` and `dot-emacs-l3y`.

**Scale/Scope**: this repository's tracker holds 79 issues, 7 open; the section
lists single digits. `beads.el` is 631 lines today and this feature adds roughly
200.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1 design. Both passes
recorded below.*

### I. Evaluation-Time Verification

Nix evaluation cannot see Emacs Lisp behaviour, so the principle's operative
clause here is its spirit: make the mistake fail where it is cheap. The feature
adds no Nix option and no shell script, so there is nothing to express as an
`mkOption` or an assertion. What it does add is ~200 lines of behaviour that
nothing currently runs automatically — `beads-test.el` is invoked by a command in
its own header. The plan closes that with `packages.test-beads`, which makes the
suite a build. **Pass, with the test package as a required task, not an optional
one.**

### II. Determinism and Reproducibility

No new external source, so no new pin. `beads.el` is a tracked file in this repo.
Every new file must be `git add`ed before `nix build` — called out in
[quickstart.md](./quickstart.md) step 4. No ambient state is read at evaluation
time. **Pass.**

### III. Fast Default Gate, Heavy Tests Opt-In

`test-beads` builds an Emacs closure, so it goes in `packages.*`, not `checks.*`,
and carries the comment stating the command and when to run it — exactly as
`test-disk-layout` and `test-emacs-sops-save` already do. `nix flake check` stays
untouched and therefore stays fast. **Pass.**

### IV. Single Source of Truth

- `workstation/emacs/packages/beads.el` is the package's source of truth and is
  edited directly; `workstation/emacs/config.org` holds only the `use-package`
  block and the prose describing the keys, which must be updated to describe the
  new transient entries. No generated `.el` is touched.
- New domain terms — parent, blocker, dependent, relation mark, jump history —
  belong in `CONTEXT.md` beside the existing `Ready` / `In progress` / `Beads
  section` entries, and the existing `Ready` entry's rule ("Computed by `bd`,
  never derived in Emacs") is the reason R2 chose `bd blocked`. Adding the terms
  is a required task.
- `AGENTS.md` / `CLAUDE.md` parity: this feature changes neither file's subject
  matter (they describe the repository's workflow, not Emacs key bindings), so
  no mirror edit is needed. Re-checked after design: still none.

**Pass.**

### V. Toggleable Modules, Declarative Machines

Not a NixOS feature module; nothing to gate behind `mkEnableOption`. The
equivalent discipline — cost nothing when the feature does not apply — is met
structurally: a repository without `.beads/` still makes no `bd` call, and a
tracker whose listed issues have no relations makes no *extra* call and renders
byte-identically to today (FR-005, SC-005). **Pass.**

### Additional constraints

`nix fmt` before commit, with unrelated churn reverted. Conventional Commits.
Work tracked in `bd`, not in a markdown list — the tasks for this feature become
beads issues at `/speckit-tasks` time.

### Post-design re-check

Phase 1 introduced no new dependency, no new option outside `beads.el`'s own
`defcustom`, and no new Nix module. The one design decision that touches the
constitution is choosing `bd blocked` over a cheaper local join, which is
Principle IV's single-source-of-truth rule applied to blocker resolution, and it
costs 0.10 s only when a listed issue has dependencies at all. **All five
principles still pass.** No deviation is outstanding: the one the first pass
found — a relative performance bound the design could not meet in every case —
was resolved by amending the criterion it broke, not by accepting a violation.
See Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/002-beads-issue-relations/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — R1..R10, all measured
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output — validation guide
├── contracts/
│   ├── bd-cli.md        # What this feature asks of the bd CLI
│   └── commands.md      # Commands, transient, faces, options
├── checklists/
│   └── requirements.md  # Spec quality checklist (all items pass)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
workstation/emacs/
├── packages/
│   ├── beads.el         # The package. All behaviour changes land here.
│   └── beads-test.el    # ERT suite; fake bd gains `blocked` and `--id` cases
└── config.org           # use-package block + the prose describing the keys

tests/
└── beads.nix            # New: runs the ERT suite in a build (Principle III)

flake.nix                # New packages.test-beads attribute
CONTEXT.md               # New domain terms under "Emacs / beads"
```

**Structure Decision**: no new module and no new directory. `beads.el` is a
self-contained Emacs package that already owns everything this feature touches —
sections, transient, `bd` invocation, the show buffer — so the change is local to
it plus its test. The only files outside it are the ones the constitution
requires: a `packages.*` test attribute (Principle III), the domain vocabulary
(Principle IV), and the literate config's prose describing what `#` now offers.

Within `beads.el` the change follows the file's existing section comments:
`;;; Talking to bd` gains the relation calls, `;;; Formatting` gains the mark
rendering, `;;; Sections` gains the relation table and the body lines,
`;;; Acting on issues` gains the navigation commands and the jump history, and
`;;; The transient` gains the `Relations` column.

## Complexity Tracking

> No outstanding violation of the constitution, and none of the spec.

The first Constitution Check pass found one conflict, since resolved. The
original SC-004 required the section to draw "within 10% of the time it takes
today", which the design meets when the listed issues have no relations and
cannot meet when they do: the marks need each relation target's title and status,
and `bd` exposes neither on the cheap list calls.

The two cheaper designs were both rejected on grounds that outrank the bound.
Joining `bd`'s thin `dependencies` edges against locally known statuses costs
nothing but reimplements blocker resolution in Emacs — the exact drift
`CONTEXT.md` forbids and FR-017 restates. `bd show` per issue costs 0.12 s **per
id**, which is worse than the chosen design from three issues up.

What the design does instead is make the cost proportional to the relations
present: no relations ⇒ no extra call at all; ready issues never trigger the
blocked call, being unblocked by construction; dependents are counted for free
from a field both existing calls already return, and identified only on demand.

SC-004 was therefore amended, on 2026-09-23, into SC-004a (the no-relations case:
no extra request, within 5% of today) and SC-004b (the relations case: at most two
extra requests, neither growing with the number of issues, under 0.6 s). Both are
verifiable by counting `bd` invocations rather than by timing, which
[quickstart.md](./quickstart.md) step 3 does.
