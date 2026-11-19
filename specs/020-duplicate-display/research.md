# Research: Duplicate Display

## R1. Mango cannot duplicate

- **Finding**: Mango 0.18.5 has no mirror or clone option, dispatcher or
  monitor rule (its source and docs were searched). Giving two displays
  the same position is accepted (`src/manage/monitor.c:1310` has no
  overlap check), but each display keeps its own tags, windows and rail,
  so both sets are drawn over each other and the pointer belongs to only
  one of them. `disable_monitor` removes the display, which turns it off.
- **Decision**: the shell makes the copy itself (R2 to R5).
- **Alternatives**: patch Mango (the repository already carries one
  patch, but a duplicate mode touches output layout, scene and focus: a
  large patch to keep alive across releases); wait for upstream.

## R2. The picture: Quickshell's ScreencopyView

- **Decision**: `Mirror.qml`, a `PanelWindow` per copy on the overlay
  layer, anchored to all four edges, black, with a centred
  `ScreencopyView` whose `captureSource` is the source's screen,
  `live: true`, `paintCursor: true` and `constraintSize` the window's
  size. No keyboard focus, no exclusive zone.
- **Rationale**: tried on this session (DP-9, 3840×2160, shown on DP-5,
  1440×2560 portrait). The view fitted itself to 1440×810, centred, with
  the pointer drawn, and the window ran at 60 frames per second. It needs
  no new package, it is a layer surface, so Mango never tiles or focuses
  it, and it goes away with the shell (FR-025). A layer surface is laid
  out in the copy's own logical space, so a rotated copy shows the picture
  upright with nothing to compute.
- **Not measured**: the capture rate. The trial ran inside the agent
  sandbox, which hides `/dev/dri`, so Quickshell fell back to
  memory-copied buffers (`Failed to find render device`). The 60 is the
  window's own frame rate, not how often a new picture arrived. Quickstart
  M3 measures it on a real session and settles SC-003.
- **Alternatives**: `wl-mirror` 0.18.5 (also tried; works with
  `-b extcopy-shm` and `-b screencopy-shm`; but it is one more package,
  one process per copy to supervise, and an ordinary window that Mango
  tiles, focuses and lists); the same position for both displays (R1).

## R3. Off the desktop: park the copy below its source

- **Decision**: a copy keeps the same `x` as its source and gets
  `y = source.y + slot × gap`, with `gap` 8192 logical pixels and `slot`
  1, 2 or 3, one slot per copy over the whole layout. The gap is declared
  once as `parkGap` in `modules/mango/common.nix`.
- **Rationale**: the pointer moves through wlroots' `wlr_cursor_move`
  (`src/input/pointer.c:1257`), which clamps to the closest point of the
  output layout. Across a gap that point is always the edge of the display
  the pointer is on, so the pointer cannot reach the copy (FR-004). The
  copy stays an enabled output, which `ScreencopyView` and the lock screen
  need. Slots keep two copies from overlapping each other.
- **Why 8192 and three slots**: X11 coordinates end at 32767, and
  Xwayland's screen spans the whole layout. Three slots of 8192 plus the
  tallest display stay below that. So while any display is a copy, the
  placed displays must be less than 8192 tall together, and a fourth copy
  is refused with a line that says so. Both are far from any desk this
  configuration runs on, and both are checked in `valid` (R6).
- **Verified** (tasks T001, 2026-11-19, DP-9 with DP-5 parked 8192 below
  it): a virtual pointer pushed 24000 pixels against each edge, in steps
  of 300 and of 40, stayed on DP-9 every time. Xwayland kept answering,
  with a screen of 3072×10752. One motion event longer than about half
  the gap would cross; no pointing device sends that. Quickstart M4 and M5
  repeat this by hand.
- **Alternatives**: a gap to the right (same reasoning, but layouts are
  usually wider than tall, so less room under 32767); a patch that marks
  an output as outside the pointer's desktop (R1).

## R4. The position is the record

- **Decision**: `unpark`, run on every read, finds each enabled display
  with `y` at or above the gap and looks for an enabled display at the
  same `x` and at `y` modulo the gap. Found: the first is a copy of the
  second, and takes the source's position in the card's layouts. Not
  found: an orphan, which the card repairs (R7). `park` does the reverse
  inside `applyArgs`.
- **Rationale**: nothing is stored (FR-028) and nothing can disagree with
  the displays (FR-024). Apply, the keep question and Revert already apply
  and compare whole layouts, so they cover copies with no new path
  (FR-021, FR-022). kanshi applying a display setup moves every display to
  its declared position, which ends the duplicate, as the spec asks. A
  restarted shell reads the positions and shows the mirrors again.
- **Alternatives**: a list in the `Displays` singleton (lost on a shell
  restart, with the copy left parked and showing a desktop nobody can
  reach); a state file (against FR-028, and it can go stale).

## R5. The guard: focus and windows

- **Finding**: the gap stops the pointer, not the key bindings.
  `focusmon,next` and `tagmon,next` (`Super+.`, `Super+Shift+.`) walk
  Mango's list of monitors, and `monitor_from_direction` finds the nearest
  output in a direction whatever the distance. Either can focus a copy or
  send a window to it.
