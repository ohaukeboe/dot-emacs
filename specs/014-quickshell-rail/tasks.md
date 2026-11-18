# Tasks: Quickshell Rail

**Input**: Design documents from `specs/014-quickshell-rail/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/rail-ipc.md](contracts/rail-ipc.md), [quickstart.md](quickstart.md)

**Look reference**: the current waybar rail. Its sizes, margins, radii,
colours and hover tints are the `programs.waybar` block in
`modules/mango/default.nix` (`settings.main` and `style`). Read that block
before deleting it (T020). Every number below comes from it.

**Tests**: no new test tasks; the spec asks for none. Verification is the
build gate (Nix evaluation, `qmllint` via `qmlCheck`), `just qs-check`
(loads the config against the running session), and the manual checks in
[quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, no dependency on an
  unfinished task. Most rail tasks edit `modules/mango/quickshell/Bar.qml`,
  so few are [P].
- **[Story]**: US1 same rail in one program, US2 workspaces island, US3
  status island and popups (all P1 in spec.md).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new QML file
  before `nix build`. `qmlCheck` generates the `qmldir` from the file list,
  so a new singleton only needs `pragma Singleton` on its first line.
- Colours come only from `Config` (`frame`, `island`, `raised`, `fg`, `dim`,
  `onAccent`). Translucent tints are `Qt.alpha(Config.fg, a)`. No colour
  literals.
- Executables reach QML only as `Config.<name>` store paths, filled by
  `replaceVars` in `modules/mango/default.nix`. Never use a bare command
  name.
- Reuse what exists: `HoverArea.qml` for hover tints, `Glyph.qml` for
  Nerd Font icons, `Rail.run()` for detached commands.
- After each phase, run the build gate:
  1. `nix fmt` (revert any unrelated churn).
  2. `nix flake check`.
  3. `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`.
  4. `just qs-check`.
- Deploying and logging in are **(user)** steps on `laptop`. Do not deploy
  until Phase 5 is done: before that, waybar and the new bar would both
  reserve the top edge.
- Never commit without an explicit instruction; stage and report.

---

## Phase 1: Setup

- [X] T001 Create the beads epic `Quickshell rail (specs/014)` linking
  `specs/014-quickshell-rail/`, and file one child ticket per phase
  (`dot-emacs-chy.1`–`.6`), keeping the `T0NN` ranges in titles, as for
  spec 011.
- [X] T002 Verify research R2 on the running session. Run
  `mmsg dispatch viewcrossmon,1,eDP-1` with the pinned binary
  (`nix eval --raw '.#nixosConfigurations.laptop.config.programs.mango.package'`
  then `/bin/mmsg`). Check with `mmsg get all-tags` that tag 1 became active
  on `eDP-1`, then switch back. If the argument order is wrong, try
  `viewcrossmon,eDP-1,1`. If neither works, use `focusmon,eDP-1` followed by
  `view,1,0`. Record the working form under R2 in
  `specs/014-quickshell-rail/research.md` and in the tag-click row of
  `specs/014-quickshell-rail/contracts/rail-ipc.md`.

---

## Phase 2: Foundational (blocks US1–US3)

- [X] T003 [P] Add the rail geometry to
  `modules/mango/quickshell/Config.qml`:
  - `railTop: 8`, `railHeight: 36`, `islandRadius: 18`, `pillRadius: 14`;
  - `railEdge` computed as `railTop + railHeight + 8`, replacing the
    literal, with a comment that the values are waybar's old `height` and
    `margin-*`.
- [X] T004 [P] Add waybar's `format-icons` to
  `modules/mango/quickshell/Icons.qml`, copying the glyphs exactly from the
  `programs.waybar.settings.main` block in `modules/mango/default.nix`:
  - Wi-Fi strength `󰤟 󰤢 󰤥 󰤨`, ethernet `󰈀`, disconnected `󰤮`;
  - volume `󰕿 󰖀 󰕾`, muted `󰝟`;
  - battery `󰂎 󰁻 󰁾 󰂀 󰁹`, charging `󰂄`, plugged `󰚥`;
  - tray chevron `󰅁`, phone `󰄜`.

  Add a helper `level(list, fraction)` that picks from any of these lists
  by even steps, as waybar does.
- [X] T005 Change `modules/mango/quickshell/Rail.qml` per research R4/R5/R6:
  - `toggle(target, screenName, rect)`: when `screenName` is given, set
    `openOutput` and `openRect` directly and skip `cursorQuery`. Without it
    (IPC), keep the `cursorQuery` path and set `openRect` to null.
  - Clear `openRect` when `openTarget` becomes `""`.
  - Delete the `railState` `FileView`, its `Component.onCompleted`, and the
    `run([Config.pkill, "-RTMIN+8", "waybar"])` line.
  - Move the `limits.json` `FileView`, `limits`, `stale`, `now` and
    `parse()` from `Usage.qml` into `Rail`.
  - Add `sessionPercent`: `limits.session.used_percentage` rounded, or 0
    when `limits.session` is null or `resets_at` is before now, the same
    rule as the old jq filter in `railModule`.
  - Update the header comment: the rail is drawn here, not in waybar.
- [X] T006 Point `modules/mango/quickshell/Usage.qml` at `Rail.limits`,
  `Rail.stale` and `Rail.now`, removing its own `limits.json` `FileView`.
  Keep its tokens `FileView` and refresh control as they are. If refresh
  reloads limits, call `Rail`'s `FileView.reload()` through a `Rail` function.
- [X] T007 Change `modules/mango/quickshell/RailPopup.qml` per research R4:
  - When `Rail.openRect` is set, map it into this window's coordinates.
  - Centred popups: `x` is the rect's centre minus half the card width.
    `endAligned` popups: `x` is the rect's right edge minus the card width.
    Clamp both to `Config.edgeGap` from the screen edges.
  - Keep `y: Config.railEdge` and today's `x` when `openRect` is null.
  - Keep `transformOrigin` matching the alignment.
- [X] T008 Create `modules/mango/quickshell/Bar.qml` and add it to
  `modules/mango/quickshell/shell.qml` as
  `Variants { model: Quickshell.screens; Bar {} }`. Per research R3:
  - a `PanelWindow` with `required property var modelData` and
    `screen: modelData`;
  - anchored `top`, `left` and `right`, with `margins` top
    `Config.railTop`, left and right `Config.edgeGap`;
  - `implicitHeight: Config.railHeight`, `exclusiveZone` of
    `Config.railHeight + Config.railTop`, transparent;
  - `WlrLayershell.layer: WlrLayer.Top`, namespace `mango-rail`.

  Inside, add three `Rectangle` islands in `Config.island` with radius
  `Config.islandRadius` and full rail height:
  - left island: left-anchored, horizontal padding 8;
  - centre island: `anchors.horizontalCenter: parent.horizontalCenter`;
  - right island: right-anchored, padding 6 on the left and 4 on the right.

  Each island is sized by a `Row` inside it. Add a helper
  `function openAt(target, item)` that calls
  `Rail.toggle(target, modelData.name, item.mapToItem(null, 0, 0,
  item.width, item.height))`, offset by the window's position on the
  screen.

**Checkpoint**: build gate passes; `just qs-check` shows an empty
three-island bar.

---

## Phase 3: User Story 2 - Workspaces island (Priority: P1)

**Goal**: The left island shows occupied tags as dots and the active tag as
a numbered pill, follows changes live, and switches tags on click.

**Independent Test**: quickstart checks 3 to 6, via `just qs-check` or after
Phase 5.

- [X] T009 [P] [US2] Create the singleton
  `modules/mango/quickshell/Tags.qml` per data-model "Tag state" and
  research R1:
  - A `Process` runs `[Config.mmsg, "watch", "all-tags"]` with
    `running: true`. Its stdout is a `SplitParser` that parses each line.
  - `monitors` maps the monitor name to `Tag[]`, replaced whole per line.
    Each tag is `{index, active: is_active, urgent: is_urgent,
    clients: client_count}`.
  - "a line that fails `JSON.parse` or has no `all_tags` array is ignored,
    so the last good snapshot is kept".
  - `connected` is true from the first line until the process exits. On
    exit, a 1 s `Timer` restarts the process.
  - Expose `function visible(monitor)`, returning the tags with
    `clients > 0` or `active`, in `index` order.
  - Expose `function view(monitor, index)`, running the dispatch form
    recorded in T002 through `Rail.run`.
- [X] T010 [US2] Fill the left island in
  `modules/mango/quickshell/Bar.qml` with a `Repeater` over
  `Tags.visible(modelData.name)`. Sizes are from the old waybar CSS:
  - Inactive tag: an 8×8 circle in `Config.dim`, 4 px side margins,
    vertically centred.
  - Active tag: a 26×18 pill in `Config.fg`, with its index in bold sans
    11 px in `Config.onAccent`.
  - Urgent tag: an inset 2 px ring in `Config.fg`, drawn with
    `border.width` on an inner rectangle.
  - Width and colour animate over 120 ms ease-out.
  - Click calls `Tags.view(modelData.name, index)`.
  - Hover uses `HoverArea` at alpha 0.25 of `fg`; the active pill uses
    alpha 0.22 of `onAccent`.
  - An empty `visible()` (no snapshot yet) leaves the island at its padding
    width.

**Checkpoint**: tags follow `SUPER+n` live; clicking a dot switches tag.

---

## Phase 4: User Story 3 - Status island and popups (Priority: P1)

**Goal**: Clock, tray, usage ring and controls capsule look and act as in
waybar, and every popup opens under its capsule with an open state.

**Independent Test**: quickstart checks 7 to 12.

- [X] T011 [P] [US3] Create `modules/mango/quickshell/RailTooltip.qml`
  (research R8):
  - a `PopupWindow` with `required property Item target` and
    `property string text`;
  - `anchor.item: target`, edges below, centred horizontally, 6 px gap;
  - shown after the target's `HoverArea` has hovered for 500 ms, hidden on
    exit;
  - `Config.island` card, radius `Config.pillRadius`, 8×12 padding, sans
    12 px in `Config.fg`;
  - takes no input.
- [X] T012 [P] [US3] Create `modules/mango/quickshell/Tray.qml` per
  research R7:
  - A `Row` that holds a chevron `Glyph` (`Icons` chevron, `Config.dim`,
    28 px wide, round `HoverArea`) and a `Row` of `SystemTray.items`. The
    item row is visible only while `revealed`; the chevron toggles
    `revealed`.
  - The whole tray is `visible: SystemTray.items.values.length > 0`.
  - Each item is a 28 px cell with a 16 px `IconImage`. Its source is
    `Quickshell.iconPath(name + "-symbolic", true)` when `item.icon` starts
    with `image://icon/`, falling back to `item.icon`.
  - Left click: `item.onlyMenu ? menu.open() : item.activate()`. Right
    click: `menu.open()`. `menu` is a `QsMenuAnchor` with `menu: item.menu`
    and `anchor.item` set to the cell.
  - Hover: `HoverArea` at radius 14.
  - Tooltip: `RailTooltip` with `item.tooltipTitle || item.title`.
