# Implementation Plan: Mango Rail Bar

**Branch**: `012-mango-rail-bar` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/012-mango-rail-bar/spec.md`

## Summary

Restyle the Mango session's waybar into a narrow left rail that matches the
reference's "Pebble Shell" layout: frame-coloured, 32 px wide, workspaces as
dots with a numbered active pill (native `mango/workspaces`, now that waybar
0.16.0 is pinned), a stacked 24-hour clock, icon-only status modules, the
tray behind a chevron drawer, and a gear at the bottom. The gear and the
clock open two small Quickshell popups (quick controls and calendar),
toggled from waybar over Quickshell IPC. Details: [research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, pinned nixpkgs), NixOS module with Home
Manager as a NixOS module; QML (Qt 6) for the popups; GTK3 CSS for waybar.

**Primary Dependencies** (nixpkgs only): waybar 0.16.0 (`mango/workspaces`,
group drawers), quickshell 0.3.2 (HM `programs.quickshell`; Pipewire,
UPower, Bluetooth, Networking services), brightnessctl, qmllint from
`qt6.qtdeclarative` (build check only). Existing: mango, swayosd, blueman,
power-profiles-daemon, `mango-power-menu`, `nerd-fonts.symbols-only`.

**Storage**: N/A.

**Testing**: Nix evaluation and build (`nix flake check`, laptop toplevel
build) plus a `qmllint` derivation in `system.extraDependencies`; manual
validation per [quickstart.md](quickstart.md).

**Target Platform**: NixOS `laptop` (the only machine with
`modules.mango.enable`), docked to known and unknown displays.

**Project Type**: Declarative desktop configuration (NixOS/HM module).

**Performance Goals**: Popups open within one frame of the click as far as
the user can tell; rail appears with the session as today (SC-005).

**Constraints**: Rail ≤ 32 logical px (FR-002); COSMIC session unaffected
(FR-014); all services bound to `mango-session.target`.

**Scale/Scope**: One module (`modules/mango`), one QML file, ~150 lines of
Nix changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                  | How this plan complies                           | Status |
|----------------------------|--------------------------------------------------|--------|
| I. Evaluation-time check   | QML rendered by `replaceVars` (store paths,      | Pass   |
|                            | missing placeholder fails build); `qmllint`      |        |
|                            | derivation; `lib.getExe` for `qs`, brightnessctl |        |
| II. Determinism            | nixpkgs packages only; no new inputs or ambient  | Pass   |
|                            | state                                            |        |
| III. Fast default gate     | `qmllint` in `system.extraDependencies`, not     | Pass   |
|                            | in `checks.*`                                    |        |
| IV. Single source of truth | Colours stay `bg`/`card`/`accent` in             | Pass   |
|                            | `default.nix`, passed into the QML; new terms    |        |
|                            | Rail and Quick controls go in `GLOSSARY.md`      |        |
| V. Toggleable modules      | All inside `mkIf cfg.enable` of `modules/mango`; | Pass   |
|                            | Quickshell service bound to the Mango target     |        |

No ADR contradicted. ADR-worthy? No: replacing a popup toolkit later is a
one-file change; the choice is recorded in research R4.

**Post-design re-check**: unchanged, all Pass. The one risk (research R9,
`qmllint` and C++-registered Quickshell types) only weakens the check, not
the build.

## Project Structure

### Documentation (this feature)

```text
specs/012-mango-rail-bar/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/popup-ipc.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
modules/mango/
├── default.nix          # waybar rail settings + CSS, programs.quickshell,
│                        # qmllint check, brightnessctl
├── scripts.nix          # unchanged (powerMenu reused)
└── quickshell/
    └── shell.qml        # controls + calendar popups, @placeholders@
GLOSSARY.md              # Rail, Quick controls
```

**Structure Decision**: Everything stays in `modules/mango`; the QML lives
beside the module as a source file substituted at build time, in line with
how `scripts.nix` renders shell code.

## Complexity Tracking

None: no constitution violations.