- **Decision**: `mango-copy-guard`, a `writeShellApplication` that
  `Displays.qml` runs while at least one copy is applied, with the pairs
  as arguments ([contracts/displays.md](contracts/displays.md)). It reacts
  to `mmsg watch all-monitors` and `mmsg watch all-clients`. A window on a
  copy is sent to its source with `tagmon`. A focused copy passes focus on
  in the direction it came from, to the next display that is not a copy,
  so `Super+.` still reaches every real display.
- **Rationale**: both dispatchers and both watch streams are already used
  in this repository (`mango-swap-monitors`, `Tags.qml`). The same first
  pass that runs when the guard starts moves the windows that were on the
  display when it became a copy (FR-005).
- **Limit**: the guard reacts after the fact, so focus is on the copy for
  an instant. Nothing is visible there, because the mirror covers it.
- **Alternatives**: remove the bindings while a copy exists (needs a
  config reload, and the scripts would still reach it); a Mango patch
  (R1).

## R6. Stack rules in the layout module

- **Decision**: a display gains `copyOf`, the name of its source or "".
  `displayLayout.mjs` gains `park` and `unpark` (R3, R4); `stack`,
  `separate` and `makeSource`; `arrangement`, `choices` and `arrange`
  for the switch; `repair` (R7). The existing geometry (`rect`, `snap`,
  `settle`, `frame`, `valid`) works on the *placed* displays: enabled
  and not a copy. `same` compares `copyOf` too, so `dirty` and the
  honest-refresh check of specs/019 see it.
- **Rationale**: FR-033, and constitution principle I. These rules have
  the most cases and need no display to test.
- **Tests added**: a copy is never a source (FR-003); every arrangement,
  then Extend, leaves all on and none a copy (SC-007); a choice keeps
  what already fits (FR-011); `unpark(park(x))` is `x`; the placed
  displays stay connected after every stack, separate and promotion
  (FR-019); the first copy takes over a source that goes off (FR-026); a
  fourth copy and a layout 8192 tall are not valid.

## R7. Repair without the card

- **Finding**: a source can go away while the card is closed: unplugged,
  or the panel turned off by `mango-lid-sync`. Its copy is then parked
  with nothing to show.
- **Decision**: `Displays.qml` also reads when `Quickshell.screens`
  changes while the card is closed. When the layout it reads has an
  orphan, or a copy whose source is off, it applies `repair(layout)` at
  once, with no keep question: the first copy of a lost source takes the
  source's place (FR-026), any other orphan is placed like a display that
  was turned on (FR-007).
- **Rationale**: FR-025 gives 5 seconds. The screens signal arrives
  within one. While the display is orphaned the mirror window shows
  black, since its source screen is gone.
- **Alternatives**: let kanshi do it (it only acts when a declared setup
  matches); the 2 s poll (runs only while the card is open).

## R8. The arrangement switch

- **Decision**: a `Segmented` between the header and the canvas. Its
  options come from `choices(layout, panel)`: Extend and Duplicate with
  two or more connected displays, plus "Only panel" and "Only external"
  when the panel (`Config.panel`, the module's `displays.internal`) is
  among the connected displays and another display is too. `current` is
  `arrangement(pending, panel)`, or -1. Left and Right are handled by the
  card's key handler beside Tab, and are ignored while a `Chooser` list
  is open.
- **Lid**: for Duplicate and Extend the panel is left off while the lid
  is closed (FR-010). `mango-lid-sync` gains a `state` argument that
  prints `open` or `closed`, so the lid is read in one place; the card
  asks it when it opens.
- **Alternatives**: four pills (not exclusive, and `Segmented` already
  marks one of several); a `Chooser` (two more key presses).

## R9. Dropping on a tile

- **Decision**: while a tile is dragged, the pointer over the inner half
  of another placed tile (a quarter in from each side) marks that tile
  as the drop target and stops snapping. Release calls `stack`. Outside
  the inner half, snapping works as before. A stack is drawn as its
  source's tile with a second outline offset behind it, and the label
  names every member.
- **Rationale**: the pointer's position, not the dragged tile's overlap,
  decides, so a large tile dragged past a small one does not stack by
  accident.
- **Selecting a member**: Tab walks every display, copies included. A
  click on a stack selects its source. The settings card of a display in
  a stack shows the other members as pills that select them.

## R10. The shell's own windows on a copy

- **Finding**: `Bar`, the popups and the displays card are made per
  screen. On a copy they sit under the mirror: harmless, but a popup or
  the keep question opened there would be invisible. Popups opened over
  IPC go to the pointer's display, which is never a copy; the keep
  question goes to `Rail.openOutput`, which may have just become one.
- **Decision**: `Rail.showsOn` treats a copy as its source, using a
  `Displays.sourceOf(name)` that reads the applied layout (FR-023).
  Notifications set no screen and follow focus, which the guard keeps off
  copies. The lock screen needs nothing: session-lock surfaces are above
  the overlay layer on every output (FR-027; quickstart M12).

## R11. "Copy as setup"

- **Decision**: `mango-display-setup` takes the gap as an argument from
  Nix and writes a parked display as an extended one, right of the
  widest reach of the others, at `y` 0. `--copy` exits 0 and prints
  nothing, as before; the card adds "the duplicate is not part of it" to
  its line when a copy is applied (FR-029).
- **Rationale**: without this the entry would hold `y = 8192`, which is
  valid for kanshi and wrong on the desk.
