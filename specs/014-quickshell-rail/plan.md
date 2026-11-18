# Implementation Plan: Quickshell Rail

**Branch**: `014-quickshell-rail` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-quickshell-rail/spec.md`

## Summary

Draw the Mango rail in the existing Quickshell config and remove waybar.

- A new `Bar.qml` puts one top `PanelWindow` with the three islands on each
  screen.
- A `Tags` singleton streams `mmsg watch all-tags` for the workspaces island.
- The tray, clock, usage ring and status icons bind Quickshell services that
  the popups already use. The ring is drawn with QtQuick.Shapes instead of
  21 prebuilt SVGs.
- Popups open under the clicked capsule from its geometry. The runtime file
  and waybar signals between the two programs go away.
- Removed from `modules/mango`: `programs.waybar`, `railModule`, the ring
  SVGs and the `pkill` glue.

Details: [research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, pinned nixpkgs); QML (Qt 6) on
Quickshell 0.3.2.

**Primary Dependencies**: all already in the closure: quickshell 0.3.2
(`Quickshell.Services.SystemTray`, `QsMenuAnchor`, `Pipewire`, `UPower`,
`Networking`), mango 0.18.5 (`mmsg`), QtQuick.Shapes,
`kdePackages.kdeconnect-kde` QML (optional). Waybar and `procps` (pkill)
leave the module.

**Storage**: none new. The rail reads the existing
`$XDG_STATE_HOME/agent-usage/limits.json`.

**Testing**: `nix flake check`; the laptop toplevel build, which runs
`qmllint` over the QML dir (existing `system.extraDependencies`); manual
validation per [quickstart.md](quickstart.md).

**Target Platform**: NixOS `laptop`, the only machine with
`modules.mango.enable`.

**Project Type**: Declarative desktop configuration (NixOS/HM module).

**Performance Goals**: tag changes show without perceptible delay (SC-003);
no polling except the existing usage refresh; the rail is back within 2 s
after a restart (SC-006).

**Constraints**: same pixels as waybar (SC-001); one shell process
(SC-004); IPC targets unchanged (FR-016); inert with KDE Connect or Claude
Code off.

**Scale/Scope**: one module. About 5 new QML files (`Bar`, `Tags`,
`Tray`, `RailTooltip`, `PhoneIcon`), 7 edited (`shell`, `Rail`,
`RailPopup`, `Usage`, `Phone`, `Icons`, `Config`), about 250 lines of Nix
removed.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                  | How this plan complies                           | Status |
|----------------------------|--------------------------------------------------|--------|
| I. Evaluation-time check   | Store paths reach QML only through `replaceVars` | Pass   |
|                            | on `Config.qml`, where a missing placeholder     |        |
|                            | fails the build; `qmllint` covers the new files; |        |
|                            | `@pkill@` is removed together with its use       |        |
| II. Determinism            | No new inputs or sources; tag state is runtime   | Pass   |
| III. Fast default gate     | No new checks; qmllint stays in the toplevel     | Pass   |
|                            | build                                            |        |
| IV. Single source of truth | One `limits.json` reader (moved into `Rail`);    | Pass   |
|                            | palette unchanged; glossary Rail entry updated;  |        |
|                            | spec 012 R2 and spec 013's IPC contract marked   |        |
|                            | superseded                                       |        |
| V. Toggleable modules      | Everything stays in `mkIf cfg.enable`;           | Pass   |
|                            | `PhoneIcon.qml` is dropped from the build with   |        |
|                            | KDE Connect off, like `Phone.qml`                |        |

No ADR covers the rail, so nothing is contradicted. Spec 012 R2 is a
research decision; this spec supersedes it in its own text (R11).

**Post-design re-check**: unchanged, all Pass. Two items are marked "Verify
first" in research: R2 (`viewcrossmon` argument order) and R7 (tray menus on
Mango). Each has a fallback inside the same files.

## Project Structure

### Documentation (this feature)

```text
specs/014-quickshell-rail/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── rail-ipc.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
modules/mango/
├── default.nix          # drop programs.waybar, usageRing*, centered,
│                        # popupToggle, pkill; quickshellDir drops PhoneIcon.qml
│                        # when KDE Connect is off
├── scripts.nix          # drop railModule
└── quickshell/
    ├── shell.qml        # + Variants { Bar {} }
    ├── Bar.qml          # new: PanelWindow per screen, three islands
    ├── Tags.qml         # new: singleton, mmsg watch all-tags
    ├── Tray.qml         # new: drawer, SystemTray items, menus
    ├── RailTooltip.qml  # new: hover tooltip
    ├── PhoneIcon.qml    # new: reachable-phone icon (KDE Connect only)
    ├── Rail.qml         # toggle(target, screen, rect); limits moved in;
    │                    # runtime file and pkill removed
    ├── RailPopup.qml    # position from Rail.openRect when set
    ├── Usage.qml        # read Rail.limits instead of its own FileView
    ├── Phone.qml        # drop the RTMIN+9 signal
    ├── Icons.qml        # + network, volume, battery glyph sets
    └── Config.qml       # drop @pkill@
GLOSSARY.md              # Rail entry: Quickshell, not waybar
specs/012-mango-rail-bar/research.md  # R2: superseded note
```

**Structure Decision**: everything stays in `modules/mango`, the existing
feature module. New QML files sit next to the popups they share state with.

## Complexity Tracking

No constitution violations.
