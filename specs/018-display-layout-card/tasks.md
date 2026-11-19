# Tasks: Display Layout Card

**Input**: design documents in `specs/018-display-layout-card/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/displays.md](contracts/displays.md),
[quickstart.md](quickstart.md)

**Tests**: the spec asks for none. The plan adds one build-time test for
the geometry module (research R4, constitution principle I); its tasks
are T003 and the test cases named in T008 and T017. Everything else is
checked by `qmlCheck`, `just qs-check` and the quickstart by hand.

**Design reference**: `mocks/display-mocks.html`, section "Mock A". All
QML uses the tokens and components of
`modules/mango/quickshell/README.md`; no literal colour, size or radius.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no unfinished dependency)
- **[Story]**: the user story the task belongs to (US1 to US4)

---

## Phase 1: Setup

- [X] T001 Build plumbing. In `modules/mango/quickshell/Config.qml` add
  `readonly property string wlrRandr: "@wlrRandr@"`, `kanshictl:
  "@kanshictl@"` and `displaySetup: "@displaySetup@"` with a one-line
  comment ("The displays card (Displays.qml)"). In
  `modules/mango/quickshell.nix` fill them in the `replaceVars` set:
  `getExe pkgs.wlr-randr`, `getExe' pkgs.kanshi "kanshictl"`,
  `getExe displaySetup` (add `displaySetup` to the `inherit` from
  `./common.nix` if it is not in scope). In `quickshellDir` also copy
  `${./quickshell}/displayLayout.mjs` (not the `.test.mjs`)

---

## Phase 2: Foundational (blocks every story)

**Purpose**: the layout module, its test, the state singleton that reads
the displays, and an empty card that opens and closes.

- [X] T002 Create `modules/mango/quickshell/displayLayout.mjs`, an
  ECMAScript module with no QML types and a header comment naming this
  spec. Export:
  `fromRandr(json)` → list of displays with the fields of
  [data-model.md](data-model.md) (`name`, `make`, `model`, `serial`,
  `modes`, `enabled`, `mode` index of the `current` mode, `x`, `y`,
  `scale`, `transform`, `adaptiveSync`; a display that is off gets its
  `preferred` mode, scale 1, `normal`, x and y 0);
  `label(d)` → `model`, else `name`;
  `logicalSize(d)` → `{ w, h }` as "`floor(width / scale)` by
  `floor(height / scale)`, swapped for a 90 or 270 transform" (also
  `flipped-90`, `flipped-270`);
  `resolutions(d)` → distinct width x height pairs, largest first;
  `rates(d, w, h)` → mode indexes of that resolution, highest refresh
  first;
  `normalise(layout)` → copy shifted so "the smallest `x` and the
  smallest `y` of the enabled displays are 0";
  `valid(layout)` → true only when rules 1 to 4 of data-model.md
  "Layout" hold (one enabled; no overlap; all enabled connected through
  shared edge length > 0; minimum at 0,0);
  `same(a, b)` → deep equality on the state fields;
  `applyArgs(layout, applied)` → the argument list of
  [contracts/displays.md](contracts/displays.md) "Applying": one
  `--output` group per display in order, `--off` for a disabled one,
  `--mode <w>x<h>@<refresh>Hz` with the refresh as read,
  `--adaptive-sync` only where it differs from `applied`
- [X] T003 Create `modules/mango/quickshell/displayLayout.test.mjs`
  (imports `./displayLayout.mjs`, uses `node:assert/strict`, exits
  non-zero on failure) with cases for T002: `fromRandr` on the laptop's
  real JSON (one `eDP-1`, 1920x1200@120.002998) and on a two-display
  sample with one display off; `logicalSize` at scale 1, 1.25, 1.5 and
  with transform `90`; `normalise` with negative positions; `valid`
  false for overlap, for a gap, for none enabled; `applyArgs` exact
  output for an on and an off display, with and without an adaptive sync
  change. In `modules/mango/quickshell.nix` add
  `displayLayoutTest = pkgs.runCommand "mango-display-layout-test"
  { nativeBuildInputs = [ pkgs.nodejs ]; }` that copies both files to the
  build dir, runs `node displayLayout.test.mjs`, and prints
  "modules/mango/quickshell: displayLayout test failed" on failure; add it
  to `system.extraDependencies` beside `qmlCheck`. `git add` both files
  before building
