# Tasks: Duplicate Display

**Input**: design documents in `specs/020-duplicate-display/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/displays.md](contracts/displays.md),
[quickstart.md](quickstart.md)

**Tests**: FR-033 asks for build-time tests of the stack rules. They
extend `modules/mango/quickshell/displayLayout.test.mjs` and are named in
T004, T010, T016 and T022. Everything else is checked by `qmlCheck`,
shellcheck, `just qs-check` and the quickstart by hand.

**Design reference**: `mocks/duplicate-display-mocks.html`, section
"A+B". All QML uses the tokens and components of
`modules/mango/quickshell/README.md`; no literal colour, size or radius.

**Words**: copy, source, stack, placed, parked, orphan, as in
[data-model.md](data-model.md). `gap` is 8192.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no unfinished dependency)
- **[Story]**: the user story the task belongs to (US1 to US3)

---

## Phase 1: Setup

- [X] T001 By hand, before any code, with a second display: prove
  research R3 on the real session. Read the layout with
  `wlr-randr --json`, then park the external display under the panel:
  `wlr-randr --output <external> --pos <panel x>,<panel y + 8192>`.
  Check quickstart M4 (the pointer cannot leave the panel on any side)
  and M5 (an X11 program starts and draws). Put the display back with
  `kanshictl reload`. Write the result under "To verify" of R3 in
  `specs/020-duplicate-display/research.md`. If the pointer reaches the
  parked display or X11 breaks, stop: the plan needs another answer for
  FR-004
- [X] T002 Build plumbing. In `modules/mango/common.nix` add
  `parkGap = 8192;` with a comment ("How far below its source a copy is
  parked, specs/020 research R3") and export it like `panel`. In
  `modules/mango/quickshell/Config.qml` add, under the displays card's
  values, `readonly property int parkGap: @parkGap@`,
  `readonly property string panel: "@panel@"`,
  `readonly property string copyGuard: "@copyGuard@"` and
  `readonly property string lidSync: "@lidSync@"`, with one comment
  line. In `modules/mango/quickshell.nix` fill them in the `replaceVars`
  set: `toString parkGap`, `panel`, `getExe copyGuard` (T007 makes it;
  until then point it at `getExe lidSync` so the build passes),
  `getExe lidSync`

---

## Phase 2: Foundational (blocks every story)

**Purpose**: a copy can exist. Parked positions are read and written, the
picture is shown, focus and windows stay off the copy, and a broken stack
repairs itself. No control in the card makes a copy yet; T009 makes one by
hand.

- [X] T003 Copies in `modules/mango/quickshell/displayLayout.mjs`
  (research R4, R6). `fromRandr` gives every display `copyOf: ""` and
  `orphan: false`. Add `placed(d)`: "enabled and `copyOf` is \"\"".
  Add `unpark(layout, gap)`: "a display with `y >= gap` is a copy of
  the enabled display at `(x, y mod gap)` whose own `y` is below the
  gap"; it gets `copyOf` and the source's `x` and `y`; with no such
  display it keeps `copyOf: ""`, gets `orphan: true` and `y mod gap`.
  Add `park(layout, gap)`: copies in the order read get slot 1, 2, 3
  and `y = source.y + slot × gap`, `x = source.x`. Add
  `follow(layout)`: every copy takes its source's `x` and `y`. Make
  `rect` users (`valid`, `snap`, `place`, `settle`, `normalise`,
  `frame`, `component`) work on `placed` displays instead of enabled
  ones, and end `settle` and `normalise` with `follow`. `key(d)`
  for an enabled copy is `[name, mode, transform, adaptiveSync,
  copyOf]` (no `x`, `y`, `scale`); for other enabled displays add
  `copyOf` (always "") at the end. `valid` adds the rules of
  data-model.md "Layout": "a copy's source is enabled and is not itself
  a copy", "at most 3 copies", "with any copy, the placed displays'
  bounding box is under `gap` tall, and every copy's logical height is
  under `gap`", "no orphan"; it takes `gap` as a second argument.
  `applyArgs(layout, applied, gap)` runs `park` first, so a copy's
  group has `--pos <source x>,<source y + slot × 8192>`
  ([contracts/displays.md](contracts/displays.md), "Applying"). Add
  `sourceOf(layout, name)`: the source's name for a copy, else `name`;
  `copiesOf(layout, name)`; `stackLabel(layout, name)`: the labels of
  the source and its copies joined with " + "
- [X] T004 Tests for T003 in
  `modules/mango/quickshell/displayLayout.test.mjs`, with `const gap =
  8192` and a three-display sample (add a third JSON display beside
  `panelJson` and `dellJson`). Cases: `unpark` of a display at the
  panel's `x` and `y = 8192` gives `copyOf: "eDP-1"` and the panel's
  position; at `y = 16384` too; a parked display with no display above
  it is an orphan; `unpark(park(x))` deep-equals `x` for one and two
  copies; `applyArgs` exact `--pos` for a copy in slot 1 and slot 2;
  `valid` false for a copy of a copy, a copy of an off display, four
  copies, placed displays 8192 tall with a copy, an orphan; `valid`
  true for the same tall layout with no copy; `same` false when only
  `copyOf` differs and true when only a copy's `scale` differs;
  `settle` on a layout with a copy leaves the copy at its source's
  position; every existing case still passes with `gap` added where
  the signature changed
- [X] T005 Read and apply copies in
  `modules/mango/quickshell/Displays.qml`. In the reader, pass the
  parsed layout through `Geo.unpark(next, Config.parkGap)`. Pass
  `Config.parkGap` to every `Geo.valid` and `Geo.applyArgs` call
  (apply and revert). Add `function sourceOf(name)` over `applied`
  and `readonly property var copies`: the list of `{ copy, source }`
  name pairs in `applied`. `select()` keeps a selected copy.
  `setScale` does nothing for a copy. Update the header comment: the
  layouts now hold which display copies which (specs/020)
- [X] T006 [P] Create `modules/mango/quickshell/Mirror.qml` (research
  R2; [contracts/displays.md](contracts/displays.md), "The mirror") with
  a header comment that says what it is and names specs/020. A
  `PanelWindow` with `required property var modelData`, `screen:
  modelData`, all four anchors, `color: "black"` (the one literal: the
  bars of FR-002 are black whatever the palette; say so in a comment),
  `exclusionMode: ExclusionMode.Ignore`, `WlrLayershell.layer:
  WlrLayer.Overlay`, `WlrLayershell.keyboardFocus:
  WlrKeyboardFocus.None`, namespace `"mango-mirror"`, an empty input
  `mask: Region {}`. `readonly property string source:
  Displays.copies.find(p => p.copy === modelData.name)?.source ?? ""`;
  `visible: source !== ""`. Inside, `ScreencopyView` from
  `Quickshell.Wayland`: `anchors.centerIn: parent`, `captureSource:
  Quickshell.screens.find(s => s.name === win.source) ?? null`,
  `live: true`, `paintCursor: true`, `constraintSize:
  Qt.size(win.width, win.height)`. In
  `modules/mango/quickshell/shell.qml` add `Variants { model:
  Quickshell.screens; Mirror {} }` after the `DisplaysCard` one, and a
  line in the header comment. `git add` the new file
- [X] T007 [P] Add `copyGuard` to `modules/mango/scripts.nix`: a
  `writeShellApplication` named `mango-copy-guard` with
  `runtimeInputs = [ pkgs.coreutils pkgs.jq mango ]`, a comment that
  names specs/020 research R5, and the behaviour of
  [contracts/displays.md](contracts/displays.md), "mango-copy-guard":
  arguments `COPY=SOURCE`, "Exit 2 with a usage line on an argument
  that is not `COPY=SOURCE`"; a `sweep` function that (1) for every
  client of `mmsg get all-clients` whose `.monitor` is a `COPY` runs
  `mmsg dispatch "tagmon,SOURCE,0" "client,ID"` (the form
  `mango-swap-monitors` uses), and (2) when the `.active` monitor of
  `mmsg get all-monitors` is a `COPY`, runs `mmsg dispatch
  "focusmon,NAME"` for "the next monitor that is not a copy, in the
  direction focus arrived from (the order of `mmsg get all-monitors`)",
  remembering the last active monitor that was not a copy in a shell
  variable, and "when the direction is not known, to its `SOURCE`";
  then `sweep` once, and again for every line of
  `{ mmsg watch all-monitors & mmsg watch all-clients; } | while read`.
  Export it from the file like `lidSync`, and point `copyGuard` in
  `modules/mango/quickshell.nix` at it (T002). In
  `modules/mango/quickshell/Displays.qml` add a `Process` whose
  command is `[Config.copyGuard]` plus `copy + "=" + source` for each
  entry of `copies`, `running: copies.length > 0`; when `copies`
  changes while it runs, stop it and start it again with the new pairs
- [X] T008 Repair (research R7). In
  `modules/mango/quickshell/displayLayout.mjs` add `broken(layout)`:
  true when any display is an orphan, or a copy's source is off or
  missing; and `repair(layout)`: for a lost or off source, "the first
  copy becomes the source" at the source's `x`, `y` and keeps the other
  copies (FR-026); any other orphan gets `copyOf: ""`, `orphan: false`
  and is placed "right of everything" then settled (FR-007); the result
  is `valid`. Tests in `displayLayout.test.mjs`: an orphan alone is
  placed touching the rest; a parked copy whose source is `enabled:
  false` takes the source's position; two copies of a lost source give
  one source and one copy; `repair` of a layout that is not `broken`
  is the same layout. In `modules/mango/quickshell/Displays.qml`: read
  on `Quickshell.screensChanged` also while the card is closed; in
  `took(next)`, when `Geo.broken(next)`, apply
  `Geo.repair(next)` at once through the `applier` with a new
  `purpose` `"repair"` (no keep question: on exit just read), set
  status to "<label> is gone; duplicate ended", and when `phase` is
  `"confirming"` stop the countdown and go to `"idle"` without
  reverting
- [X] T009 Popups never open on a copy (research R10, FR-023). In
  `modules/mango/quickshell/Rail.qml` change `showsOn(name)` so the
  remembered output is first passed through `Displays.sourceOf`: true
  when `openOutput === ""`, when `Displays.sourceOf(openOutput) ===
  name`, or when no screen has that name. Extend the comment over it
- [X] T010 Gate for the foundation. `git add` the new files, `nix fmt`
  (revert unrelated churn), `nix flake check`, `nix build
  '.#nixosConfigurations.laptop.config.system.build.toplevel'` (runs
  `qmlCheck`, shellcheck and `mango-display-layout-test`), `just
  qs-check`. Then with the `verify-quickshell` skill on a session with
  two displays: park one by hand as in T001 and capture it: the mirror
  shows the other display, fitted, with the pointer; `kanshictl reload`
  and capture again: the mirror is gone. Check the log for warnings from
  `Mirror.qml` and `Displays.qml`

**Checkpoint**: a display parked by hand shows its source, takes no
focus or window, and unparks itself when the source goes.

---

## Phase 3: User Story 1 - Duplicate from the keyboard (Priority: P1) MVP

**Goal**: open the card, `Right`, `Enter`, `Enter`: the external
display shows the panel's picture.

**Independent Test**: quickstart M1, M2, M7, M15, M21, M22.

- [X] T011 [US1] Arrangements in
  `modules/mango/quickshell/displayLayout.mjs` (data-model.md,
  "Arrangement"). `choices(layout, panel)`: `[]` with one connected
  display, else `["extend", "duplicate"]` (US3 adds the other two).
  `arrangement(layout, ctx)` with `ctx = { panel, lidClosed,
  selected }`: `"extend"` when "every display enabled, none a copy",
  `"duplicate"` when "every display enabled, one source, the rest its
  copies", else `""`; "every display" leaves out a panel that is off
  while `ctx.lidClosed`. `arrange(layout, choice, ctx)`: for
  `"extend"` turn every display on, clear every `copyOf`, and place
  each display that was off or a copy "right of everything" then
  settle; for `"duplicate"` the source is "the panel when it is
  connected and the lid is open, else the selected display, else the
  first enabled one" (FR-010), every other display is turned on with
  `copyOf` the source, then settle; in both a panel that is off with
  the lid closed stays off; "a display that already is as the choice
  describes keeps every value" (FR-011). Returns the layout unchanged
  when the result is not `valid`
- [X] T012 [US1] Tests for T011 in
  `modules/mango/quickshell/displayLayout.test.mjs`: `choices` for
  one, two and three displays; `arrangement` names an extended and a
  fully duplicated layout and gives `""` for a stack of two with a
  third extended; `arrange` duplicate with the panel connected makes
  the panel the source; without a panel the selected display; with
  `lidClosed` the panel stays off and is not the source; `arrange`
  extend after duplicate leaves "all displays on and none a copy"
  (SC-007) and is `valid`; extend on an already extended layout
  deep-equals the input (FR-011); duplicate with five displays returns
  the input (four copies)
- [X] T013 [P] [US1] Lid state. In `modules/mango/scripts.nix` give
  `mango-lid-sync` a `state` argument, handled first: it "prints
  `open` or `closed` and exits 0; `open` on a machine with no lid",
  reusing the loop over `/proc/acpi/button/lid/*/state` that the
  script has (move it into a function both paths call). Extend the
  comment over `lidSync`
- [X] T014 [US1] Arrange in `modules/mango/quickshell/Displays.qml`.
  Add `property bool lidClosed: false` and a `Process` running
  `[Config.lidSync, "state"]` when the card opens, setting it from the
  output. Add `readonly property var arrangeContext: ({ panel:
  Config.panel, lidClosed: lidClosed, selected: selected })`,
  `readonly property var choices: Geo.choices(pending, Config.panel)`,
  `readonly property string arrangement: Geo.arrangement(pending,
  arrangeContext)`, and `function arrange(choice)`: `status = ""`,
  `pending = Geo.arrange(pending, choice, arrangeContext)`; when
  `pending` did not change and `arrangement !== choice`, set status
  to "At most three displays can duplicate" or "This layout is too tall
  to duplicate" (whichever rule of `valid` failed; add a small
  `Geo.whyNot(layout, gap)` that returns one of the two lines or "").
  `function arrangeStep(delta)`: with `i` the index of
  `arrangement` in `choices`, pick `i + delta` when it is in range;
  with no choice marked, "right picks the first and left the last"
  (FR-013). After a change, when `selected` is no longer in a state
  that can be shown, call `select()`
- [X] T015 [US1] The switch in
  `modules/mango/quickshell/DisplaysCard.qml`. Between the header row
  and `DisplayCanvas` add a `Segmented` with `visible:
  Displays.choices.length > 0`, `enabled: win.idle`, `options` the
  labels of `Displays.choices` ("Extend", "Duplicate", "Only panel",
  "Only external"), `current: Displays.choices.indexOf(
  Displays.arrangement)`, `onPicked: Displays.arrange(
  Displays.choices[index])`. Add `property int listsOpen: 0` to the
  window, counted up and down by `Chooser.onExpandedChanged`. On
  `stage` add `Keys.onLeftPressed` and `Keys.onRightPressed`: when
  `win.idle && win.listsOpen === 0` call `Displays.arrangeStep(-1)`
  or `(1)`. Change the footer `Hint` to "← → arrangement · Tab next
  display · Drop on a display to duplicate · Enter applies" and add the
  two keys to the header comment
- [X] T016 [US1] Draw stacks in
  `modules/mango/quickshell/DisplayCanvas.qml` (research R9). `onKey`
  lists the placed displays only (`Geo.placed`), so a copy has no tile
  of its own. For a tile whose display has copies
  (`Geo.copiesOf(Displays.pending, name).length > 0`): draw a second
  rectangle of the same size behind it, offset 6 up and 6 right, in
  `Config.raised3` with `Config.chipRadius` (the "ghost" of the
  mock), animated like the tile; the label is
  `Geo.stackLabel(Displays.pending, name)` and the detail line starts
  with "Duplicated · ". A tile is `picked` when `Displays.selected`
  is its display or one of its copies. Pass `Config.parkGap` wherever
  the canvas calls a function whose signature changed. Add to
  `displayLayout.test.mjs`: `frame` of a layout with a copy equals
  `frame` of the same layout without that display
- [X] T017 [US1] Settings of a copy in
  `modules/mango/quickshell/DisplaysCard.qml` (FR-006, FR-017). With
  `win.display.copyOf !== ""`: the `Detail` under the title reads
  "<name> · Duplicates <source label> · <w>×<h> · <rate>"; the Scale
  column of the grid is hidden (`visible: false`, so Rotation takes
  the row); Resolution, Refresh rate, Rotation, Adaptive sync and On/Off
  stay. For a source with copies the `Detail` ends with " · Shown on
  <copy labels>". In `Displays.setEnabled(name, false)` for a copy,
  clear `copyOf` as well (data-model.md, Layout rule 2)
- [ ] T018 [US1] Gate and check. The gate commands of T010. Then
  quickstart M1, M2, M7, M15, M21 and M22 with the panel and one
  external display, and captures of the card with the
  `verify-quickshell` skill in three states: Extend marked, Duplicate
  pending (one stack tile), a copy selected (no Scale column)

**Checkpoint**: the presentation case works from the keyboard.

---

## Phase 4: User Story 2 - Duplicate one chosen pair (Priority: P2)

**Goal**: with three displays, drag one tile onto another; that pair is a
stack and the third display still extends the desktop.

**Independent Test**: quickstart M8 to M11, M24.

- [X] T019 [US2] Stack operations in
  `modules/mango/quickshell/displayLayout.mjs` (data-model.md,
  "Operations"). `stack(layout, name, target, gap)`: "`name` and its
  copies become copies of `target`'s source", then settle; it "does
  nothing when `target` is `name`, is off, or is already in `name`'s
  stack, and when the result would break rule 3 or 4".
  `separate(layout, name)`: clears `copyOf`, places the display
  "right of everything", settles. `makeSource(layout, name)`: `name`
  takes `copyOf: ""` and its old source's `x`, `y` and `scale`; the
  old source and the other copies get `copyOf: name`; nothing else
  moves (FR-018). `disable(layout, name)`: for a source with copies,
  `makeSource` on its first copy and then the display goes off
  (FR-026); otherwise the plain patch. `dropTarget(layout, name, x, y)`:
  the name of the placed display, other than `name`'s own stack, whose
  rectangle shrunk by a quarter on each side contains the layout point
  `x, y`, else `""`
- [X] T020 [US2] Tests for T019 in
  `modules/mango/quickshell/displayLayout.test.mjs`: `stack` of C on
  A in a row A, B, C leaves A and B touching and C a copy of A; `stack`
  on a copy lands on that copy's source (FR-003: no copy is a source,
  asserted over every result in this block); `stack` of a source with
  a copy moves both; `stack` on itself, on an off display and a fourth
  copy return the input; `separate` gives a `valid` layout with the
  display placed and touching; `makeSource` keeps every other
  display's position and swaps the roles; `disable` of a source with
  two copies leaves one source, one copy and one off; `dropTarget`
  inside the inner half, in the outer quarter (`""`), and over the
  dragged display's own stack (`""`); after every operation the placed
  displays are connected with no overlap (FR-019)
- [X] T021 [US2] Stack edits in
  `modules/mango/quickshell/Displays.qml`: `function stack(name,
  target)`, `separate(name)`, `makeSource(name)`, each clearing
  `status`, assigning `pending` and setting the status line of
  `Geo.whyNot` when `stack` changed nothing. `setEnabled(name,
  false)` goes through `Geo.disable`. Add `property string
  dropTarget: ""`, set by the canvas during a drag and cleared in
  `drop`
- [X] T022 [US2] Drop on a tile in
  `modules/mango/quickshell/DisplayCanvas.qml` (FR-015). In the tile's
  `onPositionChanged`, after the drag has started, convert the pointer
  to layout coordinates and set `Displays.dropTarget =
  Geo.dropTarget(Displays.pending, tile.modelData, lx, ly)`; while it
  is not `""` skip `Displays.move`'s snapping (pass threshold 0). A
  tile whose name is `Displays.dropTarget` shows a 2 px
  `Config.fg` border and a centred `Detail` "Duplicate here" in
  place of its label. In `onReleased` and `onCanceled`: when
  `Displays.dropTarget !== ""` call `Displays.stack(tile.modelData,
  Displays.dropTarget)`, then `Displays.drop` as before. Dragging a
  stack tile moves the source; the copies follow through `follow`
  (T003), so nothing more is needed (FR-016)
- [X] T023 [US2] Stack controls in
  `modules/mango/quickshell/DisplaysCard.qml` (FR-017, FR-018). In the
  selected display's header row, for a copy, add two `Pill`s before
  "On": "Separate" (`Displays.separate`) and "Make source"
  (`Displays.makeSource`), both `color: Config.raised2`. When the
  selected display is in a stack of two or more, add a row under the
  header with one `Pill` per member (label `Geo.label`, `on` for the
  selected one) that sets `Displays.selected`. A click on a stack tile
  selects the source (already so: the tile's name is the source's)
- [ ] T024 [US2] Gate and check. The gate commands of T010. Then
  quickstart M8 to M11 and M24 with three displays, M6 and M9 for the
  guard, and captures with the `verify-quickshell` skill of: a tile
  held over a drop target, a stack beside a third display with no
  switch choice marked, a copy selected with its two pills

**Checkpoint**: any pair can be duplicated while the rest extend.

---

## Phase 5: User Story 3 - Show only one side (Priority: P3)

**Goal**: "Only panel" and "Only external" in the switch.

**Independent Test**: quickstart M16, M17, and "Only external" applied
with the panel and one external display.

- [X] T025 [US3] In `modules/mango/quickshell/displayLayout.mjs`:
  `choices` returns all four "when the panel and at least one other
  display are connected"; `arrangement` also names `"panel"` ("the
  panel enabled, every other display off") and `"external"` ("the
  panel off, every other enabled, none a copy"); `arrange` builds
  both, clearing `copyOf` everywhere, with `"panel"` returning the
  input while `ctx.lidClosed` (it would turn every display off).
  Tests in `displayLayout.test.mjs`: `choices` with and without the
  panel in the layout; both arrangements are recognised and are
  `valid`; each followed by `"extend"` leaves all on and none a copy
  (SC-007); `"external"` from a duplicated layout has no copy;
  `"panel"` with the lid closed returns the input
- [ ] T026 [US3] Check. No QML change is expected: the switch draws
  what `choices` returns (T015). Gate commands of T010, then quickstart
  M16 on the desktop machine, M17 with one display, and "Only external"
  then "Only panel" on the laptop, each applied and kept

**Checkpoint**: all four arrangements work from the keyboard.

---

## Phase 6: Polish & Cross-Cutting

- [X] T027 [P] "Copy as setup" (research R11, FR-029). In
  `modules/mango/scripts.nix` pass `--argjson gap ${toString parkGap}`
  to the `jq` call of `mango-display-setup` and, before the entry is
  built, rewrite each enabled output with `.position.y >= $gap` to "
  enabled at `y = 0`, right of every other display, in the order
  read" (`x` = the largest `position.x + width / scale` of the
  outputs before it, floored). In
  `modules/mango/quickshell/Displays.qml`, where the copy confirmation
  is set, use "Copied without the duplicate" when `copies.length > 0`
- [X] T028 [P] Words and pointers. In `GLOSSARY.md`, after "Displays
  card", add **Copy**, **Source** and **Stack** for displays, each one
  or two sentences in the wording of spec.md's opening, with
  `_Avoid_: mirror, clone`. In
  `specs/018-display-layout-card/contracts/displays.md` under
  "Applying" add one line: a copy's `--pos` is defined in
  `specs/020-duplicate-display/contracts/displays.md`. In
  `specs/018-display-layout-card/data-model.md` add one line under
  "Display" that points to the `copyOf` field of specs/020
- [X] T029 Full gate: `nix fmt` (revert unrelated churn), `nix flake
  check`, `nix build
  '.#nixosConfigurations.laptop.config.system.build.toplevel'`, `just
  qs-check`, and the log check of the `verify-quickshell` skill for
  every QML file this feature touched
- [ ] T030 By hand on the laptop after `sudo nixos-rebuild switch
  --flake .#laptop`: the rest of
  [quickstart.md](quickstart.md): M3 (note the capture rate), M12 to
  M14, M18 to M20, M23. Write the M3 result into research R2 ("Not
  measured") and replace "looks smooth" in spec.md SC-003 with the
  measured number. If M3 is not smooth, run the `wl-mirror` comparison
  at the end of the quickstart and record both before changing anything

---

## Dependencies

- T001 gates everything: it can end the plan.
- T002 before T005, T006, T007.
- T003 before T004, T005, T008, and every later `displayLayout.mjs`
  task (T008, T011, T019, T025 edit the same file, in that order).
- T005 before T006's check, T007's `Process`, T008, T009.
- Phase 2 complete before any story.
- US1 (T011 to T018) before US2 and US3: both build on the switch,
  the stack tile and `arrange`.
- US2 and US3 are independent of each other.
- T027 and T028 can be done any time after Phase 2.

## Parallel Opportunities

- T006 (`Mirror.qml`, `shell.qml`) and T007 (`scripts.nix`, one
  `Process` in `Displays.qml`) after T005; T007's `Displays.qml` edit
  waits for T005.
- T013 (`scripts.nix`) beside T011 and T012 (`displayLayout.mjs`).
- T027 and T028 beside each other and beside Phase 5.

Most other tasks share `displayLayout.mjs`, `Displays.qml` or
`DisplaysCard.qml` and run in order.

## Implementation Strategy

1. T001 first, alone. It costs ten minutes and tests the one assumption
   everything rests on.
2. Phase 2, then stop at the checkpoint: a hand-parked display must
   behave before any control is built on it.
3. US1 is the MVP: the presentation case, keyboard only.
4. US2, then US3; each is usable when its checkpoint passes.
5. Polish, with T030 last because it needs the deployed system.