- [X] T013 [P] [US3] Create `modules/mango/quickshell/PhoneIcon.qml`
  (research R9):
  - Reuse the `DevicesModel` filter from `Phone.qml` (paired devices) and
    show the `Icons` phone glyph only while a paired device is reachable.
  - In `modules/mango/default.nix` `quickshellDir`, extend the
    `optionalString (!kdeconnect)` line to also remove `PhoneIcon.qml`.
  - In `modules/mango/quickshell/Phone.qml`, delete the
    `onReachableCountChanged` line that signals waybar.
- [X] T014 [US3] Add the clock to the centre island in
  `modules/mango/quickshell/Bar.qml` (research R10):
  - A `SystemClock` with `precision: SystemClock.Minutes` and a `Text`
    with `textFormat: Text.StyledText`, showing
    `<font color=dim>ddd d MMM</font>  <b>HH:mm</b>` (two spaces) in sans
    13 px, `Config.fg`, with 16 px side padding.
  - The island's fill is `Config.raised` while
    `Rail.openTarget === "calendar" && Rail.showsOn(modelData.name)`.
  - Click calls `openAt("calendar", island)`.
  - Hover: `HoverArea` at alpha 0.1 of `fg`.
- [X] T015 [US3] Add the usage pill to the right island in
  `modules/mango/quickshell/Bar.qml` (research R6):
  - A 28×28 cell with radius 14, `visible: Rail.limits !== null`.
  - Inside it, a 16×16 `Shape` (`import QtQuick.Shapes`) with two
    `ShapePath`s, each a `PathAngleArc` centred at 8,8 with radius 6,
    `strokeWidth` 2.5, `capStyle: ShapePath.RoundCap`, no fill:
    - the track: full 360°, ring colour at 0.25 opacity;
    - the arc: from −90°, sweeping `3.6 * Rail.sessionPercent`, hidden at 0.
  - The ring colour is `Config.fg`, or `Config.onAccent` while the usage
    popup is open, when the cell fills with `Config.fg`.
  - Click calls `openAt("usage", cell)`.
  - Tooltip: `"Session N% · weekly M%"`, where weekly uses the same
    reset-time rule.
  - Hover: alpha 0.1 of `fg`, or 0.22 of `onAccent` while open.
