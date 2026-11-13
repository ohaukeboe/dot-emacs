# Tasks: Mango Rail Bar

**Input**: Design documents from `specs/012-mango-rail-bar/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/popup-ipc.md](contracts/popup-ipc.md), [quickstart.md](quickstart.md)

**Tests**: no test suite was requested. Verification is Nix evaluation and
build (Constitution I, III), the `qmllint` derivation, and the manual checks
in [quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, no dependency on an
  unfinished task. Most tasks edit `modules/mango/default.nix`, so few are
  [P].
- **[Story]**: the user story the task belongs to (US1–US3).

**Implementation note (2026-11-13)**: the popups pick their monitor from
`mmsg get cursorpos`, so the IPC `toggle` takes no argument and no waybar
`on-click` passes `$WAYBAR_OUTPUT_NAME` (research R5, revised). T007, T009
and T015 were done that way.

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file
  (`modules/mango/quickshell/shell.qml`) before `nix build` or
  `nix flake check`.
- Every package comes from nixpkgs (`pkgs.<name>`); no new flake input or
  nvfetcher entry.
- Everything sits inside `mkIf cfg.enable` in `modules/mango/default.nix`;
  Home Manager config goes under `home-manager.users.${config.user.username}`
  (Constitution V).
- Colours come only from the `bg`, `card`, `accent` bindings at the top of
  `modules/mango/default.nix` (FR-013); the QML gets them as `@bg@`,
  `@card@`, `@accent@` placeholders.
- Executables are referenced by store path (`lib.getExe`, `getExe'`), never
  bare names, in waybar `on-click` strings and in the QML (Constitution I).
- Use Nerd Font glyphs from `Symbols Nerd Font` (already installed by
  `nerd-fonts.symbols-only` in `workstation/home.nix`).
- No waybar module may set `rotate` (SC-004).
- The agent sandbox cannot deploy, log in or dock. Steps marked **(user)**
  are the user's, on `laptop`.

---

## Phase 1: Setup

- [X] T001 Create the beads epic `Mango rail bar (specs/012)` linking
  `specs/012-mango-rail-bar/`, and file one child ticket per phase below,
  keeping the `T0NN` ids in titles.

---

## Phase 2: Foundational (blocks US1–US3)

- [X] T002 In `modules/mango/default.nix` `programs.waybar.settings.main`,
  set `width = 32;` (FR-002: "no wider than 32 logical pixels"), keep
  `position = "left"`, `layer = "top"`, and set the module lists from
  [data-model.md](data-model.md) §Rail: `modules-left = [ "mango/workspaces" ]`,
  `modules-center = [ "clock" ]`, `modules-right = [ "group/tray" "network"
  "wireplumber" "power-profiles-daemon" "battery" "custom/controls" ]`.
  Remove the `ext/workspaces` and `custom/power` module blocks. Leave the
  new modules' bodies to the story phases; stub `custom/controls` with
  `format = "";` so the build still evaluates.
- [X] T003 Rewrite the base waybar CSS in `modules/mango/default.nix` `style`:
  `* { font-family: "Symbols Nerd Font", sans-serif; font-size: 13px;
  min-height: 0; }`, `window#waybar { background: #${bg}; color: #c8c5c7; }`
  with no border, and one padding rule `padding: 6px 0;` for every
  right-side module id (`#network, #wireplumber, #power-profiles-daemon,
  #battery, #custom-controls, #custom-tray-chevron, #tray`). Drop the old
  `#custom-power` selector.
- [X] T004 Build: `git add -A modules/mango`, `nix fmt` (revert unrelated
  churn), `nix flake check`, then
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`.

**Checkpoint**: rail evaluates at 32 px with the new module order.

---

## Phase 3: User Story 1 - Rail that reads as part of the frame (P1) 🎯 MVP

**Goal**: frame-coloured rail, dot-and-pill workspaces, stacked clock that
opens a calendar.

**Independent Test**: [quickstart.md](quickstart.md) steps 1, 2 and 6.

- [X] T005 [US1] Configure `"mango/workspaces"` in
  `modules/mango/default.nix`: `format = "{value}"; hide-empty = true;
  on-click = "activate";` (research R2, R3; FR-004 "Empty workspaces other
  than the active one MUST NOT show"; FR-005).
- [X] T006 [US1] Add workspace CSS in `modules/mango/default.nix` `style`
  per [data-model.md](data-model.md) §Workspace button: `#workspaces`
  transparent with `margin: 8px 0;`; `#workspaces button` a round
  `min-width: 8px; min-height: 8px; margin: 4px 12px; padding: 0;
  border-radius: 99px; background: #888888; border: none; box-shadow:
  none;`; `#workspaces button:not(.active) label { font-size: 0; }`;
  `#workspaces button.active { background: #${accent}; color: #${bg};
  min-height: 24px; margin: 4px 6px; font-size: 12px; }`;
  `#workspaces button.urgent { box-shadow: inset 0 0 0 2px #${accent}; }`.
  Check that two-digit tags (10+) still fit inside 32 px (edge case).
