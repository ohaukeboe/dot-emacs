# Implementation Plan: Display Layout Card

**Branch**: `018-display-layout-card` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-display-layout-card/spec.md`

## Summary

A floating card in the Mango shell that shows the connected displays to
scale, lets the user drag them and change each one's settings, applies the
result in one step, and reverts after ten seconds unless kept. It replaces
wdisplays.

Quickshell has no binding for the output management protocol, so the card
reads with `wlr-randr --json` and applies with one `wlr-randr` call that
names every display (research R1). State lives in a singleton so it
survives the card's window when a display turns off (R3). The geometry
(snap, settle, normalise, argument list) is one plain JavaScript module
with a build-time test (R4). `kanshictl status` names the matched display
setup (R6) and `mango-display-setup --copy` fills the clipboard (R7).

## Technical Context

**Language/Version**: QML (Quickshell 0.3.2, Qt 6), one ECMAScript module,
Nix

**Primary Dependencies** (nixpkgs only): wlr-randr 0.5.0, kanshi 1.9.0
(`kanshictl`), wl-clipboard; all three are already in the session

**Storage**: none (FR-024)

**Testing**: `nix flake check`; the system build, which runs `qmlCheck` and
the new `mango-display-layout-test`; `just qs-check`; then
[quickstart.md](quickstart.md) by hand with a second display

**Target Platform**: NixOS, Mango session

**Project Type**: desktop shell configuration

**Performance Goals**: the card shows the layout within 1 s of the open
command (SC-002); a drag follows the pointer every frame

**Constraints**: no display changes before Apply (FR-015); one atomic
change per Apply and per Revert; revert between 10 and 11 s (SC-003); never
all displays off (SC-004)

**Scale/Scope**: about 450 lines of QML in three new files, 150 lines of
layout module, 80 lines of test, 40 lines of Nix

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                           | Status | Note                                  |
|-------------------------------------|--------|---------------------------------------|
| I. Evaluation-time verification     | pass   | store paths; qmlCheck; layout test    |
| II. Determinism and reproducibility | pass   | nixpkgs only, no new input            |
| III. Fast default gate              | pass   | layout test runs in milliseconds      |
| IV. Single source of truth          | pass   | setup entry format in one script      |
| V. Toggleable modules               | pass   | inside `modules.mango`, no new option |

The layout test is wired like `qmlCheck` (`system.extraDependencies`), not
as a flake check, so `nix flake check` stays as fast as it is. No new
option and no new module. Re-checked after Phase 1: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/018-display-layout-card/
├── spec.md
├── plan.md              # this file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── displays.md      # IPC, keys, the wlr-randr call, --copy
├── mocks/display-mocks.html
└── checklists/requirements.md
```

### Source Code

```text
modules/mango/
├── quickshell/
│   ├── Displays.qml          # new singleton: state, read, apply, keep/revert
│   ├── DisplaysCard.qml      # new: the overlay window and the card
│   ├── DisplayCanvas.qml     # new: the to-scale layout with drag
│   ├── displayLayout.mjs     # new: geometry and the wlr-randr arguments
│   ├── displayLayout.test.mjs  # new: run at build time, not installed
│   ├── Config.qml            # wlrRandr, kanshictl, displaySetup
│   ├── Rail.qml              # "displays" in the target comment only
│   └── shell.qml             # IpcHandler "displays", Variants DisplaysCard
├── quickshell.nix            # placeholders; copy *.mjs; the layout test
├── scripts.nix               # mango-display-setup --copy
└── session.nix               # wdisplays out; "Displays" desktop entry
GLOSSARY.md                   # new term: Displays card
specs/011-mango-docking-essentials/quickstart.md   # step 2 names the card
```

**Structure Decision**: three QML files, split by what changes together.
`Displays.qml` is the only place that runs programs and holds the three
layouts of [data-model.md](data-model.md). `DisplaysCard.qml` is the
window and the controls, built from `FloatingCard`, `Card`, `Segmented`,
`Pill`, `ListRow`, `Reveal` and `Hint`. `DisplayCanvas.qml` is the one
new surface; it is not added to the design system's component table, since
nothing else uses it (README, "Adding a component"). The geometry sits in
`displayLayout.mjs` so the same file is imported by QML and by the test.

## Complexity Tracking

None.
