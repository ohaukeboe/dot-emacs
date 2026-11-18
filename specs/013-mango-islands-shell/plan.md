# Implementation Plan: Mango Islands Shell

**Branch**: `013-mango-islands-shell` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-mango-islands-shell/spec.md`

## Summary

Restyle the Mango session to design D: the waybar rail becomes three
floating capsules through CSS alone, and one `palette` attrset in
`modules/mango/default.nix` replaces every colour literal in the module.
Quick controls, the calendar and the detail pages are redrawn with D's
controls. Two additions: a Claude usage pill and popup, fed by two state
files that a new `workstation/agents/usage.nix` writes (rate limits tapped
from the status-line input, token counts from a timer-driven collector), and
a KDE Connect phone card and detail page bound to KDE Connect's own QML
module. Details: [research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, pinned nixpkgs), NixOS module with Home
Manager as a NixOS module; QML (Qt 6) for popups; GTK3 CSS for waybar; Bash
(`writeShellApplication`) for waybar module scripts; Python 3
(`writers.writePython3Bin`) for the token collector.

**Primary Dependencies** (nixpkgs only, all already in the closure): waybar,
quickshell, `kdePackages.kdeconnect-kde` (its `org.kde.kdeconnect` QML
module), jq, `nerd-fonts.symbols-only`, `qt6.qtdeclarative` (qmllint,
QtQuick.Dialogs). Existing: `context-statusline`, mango, swaybg, foot, mako,
fuzzel, swaylock.

**Storage**: Two JSON files under `$XDG_STATE_HOME/agent-usage/`
([contract](contracts/usage-record.md)).

**Testing**: `nix flake check`; laptop toplevel build (runs `qmllint`);
`checks.context-statusline` extended for the tap; new `checks.agent-usage`
for the collector against fixture transcripts;
manual validation per [quickstart.md](quickstart.md).

**Target Platform**: NixOS `laptop`, the only machine with
`modules.mango.enable`.

**Project Type**: Declarative desktop configuration (NixOS/HM modules).

**Performance Goals**: Popups open within 250 ms (SC-005); the status-line
tap adds one small atomic write per render; the collector reads only
transcripts modified in the last 8 days.

**Constraints**: No credential is read (FR-016); COSMIC session unaffected;
everything Mango-specific stays inside `mkIf cfg.enable`; one popup at a
time.

**Scale/Scope**: Two modules touched (`modules/mango`,
`workstation/agents`), about eight QML files replacing one, four waybar
custom modules, one collector, two tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                  | How this plan complies                           | Status |
|----------------------------|--------------------------------------------------|--------|
| I. Evaluation-time check   | `palette` attrset: missing key fails evaluation; | Pass   |
|                            | `replaceVars` on `Config.qml`; qmllint over the  |        |
|                            | QML dir; scripts via `writeShellApplication`;    |        |
|                            | collector via `writePython3Bin`; `getExe` for    |        |
|                            | every binary; `agents.usage.enable` typed option |        |
| II. Determinism            | No new inputs; state files are runtime data, not | Pass   |
|                            | read at evaluation                               |        |
| III. Fast default gate     | qmllint stays in `system.extraDependencies`; the | Pass   |
|                            | two tests are fixture-only, so they join the     |        |
|                            | existing `checks.context-statusline`             |        |
| IV. Single source of truth | One palette; one contract file per interface;    | Pass   |
|                            | glossary gets Island, Usage pill, Phone card and |        |
|                            | a corrected Rail entry                           |        |
| V. Toggleable modules      | Mango parts in `mkIf cfg.enable`; usage writers  | Pass   |
|                            | behind `agents.usage.enable`; the modules meet   |        |
|                            | only at the state files; KDE Connect parts       |        |
|                            | generated only when its service is enabled       |        |

No ADR is contradicted. Spec 012's clarification against usage rings is
reversed by this spec's own text, not by an ADR. ADR-worthy: R4 (limits from
the status line instead of the OAuth endpoint) is a real trade-off but easy
to reverse behind the usage-record contract, so it stays in research.

**Post-design re-check**: unchanged, all Pass. Two assumptions are marked
"Verify first" in research (R4 field names, R8 plugin loading); each has a
fallback that keeps the contracts intact.

## Project Structure

### Documentation (this feature)

```text
specs/013-mango-islands-shell/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── popup-ipc.md
│   └── usage-record.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
modules/mango/
├── default.nix          # palette, waybar islands + custom modules, service env
├── scripts.nix          # rail module scripts (clock, controls, usage, phone)
└── quickshell/
    ├── shell.qml        # ShellRoot, state, IPC, waybar signals
    ├── Config.qml       # singleton: palette + store paths (replaceVars)
    ├── RailPopup.qml    # shared popup window
    ├── Widgets.qml…     # CapsuleSlider, ToggleRow, Segmented, RoundButton, ListRow
    ├── Controls.qml     # quick controls + Wi-Fi/Bluetooth/sound pages
    ├── Calendar.qml
    ├── Usage.qml        # usage popup
    └── Phone.qml        # phone card + detail page

workstation/agents/
├── usage.nix            # agents.usage.enable, collector unit + timer
├── statusline.nix       # passes the tap switch to the package
└── packages/
    ├── context-statusline.nix   # + write limits.json
    └── agent-usage-tokens.py    # collector

tests/
├── context-statusline.nix   # + tap cases
└── agent-usage.nix          # collector on fixture transcripts

GLOSSARY.md              # Rail (top edge, capsules), Island, Usage pill, Phone card
```

**Structure Decision**: Stay inside the two existing modules. The QML is
split per popup because one file would pass 1,500 lines (research R11). The
shared widgets may be one file each, as QML requires; `Widgets.qml…` above
stands for that set.

## Build Order

Each step ends with the build gate from quickstart.

1. **Palette and islands** (Story 1, no behaviour change): `palette`
   attrset, waybar CSS capsules, frame to `111111`, all literals removed.
2. **QML split and restyle** (Story 1): split `shell.qml`, add `Config.qml`,
   redraw quick controls, calendar and detail pages with D's widgets; scroll
   when the popup is taller than the screen.
3. **Open state** (Story 1): `shell openTarget` IPC, waybar signal,
   `custom/clock` and `custom/controls`.
4. **Usage writers** (Story 2): verify R4, then the status-line tap,
   collector, timer, both tests.
5. **Usage pill and popup** (Story 2): `custom/claude-usage`, `usage`
   target, `Usage.qml`.
6. **Phone card** (Story 3): verify R8, service import path, `Phone.qml`
   card and four actions, `custom/phone`, indicator off.
7. **Phone detail page** (Story 4): notifications, other devices, pairing.
8. **Glossary** and spec 012 contract pointer.

Steps 4–5 and 6–7 are independent of each other and can swap.

## Complexity Tracking

No constitution violations to justify.