- [X] T007 [US1] Create `modules/mango/quickshell/shell.qml` with a
  `ShellRoot` containing: a shared `QtObject` state (`openTarget: ""`,
  `openOutput: ""`); an `IpcHandler { target: "calendar"; function
  toggle(output: string): void }` per
  [contracts/popup-ipc.md](contracts/popup-ipc.md) ("Opening one target
  closes the other"; empty or unknown `output` falls back to the focused
  output parsed from `@mmsg@ -g -o`, via `Process` + `StdioCollector`); a
  `Variants { model: Quickshell.screens }` of `PanelWindow` shown only when
  `openTarget === "calendar" && modelData.name === openOutput`, anchored on
  all four edges, `color: "transparent"`, `WlrLayershell.layer:
  WlrLayer.Overlay`, `exclusionMode: ExclusionMode.Ignore`,
  `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`, a full-size
  `MouseArea` that closes, `Keys.onEscapePressed` that closes (research R6).
  The visible card sits left-aligned beside the rail (x = 32 + 14),
  vertically centred, `color: "#@card@"`, `radius: 14`, and holds
  `DayOfWeekRow`, `WeekNumberColumn` and `MonthGrid` from QtQuick.Controls
  with previous/next month buttons and today in `#@accent@`
  ([data-model.md](data-model.md) §Calendar). Use the placeholders `@bg@`,
  `@card@`, `@accent@`, `@mmsg@`.
- [X] T008 [US1] In `modules/mango/default.nix` add a `let` binding
  `quickshellConfig = pkgs.replaceVars ./quickshell/shell.qml { bg = bg;
  card = card; accent = accent; mmsg = getExe' mango "mmsg"; brightnessctl =
  getExe pkgs.brightnessctl; powerMenu = getExe powerMenu; };` (all
  placeholders are declared now, so T011 needs no change here; until T011
  uses `@brightnessctl@` and `@powerMenu@`, reference them in a QML comment
  so `replaceVars` does not fail). Wrap it in a directory derivation
  (`pkgs.runCommand "mango-quickshell" { } "mkdir $out; cp ${quickshellConfig}
  $out/shell.qml"`) and set, under Home Manager: `programs.quickshell = {
  enable = true; configs.mango = <that dir>; activeConfig = "mango";
  systemd = { enable = true; target = sessionTarget; }; };`.
- [X] T009 [US1] Configure `clock` in `modules/mango/default.nix`: `format =
  "{:%H\n%M}";` (FR-006, 24-hour, hour over minutes), remove
  `tooltip-format`, `tooltip = false;`, `on-click = "${getExe'
  config.programs.quickshell.package "qs"} -c mango ipc call calendar toggle
  \"$WAYBAR_OUTPUT_NAME\"";` — reference the HM user's
  `programs.quickshell.package` (or `pkgs.quickshell` directly) so the path
  is a store path.
- [X] T010 [US1] Add `qmlCheck` beside `portalCheck` in
  `modules/mango/default.nix`: a `pkgs.runCommand "mango-qml-check"` that
  runs `${pkgs.qt6.qtdeclarative}/bin/qmllint -I
  ${pkgs.quickshell}/lib/qt-6/qml ${quickshellConfig}`, failing with a
  message naming `modules/mango/quickshell/shell.qml`; append it to
  `system.extraDependencies`. If Quickshell types report as unresolved,
  disable only the unresolved-type category (`--unresolved-type disable`
  or the qmllint version's equivalent) and note it in a comment (research
  R9). Then rebuild as in T004.
- [X] T011 [US1] **(user)** Deploy (`sudo nixos-rebuild switch --flake
  .#laptop`), run [quickstart.md](quickstart.md) steps 1, 2 and 6. For step
  6, if the calendar opens on the wrong display, check whether waybar sets
  `WAYBAR_OUTPUT_NAME` for `on-click` and report back.