- [X] T016 [US3] Add the controls capsule to the right island in
  `modules/mango/quickshell/Bar.qml` (research R8):
  - One `Config.raised` capsule with radius 14 and 4 px vertical margins,
    holding a `Row` of 28 px icon cells:
    `Loader { active: Config.kdeconnect; source: "PhoneIcon.qml" }`,
    network, sound and battery.
  - Network: `Icons.wifi(strength)` while Wi-Fi is connected, ethernet
    while wired, disconnected glyph otherwise, in `Config.dim`. Read the
    devices from `Rail.netDevices`.
  - Sound: `Icons.volume(Pipewire.defaultAudioSink.audio.volume)`, or the
    muted glyph in `Config.dim`.
  - Battery: visible only when `UPower.displayDevice.isLaptopBattery`;
    charging and plugged glyphs by state. Below 15 % while discharging,
    the cell fills with `Config.fg` and the glyph is `Config.onAccent`.
  - Tooltips, as in waybar:
    - network: `"<essid> (<strength>%)"`, the interface name, or
      `"offline"`;
    - sound: `"<sink description> <volume>%"`;
    - battery: `"<percent>% <time to empty/full>"`.
  - One `HoverArea` over the whole capsule at alpha 0.1 of `fg`. Any click
    calls `openAt("controls", capsule)`.