- [X] T004 Create `modules/mango/quickshell/Displays.qml`
  (`pragma Singleton`, header comment with the IPC call and this spec),
  importing `"displayLayout.mjs" as Layout`. Properties: `applied`,
  `pending`, `previous` (lists), `selected` (display name), `state`
  (`"closed"`, `"idle"`, `"applying"`, `"confirming"`), `status`
  (string), `setup` (string), `secondsLeft` (int), readonly `open:
  Rail.openTarget === "displays"`, readonly `dirty: !Layout.same(pending,
  applied)`. A `Process` running `[Config.wlrRandr, "--json"]` with a
  `StdioCollector`; on finish parse with `Layout.fromRandr` inside
  try/catch (on failure keep the last state and set status "Could not
  read the displays"). `read()` starts it. On `open` becoming true:
  `state = "idle"`, read, then `pending = applied` and select the display
  named `Rail.openOutput`, else the first enabled one. On `open` becoming
  false: `state = "closed"`, drop pending. While open, read again on
  `Quickshell.screens` change and from a 2 s repeating `Timer` that is
  paused while a drag is in progress (`dragging` property set by the
  canvas) and in `applying` (research R2). After each read in `idle`: if
  the set of names changed, `pending = applied`, status "Displays
  changed; pending changes dropped", and reselect when `selected` is
  gone; else if the applied layout changed and `dirty`, `pending =
  applied` with status "The layout changed; pending changes dropped";
  if not dirty, just `pending = applied`
- [X] T005 Create `modules/mango/quickshell/DisplaysCard.qml`: a
  `PanelWindow` with `required property var modelData`, `screen:
  modelData`, all four anchors, transparent, `exclusionMode: Ignore`,
  `WlrLayershell.layer: Overlay`, namespace `"mango-displays"`, keyboard
  focus `Exclusive` while open, `visible: Displays.open &&
  Rail.showsOn(modelData.name)` (copy these lines' form from
  `RailPopup.qml`). A full-window `MouseArea` and `Keys.onEscapePressed`
  both call `Rail.close()`. In the centre a `FloatingCard` 640 wide with
  padding 12 and spacing 12, fading in with `Anim`: a header row
  (`Title` "Displays", `Detail` bound to `Displays.status`, else the
  setup line, right-aligned), an empty layout area 240 high in
  `Config.app` with `Config.islandRadius`, and a footer row with a
  `Hint` "Drag to move · Enter applies · Esc closes". A `MouseArea` on
  the card swallows clicks so they do not close it. In
  `modules/mango/quickshell/shell.qml` add
  `IpcHandler { target: "displays"; function toggle(): void {
  Rail.toggle("displays"); } }`, a `Variants { model: Quickshell.screens;
  DisplaysCard {} }`, and the line
  `qs -c mango ipc call displays toggle` in the header comment. In
  `modules/mango/quickshell/Rail.qml` add `"displays"` to the comment
  over `openTarget`
- [X] T006 Gate for the foundation: `git add` the new files, build
  `.#nixosConfigurations.laptop.config.system.build.toplevel` (runs
  `qmlCheck` and the layout test), run `just qs-check`. If qmllint or
  Quickshell rejects the `.mjs` import, apply the fallback of research
  R4: rename to `displayLayout.js` with `.pragma library` and plain
  functions, and have the test derivation strip the pragma line and
  append the exports with `sed` before running Node. Then use the
  `verify-quickshell` skill to open the card over IPC and confirm it
  shows, takes Esc and a click outside, and closes other popups

**Checkpoint**: an empty card opens on the pointer's display and closes;
the displays are read.

---

## Phase 3: User Story 1 - Arrange the displays by dragging (P1) 🎯 MVP

**Goal**: see the displays to scale, drag one beside another, Apply.

**Independent Test**: quickstart D1 to D5 and D12. (Until US2 is done an
applied layout simply stays.)

- [X] T007 [US1] Create `modules/mango/quickshell/DisplayCanvas.qml`: an
  `Item` that draws `Displays.pending`. Compute one factor so the
  bounding box of all enabled displays (logical sizes from
  `Layout.logicalSize`) fits inside the area with a 28 px margin, centred
  (FR-005, FR-006). One `Rectangle` per enabled display via `Repeater`:
  radius `Config.chipRadius`, a 2 px gap to its neighbours, colour
  `Config.raised2`, or `Config.fg` when `modelData.name ===
  Displays.selected`; inside it the label (`RailText`, DemiBold) and a
  `Detail` line "`<w>×<h> at <x>,<y>`", both `Config.onAccent` when
  selected; text hidden when the rectangle is too small for it.
  `Behavior` with `Anim` on x, y, width and height, off while dragging.
  A click selects (`Displays.selected = name`). Put it in the layout area
  of `DisplaysCard.qml`
- [X] T008 [US1] In `modules/mango/quickshell/displayLayout.mjs` add
  `snap(layout, name, x, y, threshold)` → the position after snapping the
  dragged display's edges and corners to those of every other enabled
  display within `threshold` logical pixels (left to right edge, right to
  left, top to bottom, bottom to top, and the aligned variants: equal
  tops, bottoms, lefts, rights), and `settle(layout, name)` → a layout
  where rules 2 and 3 of data-model.md hold: for the named display list
  every position where one of its edges touches an edge of another
  enabled display with shared length > 0, drop those overlapping any
  display, take the nearest to its current position; repeat for any
  display left without a neighbour; then `normalise` (research R5). A
  single enabled display settles at 0,0. Add cases to
  `modules/mango/quickshell/displayLayout.test.mjs`: dropped on top of
  the other; dropped far away; three displays where moving the middle one
  strands the third; a 1.5-scaled display beside a 1-scaled one; every
  result passes `valid`
- [X] T009 [US1] In `modules/mango/quickshell/DisplayCanvas.qml` add the
  drag (FR-008, FR-009): a `DragHandler` (or `HoverArea` press, move,
  release) on each rectangle that selects it on press, sets
  `Displays.dragging`, converts the pointer delta to logical pixels with
  the canvas factor held fixed for the whole drag, and writes the display's
  position through `Displays.move(name, x, y)`; on release
  `Displays.drop(name)`. In `modules/mango/quickshell/Displays.qml` add
  `move` (`pending` = copy with `Layout.snap(..., 14 / factor)` applied)
  and `drop` (`pending = Layout.settle(pending, name)`, `dragging =
  false`). Always assign a new list so bindings update
- [X] T010 [US1] Apply. In `modules/mango/quickshell/Displays.qml` add an
  apply `Process` and `apply()`: only in `idle` when `dirty` and
  `Layout.valid(pending)`; `previous = applied`; `state = "applying"`;
  command `[Config.wlrRandr].concat(Layout.applyArgs(pending, applied))`.
  On exit 0: read, `state = "idle"`, status "". On any other exit:
  `state = "idle"`, pending kept, status "The change was refused"
  (FR-018). In `modules/mango/quickshell/DisplaysCard.qml` add to the
  footer a `Pill` "Apply" with `on: Displays.dirty`, dimmed and inert
  when not dirty (FR-015), and `Keys.onReturnPressed` /
  `onEnterPressed` calling `Displays.apply()`; all controls inert while
  `applying`
- [X] T011 [US1] In `modules/mango/quickshell/DisplaysCard.qml` handle
  `Tab` and `Shift+Tab` (`Keys.onTabPressed`, `onBacktabPressed`):
  `Displays.selectNext(±1)` over all displays in list order (FR-007); add
  `selectNext` to `modules/mango/quickshell/Displays.qml`

**Checkpoint**: quickstart D1 to D5 and D12 pass with two displays.

---

## Phase 4: User Story 2 - A bad change undoes itself (P1)

**Goal**: after Apply, a ten-second keep question; no answer reverts.

**Independent Test**: quickstart D6, D7, D8, D14, D20.

- [X] T012 [US2] In `modules/mango/quickshell/Displays.qml` implement the
  `confirming` state of data-model.md "Card state": on apply exit 0 go to
  `"confirming"`, `secondsLeft = 10`, start a 1 s repeating `Timer` that
  counts down and calls `revert()` at 0. `keep()` → stop the timer,
  `state = "idle"`. `revert()` → stop the timer, run the apply process
  with `Layout.applyArgs(previous, applied)`, then read and
  `state = "idle"` (or `"closed"` when not open), status "Reverted".
  When `open` becomes false during `confirming`, call `revert()` before
  dropping state (FR-016, also covers another popup opening). A hotplug
  (name set changed) during `confirming` stops the timer and goes to
  `idle` without reverting, status "Displays changed; layout kept"
  (FR-021). The 2 s poll keeps running in `confirming`
- [X] T013 [US2] In `modules/mango/quickshell/DisplaysCard.qml` swap the
  footer while `Displays.state === "confirming"`: `RailText` "Keep this
  layout? Reverting in N s" (N bold, bound to `secondsLeft`), a `Pill`
  "Revert" and a `Pill` "Keep" with `on: true`. In this state Enter
  calls `Displays.keep()`, Esc and a click outside call
  `Displays.revert()` and leave the card open, Tab does nothing, and the
  canvas and settings are inert
  ([contracts/displays.md](contracts/displays.md) "Keys")
- [X] T014 [US2] Verify FR-017 with the `verify-quickshell` skill where a
  second display is available, else by reading the code path: when the
  display named by `Rail.openOutput` is turned off, `Rail.showsOn`
  returns true for the remaining screens and the keep question is drawn
  there with the countdown still running (state is in the singleton, not
  the destroyed window). Fix in `modules/mango/quickshell/DisplaysCard.qml`
  if focus is not taken on the new screen

**Checkpoint**: MVP. Arrange, apply, keep or revert (US1 + US2).

---

## Phase 5: User Story 3 - Change one display's settings (P2)

**Goal**: resolution, refresh rate, scale, rotation, on/off and adaptive
sync for the selected display.

**Independent Test**: quickstart D9, D10, D11, D18.

- [X] T015 [US3] In `modules/mango/quickshell/Displays.qml` add the edit
  functions, each assigning a new `pending` and ending with
  `Layout.settle(pending, name)`: `setResolution(name, w, h)` (picks
  "its highest rate"), `setMode(name, index)`, `setScale(name, s)`,
  `setRotation(name, degrees)` (changes the angle part and keeps a
  `flipped` prefix, research R9), `setAdaptiveSync(name, on)` (no
  settle), `setEnabled(name, on)`: turning off the last enabled display
  is refused with status "One display must stay on" (FR-014); turning one
  on places it right of the rightmost enabled display, then settles. Add
  `modules/mango/quickshell/displayLayout.test.mjs` cases for the pure
  helpers these use if any were added to `displayLayout.mjs`
- [X] T016 [US3] In `modules/mango/quickshell/DisplaysCard.qml` add the
  settings `Card` (colour `Config.raised`, padding 12, spacing 12) under
  the canvas for the selected display: a row with `Title` (label),
  `Detail` ("`<name> · <w>×<h> · <rate> Hz · <scale>×`", or "Off") and a
  `Pill` "On"/"Off" bound to `setEnabled`. Below, when the display is
  on, a two-column grid of `SectionLabel` plus control:
  "Resolution": a row showing the current resolution that opens a
  `Reveal` with a `ListView` of `ListRow` (at most 5 rows high, scrolls,
  `activeColor: Config.raised2`) over `Layout.resolutions`;
  "Refresh rate": `Segmented` over `Layout.rates` shown as whole Hz, or a
  second list when there are more than four;
  "Scale": `Segmented` with "1, 1.25, 1.5 and 2, plus the current value
  when it is none of these" (FR-012);
  "Rotation": `Segmented` "0°", "90°", "180°", "270°";
  "Adaptive sync": a `Pill` "On"/"Off" (FR-013).
  Segments on this card use `Config.raised2` as their track. The card
  must not grow past the screen: cap its height and let the settings
  scroll if needed
- [X] T017 [US3] In `modules/mango/quickshell/DisplayCanvas.qml` draw
  displays that are off (FR-010): a row under the arrangement of outline
  rectangles (transparent, 1.5 px dashed border in `Config.dim`, or
  `Config.fg` when selected), sized by their preferred mode at the same
  factor, selectable, not draggable, labelled with the name and "Off".
  Reserve their height when computing the factor. Add a test case to
  `modules/mango/quickshell/displayLayout.test.mjs` that `settle` and
  `valid` ignore disabled displays

**Checkpoint**: everything wdisplays did works in the card.

---

## Phase 6: User Story 4 - Keep the layout as a display setup (P3)

**Goal**: show the matched display setup; copy the layout as an entry.

**Independent Test**: quickstart D15, D16, D17.

- [X] T018 [P] [US4] In `modules/mango/scripts.nix`, `displaySetup`:
  accept `--copy` as the first argument
  ([contracts/displays.md](contracts/displays.md) "mango-display-setup");
  with it, pipe the same `jq` output to `wl-copy` and print nothing; add
  `pkgs.wl-clipboard` to `runtimeInputs`; `NAME` still defaults to
  `new-setup`; update the comment above the script
- [X] T019 [US4] In `modules/mango/quickshell/Displays.qml` add a
  `Process` running `[Config.kanshictl, "status"]` after every read;
  set `setup` to the text after `Current profile: ` (empty when the line
  is missing, the name is empty or the exit is non-zero). In
  `modules/mango/quickshell/DisplaysCard.qml` the header `Detail` shows
  `Displays.status` when set, else "Undocked" for `undocked`, else
  "Setup: <name>", else "No saved setup matches" (FR-022)
- [X] T020 [US4] In `modules/mango/quickshell/DisplaysCard.qml` add a
  `Pill` "Copy as setup" left of Apply; in
  `modules/mango/quickshell/Displays.qml` add `copySetup()` running
  `[Config.displaySetup, "--copy"]`; on exit 0 set status "Copied. Paste
  into machines/machines.nix", or, when `dirty`, "Copied the applied
  layout, not the pending changes" (US4 scenario 2); on failure "Could
  not copy"

**Checkpoint**: all four stories work.

---

## Phase 7: Polish

- [X] T021 [P] In `modules/mango/session.nix` remove `pkgs.wdisplays`
  from `home.packages` and add
  `xdg.desktopEntries.mango-displays = { name = "Displays"; genericName =
  "Display layout"; exec = "${getExe pkgs.quickshell} -c mango ipc call
  displays toggle"; icon = "video-display"; categories = [ "Settings" ];
  };` inside the existing `mkIf cfg.enable` (FR-001, FR-025, FR-026)
- [X] T022 [P] Docs: add the term **Displays card** to `GLOSSARY.md`
  after "Undocked profile" (the card that shows, arranges and applies the
  connected displays; it stores nothing, lasting layouts are display
  setups; _Avoid_: display settings, wdisplays); change step 2 of
  `specs/011-mango-docking-essentials/quickstart.md` from wdisplays to
  "Displays" in the launcher; add the `displays` row to the table in
  `specs/014-quickshell-rail/contracts/rail-ipc.md`. Keep tables aligned
  and at most 90 characters wide
- [X] T023 Compare the card with `mocks/display-mocks.html` Mock A using
  the `verify-quickshell` skill: screenshot idle, a selected display, the
  resolution list open, and the keep question; fix spacing, radii and
  type that differ from the design system (SC-008)
- [X] T024 Final gate: `nix fmt` (revert unrelated churn),
  `nix flake check`, the toplevel build of every machine in
  `machines/machines.nix`, `just qs-check`; confirm
  `rg wdisplays modules workstation machines` finds nothing; stage and
  ask the user to commit; the user deploys and runs quickstart D1 to D22
  with a second display (D9 settles research R5, D15 settles R6)

---

## Implementation Notes

Where the result differs from the task text:

- The singleton's property is `phase`, not `state`, to stay clear of
  QML's own `state`. The module is imported as `Geo`, since `Layout` is
  the attached type of QtQuick.Layouts.
- T006: Quickshell and qmllint accept the `.mjs` import; no fallback.
- T016: adaptive sync is a `Pill` in the settings header row, beside
  On/Off. The resolution list shows four rows, not five.
- T017: displays that are off are fixed-size outlined chips with a solid
  border (a QML `Rectangle` has no dashed border), not rectangles sized
  by their preferred mode.
- T014: checked by reading the code path and with faked displays; no
  second display was connected. Quickstart D8 still has to confirm it.
- T024: gates passed. Deploy and quickstart D1 to D22 are the user's.
  Measured on the panel with a 120 to 60 Hz change: reverted 11.5 s after
  Apply returned, including up to 0.4 s of measuring lag and the mode
  switch itself; D6 should time it again against SC-003.

## Dependencies & Execution Order

```text
T001 → T002 → T003 → T004 → T005 → T006
T006 → T007 → T008 → T009 → T010 → T011      (US1)
T010 → T012 → T013 → T014                    (US2; MVP with US1)
T011 → T015 → T016 → T017                    (US3)
T006 → T018 [P];  T004 → T019 → T020 (needs T018)   (US4)
T014, T017, T020 → T021 [P], T022 [P] → T023 → T024
```

- `Displays.qml` is edited by T004, T009–T012, T015, T019, T020 and
  `DisplaysCard.qml` by T005, T010, T011, T013, T016, T019, T020: one at
  a time, in order.
- US2 needs US1's Apply (T010). US3 and US4 need only the foundation and
  can come before US2, but the card should not be deployed without US2.
- T008 and T015 change `displayLayout.mjs` and its test together; the
  toplevel build fails if they disagree.

## Parallel Opportunities

- T018 (`scripts.nix`) alongside anything after T006.
- T021 (`session.nix`) and T022 (docs) alongside each other and alongside
  T023.

## Implementation Strategy

1. Setup and foundation (T001–T006): the card opens, the module is
   tested, the `.mjs` question is settled.
2. US1 + US2 (T007–T014): arrange, apply, keep or revert. This is the MVP;
   do not deploy US1 without US2.
3. US3 (T015–T017): settings; from here wdisplays is no longer needed.
4. US4 (T018–T020): setup name and copy.
5. Polish (T021–T024): wdisplays out, launcher entry, docs, final gate.