**Checkpoint**: US1 complete; the rail matches the reference's top and
middle groups.

---

## Phase 4: User Story 2 - Status as icons, details on demand (P2)

**Goal**: icon-only status, battery warning, quick-controls popup with
power entry.

**Independent Test**: [quickstart.md](quickstart.md) steps 3, 4 and 5.

- [X] T012 [US2] Configure the status modules in `modules/mango/default.nix`
  (research R7; FR-008 "icons only; their text detail MUST be available on
  hover"): `network` with `format-wifi = "{icon}"`, `format-icons` of
  signal-strength glyphs, `format-ethernet`, `format-disconnected` glyphs,
  `tooltip-format-wifi = "{essid} ({signalStrength}%)"`,
  `tooltip-format-ethernet = "{ifname}"`, `on-click` = `getExe'
  pkgs.networkmanagerapplet "nm-connection-editor"`; `wireplumber` with
  `format = "{icon}"`, `format-muted` glyph, `format-icons` low/mid/high,
  `tooltip-format = "{node_name} {volume}%"`, `on-click = getExe
  pkgs.pwvucontrol`; `battery` with `states = { warning = 15; }` (FR-010:
  "at or below 15 % while discharging"), `format = "{icon}"`,
  `format-charging` glyph, `format-icons` of five level glyphs,
  `tooltip-format = "{capacity}% {timeTo}"`; `power-profiles-daemon` with
  `format = "{icon}"` and `format-icons` for `performance`, `balanced`,
  `power-saver`. No `rotate` anywhere.
- [X] T013 [US2] Add CSS in `modules/mango/default.nix` `style`:
  `#battery.warning.discharging { color: #${accent}; }` and
  `#wireplumber.muted, #network.disconnected { color: #888888; }`.
- [X] T014 [US2] In `modules/mango/quickshell/shell.qml`, add the `controls`
  `IpcHandler` and a second `Variants`/`PanelWindow` popup with the same
  open/close behaviour as T007 (one shared state, so opening one closes the
  other). The card sits beside the rail, bottom-aligned (corner control),
  and contains, per [data-model.md](data-model.md) §Quick controls, each
  hidden under its "Hidden when" condition: volume `Slider` bound to
  `Pipewire.defaultAudioSink.audio.volume` (with `PwObjectTracker` on sink
  and source); brightness `Slider` that reads `@brightnessctl@ -m` on open
  and writes `@brightnessctl@ set N%` on move (hidden if the command finds
  no device); mic mute toggle on `Pipewire.defaultAudioSource.audio.muted`;
  Wi-Fi toggle via `Quickshell.Networking`; Bluetooth toggle on
  `Bluetooth.defaultAdapter.enabled`; a three-way power-profile switch on
  `PowerProfiles.profile`; battery percentage and charging state from
  `UPower.displayDevice`; a Power button that runs `@powerMenu@` with
  `Quickshell.execDetached` and closes the popup. Controls apply without
  closing the popup (FR-012). Remove the T008 placeholder comment.
- [X] T015 [US2] Configure `custom/controls` in `modules/mango/default.nix`:
  `format` = a gear glyph, `tooltip = false;`, `on-click` = store-path `qs
  -c mango ipc call controls toggle "$WAYBAR_OUTPUT_NAME"` (contract
  §Callers). Add `pkgs.brightnessctl` only via the `replaceVars` path from
  T008 (no `home.packages` entry needed).
- [X] T016 [US2] Rebuild as in T004 (the T010 `qmllint` check covers the new
  QML).
- [X] T017 [US2] **(user)** Deploy and run [quickstart.md](quickstart.md)
  steps 3, 4 and 5.

**Checkpoint**: every control the old bar offered is reachable in ≤ 2 clicks
(FR-009, SC-003).

---

## Phase 5: User Story 3 - Tray tucked away (P3)

**Goal**: tray behind one chevron.

**Independent Test**: [quickstart.md](quickstart.md) step 7.

- [X] T018 [US3] In `modules/mango/default.nix`, add `"group/tray" = {
  orientation = "inherit"; drawer = { click-to-reveal = true;
  transition-left-to-right = false; empty-if-drawer-empty = true; };
  modules = [ "custom/tray-chevron" "tray" ]; };`,
  `"custom/tray-chevron" = { format = "<chevron-up glyph>"; tooltip =
  false; };` and keep `tray = { spacing = 8; icon-size = 16; };` (research
  R7; FR-011).
- [X] T019 [US3] Add CSS in `modules/mango/default.nix` `style`:
  `#group-tray.empty { opacity: 0; }` (hide the chevron with no tray items,
  edge case) and `.drawer-child { padding: 4px 0; }`.
- [X] T020 [US3] Rebuild as in T004, then **(user)** deploy and run
  [quickstart.md](quickstart.md) step 7.

---

## Phase 6: Polish & Cross-Cutting

- [X] T021 [P] Add **Rail** and **Quick controls** to `GLOSSARY.md` under
  "Desktop / sessions" (research R10): Rail = the Mango session's waybar,
  a 32 px left strip in the frame colour; Quick controls = the Quickshell
  popup opened from the rail's gear, with `_Avoid_: control centre`.
- [X] T022 [P] Update `docs/mangowm-components-research.md` §4 Bar: note
  that waybar 0.16 is now pinned and `mango/workspaces` is in use, and that
  Quickshell draws only the two popups (not a shell, §5 unchanged).
- [X] T023 Final gate: `nix fmt` (revert unrelated churn), `nix flake
  check`, laptop toplevel build, and confirm `modules.mango.enable = false`
  machines evaluate with no waybar or quickshell config (FR-014,
  Constitution V): `nix eval
  '.#nixosConfigurations.work-laptop.config.home-manager.users.oskar.programs.quickshell.enable'`
  prints `false`.
- [X] T024 **(user)** Run [quickstart.md](quickstart.md) step 8 (COSMIC
  unaffected) and close the beads epic.

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 → US2 → US3 → Polish.
- US2 depends on US1 for the QML file, `quickshellConfig` and the
  `qmllint` check (T007, T008, T010). US3 depends only on Phase 2.
- Within US1: T005–T006 (waybar) and T007 (QML) are independent; T008
  needs T007; T009 needs T008; T010 needs T008.

## Parallel Opportunities

- T007 (`shell.qml`) can run alongside T005–T006 (`default.nix`).
- T014 (`shell.qml`) can run alongside T012–T013 (`default.nix`).
- US3 (T018–T019) can run alongside US2's QML task T014.
- T021 and T022 touch separate docs and run in parallel.

## Implementation Strategy

1. **MVP**: Phases 1–3. The rail already looks like the reference; old
   status modules keep working until US2 replaces them (T002 lists them).
2. **Increment 2**: US2: icons and quick controls; the old `custom/power`
   module is already gone after T002, so deploy US1 and US2 together if the
   power menu must stay one click away from the rail (`Super+Shift+Escape`
   still works).
3. **Increment 3**: US3 tray drawer, then polish.

---

## Phase 7: Convergence

- [X] T025 [US2] In `modules/mango/quickshell/shell.qml`, turn the controls
  card into a two-level view: the Wi-Fi, Bluetooth and sound controls get an
  arrow that swaps the card to that detail page, each page has a back
  control to the tiles, and closing the popup resets it to the tiles
  per FR-015 (missing)
- [X] T026 [US2] Add the Wi-Fi detail page: scan on open, list networks with
  signal and security from `Quickshell.Networking`, connect, ask for the
  password inline and use `connectWithPsk`, show the `NoSecrets` failure,
  and forget a saved network (see `docs/native-bar-popups-research.md`)
  per FR-015, US2/AC5 (missing)
- [X] T027 [US2] Add the Bluetooth detail page from `Quickshell.Bluetooth`:
  paired devices with connect/disconnect and battery where reported, a scan
  toggle on `Bluetooth.defaultAdapter`, and pair for new devices; PIN
  prompts stay with the running blueman-applet per FR-015, US2/AC6 (missing)
- [X] T028 [US2] Add the sound detail page: choose the default output and
  input from the `Pipewire.nodes` sinks and sources (non-stream nodes),
  tracked with `PwObjectTracker` per FR-015 (missing)
- [X] T029 [US2] On the sound detail page, list each app stream node
  (`isStream`) that is playing or recording, with its own volume `Slider`
  and mute, tracked with `PwObjectTracker` per FR-016, US2/AC7 (missing)
- [X] T030 [P] Add the detail pages to `data-model.md` §Quick controls and
  a quickstart step for US2/AC5–AC7 to `quickstart.md` per FR-015, FR-016
  (missing)
- [X] T031 Rebuild as in T004; the T010 `qmllint` check must pass on the
  new QML per FR-015, FR-016 (missing)
- [X] T032 **(user)** Deploy and run the new quickstart step per US2/AC5,
  US2/AC6, US2/AC7 (missing)
