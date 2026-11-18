# Implementation Plan: Proton Pass Copy Chords

**Branch**: `017-pass-copy-chords` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-pass-copy-chords/spec.md`

## Summary

Bring the Mango popup's keys in line with the COSMIC popup: `Ctrl+U`,
`Ctrl+O`, `Ctrl+L` copy the username, one-time code and website;
`Right`/`Left`/`Shift+Tab` open and leave the field list; `PageUp`/`PageDown`
work in the field list; `Ctrl+Shift+S`/`Ctrl+Shift+R` sign in and retry.

The reducer in `cosmic-pass` already does all of it for the COSMIC popup
(`Msg::CopyUsername`, `CopyTotp`, `CopyUrl`, `Startup`, `PageDown` in
fields mode). The work is four new `serve` intents in `cosmic-pass`, then
key handling in `PassPopup.qml` here (research R1, R2).

## Technical Context

**Language/Version**: QML (Quickshell, Qt 6) here; Rust, edition 2024, in
`cosmic-pass`

**Primary Dependencies**: the `cosmic-pass` flake input (`serve`, specs/016)

**Storage**: none

**Testing**: in `cosmic-pass`, `just check` with new cases in
`tests/serve_protocol.rs`; here, `nix flake check`, `qmlCheck`,
`just qs-check`, then [quickstart.md](quickstart.md) by hand

**Target Platform**: NixOS, Mango session

**Project Type**: desktop shell configuration plus a small change to a
companion application in another repository

**Performance Goals**: none new; a chord costs what `Enter` costs today

**Constraints**: no copied value in a snapshot, log or the clipboard
history (FR-005, contract guarantee 3 of `serve`); old backends ignore the
new intents (FR-014)

**Scale/Scope**: about 15 lines of Rust plus tests in `cosmic-pass`; about
20 lines of QML and a contract table here

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                           | Status | Note                            |
|-------------------------------------|--------|---------------------------------|
| I. Evaluation-time verification     | pass   | qmlCheck, flake check, builds   |
| II. Determinism and reproducibility | pass   | backend pinned in `flake.lock`  |
| III. Fast default gate              | pass   | no new heavy test               |
| IV. Single source of truth          | pass   | keys in one contract (shell.md) |
| V. Toggleable modules               | pass   | inside `modules.mango`, no opt  |

No new option, no new module, no new dependency. Re-checked after Phase 1:
unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/017-pass-copy-chords/
├── spec.md
├── plan.md              # this file
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── keys.md          # the delta to specs/016 contracts/shell.md and serve
└── checklists/requirements.md
```

### Source Code

```text
~/projects/cosmic-pass/                 # first, pushed before the bump
├── src/serve/protocol.rs               # 4 intents → existing Msg
├── tests/serve_protocol.rs             # one test per new intent + guarantees
├── specs/004-serve-mode/contracts/serve-protocol.md   # intent table rows
└── specs/004-serve-mode/data-model.md                  # intent table rows

dot-emacs/
├── flake.lock                          # cosmic-pass bump
├── modules/mango/quickshell/PassPopup.qml   # key handling, hint line
└── specs/016-proton-pass-quick-access/contracts/shell.md   # keys table
```

**Structure Decision**: no new files outside the spec. All key handling
stays in the query field's `Keys.onPressed` in `PassPopup.qml`, where the
existing keys are.

## Complexity Tracking

None.