- [X] T017 [US3] Assemble the right island in
  `modules/mango/quickshell/Bar.qml`:
  - Order: `Tray {}`, usage pill, controls capsule, centred vertically.
  - Pass each popup target's open state as in FR-015.
  - The calendar opens centred under the clock island. Controls and usage
    open end-aligned under their own capsule.

**Checkpoint**: `just qs-check` passes; every right-island item and the
clock open their popup under their capsule.

---

## Phase 5: User Story 1 - Same rail, one program (Priority: P1)

**Goal**: waybar is gone; the Quickshell rail is the only bar, on every
monitor, pixel-equal to before.

**Independent Test**: quickstart checks 1, 2, 13, 14, 15 and 16.

- [X] T018 [US1] Delete `railModule` from `modules/mango/scripts.nix`,
  including its comment block.
- [X] T019 [US1] In `modules/mango/quickshell/Config.qml`, delete the
  `pkill` property. In `modules/mango/default.nix`, delete `pkill = …` from
  the `replaceVars` set.
- [X] T020 [US1] In `modules/mango/default.nix`, delete:
  - the whole `programs.waybar` block and its comment;
  - the `usageRing` and `usageRingCss` bindings and their comment;
  - the `centered` and `popupToggle` bindings;
  - `railModule` from the `inherit (import ./scripts.nix …)` list.

  Then update the comment above `quickshellDir` and `programs.quickshell`:
  Quickshell draws the rail as well as its popups.
