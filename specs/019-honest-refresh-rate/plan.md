# Implementation Plan: Honest Refresh Rate

**Branch**: `019-honest-refresh-rate` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-honest-refresh-rate/spec.md`

## Summary

The displays card shows a refresh rate the display did not take, and
offers rates the connection cannot carry. Research found that the failing
change is refused, not ignored (R1), that a refusal can still leave some
displays changed (R3), and that a dry run tells beforehand which rates
fail (R2).

One change. After every Apply the card reads the real state and shows
it, whatever the exit code: nothing changed means no keep question and a
line that names the display and rate; anything changed means the keep
question.

A second change, dry-running the rates of the shown resolution and hiding
those that fail, was built and removed: each dry run makes the tested
display's background blink (research R5).

## Technical Context

**Language/Version**: QML (Quickshell 0.3.2, Qt 6), one ECMAScript module

**Primary Dependencies**: wlr-randr 0.5.0, already in the session as
`Config.wlrRandr`; Mango 0.18.5

**Storage**: none

**Testing**: `nix flake check`; the system build, which runs `qmlCheck`
and `mango-display-layout-test`; `just qs-check`; then
[quickstart.md](quickstart.md) by hand in the dock

**Target Platform**: NixOS, Mango session

**Project Type**: desktop shell configuration

**Performance Goals**: the card opens as fast as before (specs/018
SC-002); the rates of one resolution are sorted out within 4 s of
showing it; the real state is on show within 2 s of Apply (SC-001)

**Constraints**: opening the card changes nothing on any display
(FR-007, SC-005)

**Scale/Scope**: about 70 lines in `Displays.qml`, 15 in
`DisplaysCard.qml`, 40 in the layout module, 40 of test. No Nix change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                           | Status | Note                                 |
|-------------------------------------|--------|--------------------------------------|
| I. Evaluation-time verification     | pass   | new logic in the build-time test     |
| II. Determinism and reproducibility | pass   | no new input or package              |
| III. Fast default gate              | pass   | test stays in the system build       |
| IV. Single source of truth          | pass   | specs/018 FR-018 and contract fixed  |
| V. Toggleable modules               | pass   | inside `modules.mango`, no new option |

Principle III asks for a guard with a bug fix that evaluation could not
catch: the comparison of asked and real state is a tested function
(research R8). Principle IV: this feature contradicts two statements of
specs/018 (FR-018, and "any other exit: nothing changed" in its
contract); both get a line pointing here in the same change. Re-checked
after Phase 1: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/019-honest-refresh-rate/
├── spec.md
├── plan.md              # this file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── displays.md      # the dry run, the outcome of an Apply, the line
└── checklists/requirements.md
```

### Source Code

```text
modules/mango/quickshell/
├── displayLayout.mjs       # modeArg, notTaken, notTakenLine
├── displayLayout.test.mjs  # cases for notTaken
└── Displays.qml            # asked layout; outcome after Apply
specs/018-display-layout-card/
├── spec.md                 # FR-018: replaced by specs/019
└── contracts/displays.md   # "Applying": exit code note points here
```

**Structure Decision**: no new file. The decision about an Apply's outcome moves
from the process's exit handler into `took`, where the fresh state is at
hand. `DisplaysCard.qml` is unchanged.

## Complexity Tracking

None.
