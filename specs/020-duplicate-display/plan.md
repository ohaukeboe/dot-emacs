# Implementation Plan: Duplicate Display

**Branch**: `020-duplicate-display` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/020-duplicate-display/spec.md`

## Summary

The displays card learns to make one display a copy of another, through an
arrangement switch (Extend, Duplicate, Only panel, Only external) and by
dropping one tile on another.

Mango has no duplicate mode (research R1). The shell makes one itself, from
three parts:

1. **The picture**: a full-screen overlay window on the copy that shows the
   source through Quickshell's own `ScreencopyView` (R2). No new package.
2. **Off the desktop**: the copy is parked at a position far below its
   source, with a gap the pointer cannot cross (R3). That position is also
   the record of which display copies which, so the real state is read
   from `wlr-randr` like everything else, and Apply, Revert and a display
   setup applied by kanshi need nothing new (R4).
3. **The guard**: a small script that runs while a copy exists and moves
   focus and windows off it, for the cases a gap does not stop (R5).

The stack rules live in `displayLayout.mjs` with the build-time test
(R6); the card and the canvas only draw them.

## Technical Context

**Language/Version**: QML (Quickshell 0.3.2, Qt 6), one ECMAScript module,
Bash, Nix

**Primary Dependencies** (nixpkgs only, all already in the session):
Quickshell's `Quickshell.Wayland` `ScreencopyView`, wlr-randr, Mango 0.18.5
(`mmsg`), jq

**Storage**: none (FR-028). Which display copies which is read back from
the displays' positions.

**Testing**: `nix flake check`; the system build, which runs `qmlCheck`,
shellcheck on the guard and `mango-display-layout-test`; `just qs-check`;
then [quickstart.md](quickstart.md) by hand with two and three displays

**Target Platform**: NixOS, Mango session

**Project Type**: desktop shell configuration

**Performance Goals**: a change on the source is on the copy within 0.1 s
(SC-003); the frame rate of the capture at 3840×2160 is to be measured on
real hardware (quickstart M3) and a number put into SC-003

**Constraints**: nothing changes before Apply (FR-014); a copy never holds
the pointer, focus or a window (FR-004); no display black or frozen for
more than 5 s (FR-025); at most 3 copies and a layout under 8192 logical
pixels tall while any display is a copy (R3)

**Scale/Scope**: about 90 lines in one new QML file, 200 changed lines in
three QML files, 180 lines of layout module, 150 lines of test, 60 lines of
shell script, 30 lines of Nix

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                           | Status | Note                                  |
|-------------------------------------|--------|---------------------------------------|
| I. Evaluation-time verification     | pass   | store paths; shellcheck; layout test  |
| II. Determinism and reproducibility | pass   | nixpkgs only, no new input            |
| III. Fast default gate              | pass   | layout test stays in the system build |
| IV. Single source of truth          | pass   | the gap is one Nix value (R3)         |
| V. Toggleable modules               | pass   | inside `modules.mango`, no new option |

The parking gap is used by the layout module, the guard and
`mango-display-setup`. It is declared once in `modules/mango/common.nix`
and reaches the three as a `Config.qml` value and a script argument, so
they cannot disagree. Re-checked after Phase 1: unchanged.

No ADR: the parking position is surprising, but it is contained in one
module and easy to replace if Mango gains a duplicate mode (R1, R3).

## Project Structure

### Documentation (this feature)

```text
specs/020-duplicate-display/
├── spec.md
├── plan.md              # this file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── displays.md      # keys, parking, the guard, the setup entry
├── mocks/duplicate-display-mocks.html
└── checklists/requirements.md
```

### Source Code

```text
modules/mango/
├── quickshell/
│   ├── Mirror.qml            # new: overlay on a copy, ScreencopyView
│   ├── Displays.qml          # copyOf in the layouts; arrange, stack,
│   │                         # separate, makeSource; repair; the guard
│   ├── DisplaysCard.qml      # arrangement switch; arrow keys; copy settings
│   ├── DisplayCanvas.qml     # stack tiles; drop on a tile
│   ├── displayLayout.mjs     # park, unpark, stack rules, arrangements
│   ├── displayLayout.test.mjs
│   ├── Config.qml            # parkGap, panel, copyGuard, lidSync
│   ├── Rail.qml              # a popup never opens on a copy
│   ├── shell.qml             # Variants Mirror
│   └── README.md             # no new component (see below)
├── common.nix                # parkGap
├── quickshell.nix            # the new placeholders
└── scripts.nix               # mango-copy-guard; mango-display-setup and
                              # mango-lid-sync changes
GLOSSARY.md                   # copy, source, stack (displays)
specs/018-display-layout-card/contracts/displays.md   # points here for --pos
```

**Structure Decision**: the feature extends the four files of specs/018
and adds one. `Mirror.qml` is the only new surface; it is a window, not a
design-system component, so the README's component tables do not change.
The arrangement switch is the existing `Segmented`. Everything that
decides (what a choice means, what a drop does, how a broken stack is
repaired) is in `displayLayout.mjs`, because that is what the build can
test (FR-033). `Displays.qml` stays the only place that runs programs.

## Complexity Tracking

None.