- [X] T021 [US1] Run the build gate. In
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`,
  confirm with `nix path-info -r` on the result that no `waybar` store path
  is left in the system closure, unless another module pulls it in.
- [X] T022 [US1] **(user)** Take the quickstart "Before the change"
  screenshot on the old generation. Then run
  `sudo nixos-rebuild switch --flake .#laptop`, log out and back in, and run
  quickstart checks 1 to 16.

**Checkpoint**: one bar per monitor, no waybar process, quickstart passes.

---

## Phase 6: Polish & Cross-Cutting

- [X] T023 [P] Rewrite the **Rail** entry in `GLOSSARY.md`: Quickshell
  draws it as three capsules along the top edge. Update the
  **Quick controls** entry's sentence on what Quickshell draws (now the
  rail too).
- [X] T024 [P] Add a line under R2 in
  `specs/012-mango-rail-bar/research.md`: "Superseded by
  `specs/014-quickshell-rail` (research R1, R3)". Add a header line to
  `specs/013-mango-islands-shell/contracts/popup-ipc.md`: "Superseded by
  `specs/014-quickshell-rail/contracts/rail-ipc.md`".
- [X] T025 [P] Add a dated "Update (2026-11-14)" note under the
  recommendation in `docs/native-bar-popups-research.md` and under the Bar
  row's recommendation in `docs/mangowm-components-research.md`: the rail
  moved to Quickshell in `specs/014-quickshell-rail`.
- [X] T026 Run `grep -rn -i 'waybar\|mango-popup\|RTMIN' modules/ workstation/`.
  Only historical comments may mention waybar, and none may configure it.
  Then run the build gate once more and stage the changes for review.
- [X] T027 Tick the tasks in this file `[X]` and close their beads tickets
  as they finish (T001 epic last).

---

## Dependencies & Execution Order

- **Phase 1** (T001, T002) first. T002 decides the dispatch form T009 uses.
- **Phase 2** (T003–T008) blocks every story:
  - T003 and T004 have no dependencies.
  - T005 comes before T006 and T007.
  - T008 needs T003 and T005.
- **US2** (Phase 3) needs Phase 2. T009 comes before T010.
- **US3** (Phase 4) needs Phase 2. It does not depend on US2:
  - T011, T012 and T013 can run in parallel.
  - T014 to T017 edit `Bar.qml` in sequence; T015 and T016 use T011.
- **US1** (Phase 5) needs US2 and US3. Removing waybar before the new rail is
  complete would leave the session without a full rail. T018 to T020 come
  before T021, and T021 before T022.
- **Polish** (Phase 6): T023–T025 can start any time after Phase 2. T026
  comes after Phase 5.

## Parallel Examples

```text
Phase 2:  T003 Config.qml  ∥  T004 Icons.qml
US2/US3:  T009 Tags.qml  ∥  T011 RailTooltip.qml  ∥  T012 Tray.qml  ∥  T013 PhoneIcon.qml
Polish:   T023 GLOSSARY.md  ∥  T024 spec notes  ∥  T025 docs notes
```

## Implementation Strategy

US1 is the deliverable, but it is the removal step, so the MVP order is:

1. Phase 2 (a bar shell).
2. US2 (workspaces, the riskiest part, since it depends on the R1 stream and
   the R2 dispatch).
3. US3 (status and popups).
4. US1 (remove waybar, deploy).

Check each phase with `just qs-check` in the running session; the first
real deploy is T022. If R7's tray menus fail on Mango, finish everything
else, deploy, and track the menu fallback as a follow-up ticket rather than
blocking the switch.
