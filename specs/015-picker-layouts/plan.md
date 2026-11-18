# Implementation Plan: Picker Layouts

**Branch**: `015-picker-layouts` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/015-picker-layouts/spec.md`

## Summary

Give the Quickshell picker three layouts besides today's list: tiles (power
menu, with arm-then-run for Log out, Reboot and Power off), sources (screencast
chooser: screen cards with live thumbnails, window rows with app and tag) and
clipboard (search, rows with type and size, preview pane, paste with
Shift+Insert, copy only, forget). `mango-pick` gains `--layout` and exit status
10 for the alternate pick; stdout stays the picked value. Password filtering is
already done by `cliphist store` (research R3).

## Technical Context

**Language/Version**: QML (Qt 6, Quickshell 0.3.2), Nix, Bash via
`writeShellApplication`

**Primary Dependencies**: Quickshell (`Quickshell.Wayland` ScreencopyView,
`Quickshell.Io` Process), cliphist 0.7.0, wl-clipboard 2.3.0, wtype 0.5, mmsg
(Mango), xdg-desktop-portal-wlr 0.8.5

**Storage**: cliphist's database (unchanged); decoded image previews in
`$XDG_RUNTIME_DIR/mango-pick/`

**Testing**: build-time `qmlCheck` (qmllint) and shellcheck; manual
`quickstart.md` checks on the laptop

**Target Platform**: NixOS laptop, Mango session

**Project Type**: desktop shell config (Nix module + QML)

**Performance Goals**: every layout ready for input in under 200 ms (SC-006)

**Constraints**: dmenu contract kept (stdout = picked value, exit 1 = cancel);
xdpw's chooser treats any non-zero status as no choice

**Scale/Scope**: up to 750 clipboard entries (cliphist default), 5 power items,
a few screens and tens of windows

## Constitution Check

All five principles pass:

- **I. Evaluation-time verification**: new tools reach QML as `Config.qml`
  placeholders (`@cliphist@`), so a missing one fails the build; scripts stay
  `writeShellApplication` with `getExe` paths; qmllint runs on the new QML.
- **II. Determinism**: no new sources; all packages come from nixpkgs.
- **III. Fast default gate**: no new checks; `qmlCheck` is already in
  `system.extraDependencies`.
- **IV. Single source of truth**: adds **Picker** to `GLOSSARY.md`; the power
  items stay only in `mango-power-menu`.
- **V. Toggleable modules**: all changes sit inside `modules/mango` under
  `mkIf cfg.enable`.

Layout names are runtime input to `mango-pick`, not a Nix option, so no
`types.enum` applies; FR-002's fallback is the guard. Re-checked after Phase 1:
unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/015-picker-layouts/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/mango-pick.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
modules/mango/
├── default.nix          # Config.qml placeholders (cliphist), cliphist comment (R3),
│                        # portal chooser_cmd gains --layout sources
├── scripts.nix          # mango-pick --layout + status 10; power menu tiles;
│                        # clip-pick paste (wtype) / copy-only
└── quickshell/
    ├── Config.qml       # + cliphist path
    ├── shell.qml        # picker IPC open() gains layout
    ├── Picker.qml       # layout, parsing, arming, alt reply, delete
    ├── PickerList.qml   # picks the layout component; list stays here
    ├── PickerTiles.qml  # new: tiles (US1)
    ├── PickerClip.qml   # new: clipboard list + preview (US2)
    └── PickerSources.qml# new: screen cards + window rows (US3)
GLOSSARY.md              # + Picker
```

**Structure Decision**: one component per layout beside the existing list, all
fed by the one `Picker` singleton, so the FIFO, cancel and one-at-a-time rules
stay in a single place.

## Complexity Tracking

None.
