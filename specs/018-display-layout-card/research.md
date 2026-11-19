# Research: Display Layout Card

## R1. Reading and changing displays: wlr-randr

- **Decision**: read with `wlr-randr --json`; apply with one `wlr-randr`
  call that has an `--output` group for every connected display
  ([contracts/displays.md](contracts/displays.md)). Both by store path
  through `Config.wlrRandr`.
- **Rationale**: Quickshell 0.3.2 ships no module for the output
  management protocol (its installed QML modules were listed; none), and
  `Quickshell.screens` is read-only and lists enabled outputs only.
  `wlr-randr` speaks the protocol Mango already serves to kanshi and
  wdisplays (specs/011, R1). One call builds one configuration, so the
  change is atomic (FR-015). The JSON holds everything the card shows:
  modes, position, scale, transform, enabled, adaptive sync. Checked on
  the laptop: `wlr-randr --output eDP-1 --mode 1x1 --dryrun` prints
  `unknown mode: 1x1` and exits 1; a valid change exits 0.
- **Alternatives**: a native Quickshell plugin in C++ (events instead of
  polling, but a package to maintain for a tool used a few times a
  month); `mmsg` (no mode, scale or position commands); writing kanshi
  profiles at run time (state outside the Nix configuration, against
  FR-024).

## R2. Seeing changes from outside

- **Decision**: re-read on open, after every Apply, Keep and Revert, when
  `Quickshell.screens` changes, and every 2 s while the card is open.
  A different set of connector names is a hotplug (FR-021). Any other
  difference from the applied layout also drops pending changes, with a
  line that says the layout changed.
- **Rationale**: `wlr-randr` is one-shot; there is no event stream. The
  screens signal misses a display that is connected but off, which the
  poll catches. The poll runs only while the card is open and costs one
  short process.
- **Alternatives**: screens signal only (misses disabled outputs and
  kanshi re-applying); a long-running watcher process (none exists for
  this protocol in nixpkgs).

## R3. Where the state lives, and the window

- **Decision**: a `Displays` singleton holds the applied, pending and
  previous layouts, the selection, the countdown and the status line. The
  card is a full-screen overlay window per screen (`Variants` over
  `Quickshell.screens`), visible when `Rail.openTarget === "displays"`
  and `Rail.showsOn(name)`, with a `FloatingCard` in the middle.
- **Rationale**: the popups already work this way, and it gives FR-003
  (Esc, click outside), one popup at a time, and the pointer's display for
  an IPC open, with no new mechanism. `Rail.showsOn` already returns true
  for every screen when the remembered output is gone, so the keep
  question stays visible after the card's display turns off (FR-017). The
  window on that display is destroyed with its screen; state in a
  singleton is not. `RailPopup` itself is not used: it grows from a rail
  island, and mock A is a free card.
- **Alternatives**: state in the card component (lost when its screen
  goes); a separate `FloatingWindow` (Mango would tile it).
- **Note**: the spec says "focused display"; the shell's rule for IPC
  opens is the display under the pointer (specs/014, rail-ipc). The card
  follows the shell's rule.

## R4. Geometry as a tested module

- **Decision**: `displayLayout.mjs`, a plain ECMAScript module with no
  QML types: logical size, snap while dragging, settle after a change,
  normalise to 0,0, and the `wlr-randr` argument list. QML imports it;
  `mango-display-layout-test` runs `displayLayout.test.mjs` against it
  with Node at build time, wired like `qmlCheck`.
- **Rationale**: FR-009 and SC-005 (no overlap, all connected) are the
  part most likely to be wrong, and the only part that can be checked
  without displays. Constitution principle I asks for exactly this. One
  file for both users means the test checks what ships.
- **Alternatives**: functions inside the singleton (not testable outside
  Quickshell); a `.js` file with `.pragma library` (Node cannot parse the
  pragma; kept as the fallback, with the test stripping that line, if
  Quickshell or qmllint refuses `.mjs`).

## R5. Logical size and settling

- **Decision**: logical size is `floor(mode / scale)`, width and height
  swapped for the 90 and 270 transforms. Settle: for the changed display,
  list every position where one of its edges touches an edge of another
  enabled display with some shared length, drop those that overlap any
  display, take the one nearest to where it is. Then repeat for any
  display that lost its last neighbour.
- **Rationale**: wlroots computes the effective resolution by integer
  truncation, and positions are integers, so a rounded-up size would
  leave a one-pixel overlap. Candidate positions come only from the other
  displays' edges, so the search is small and exact.
- **To verify**: quickstart D9 checks at scale 1.25 and 1.5 that the
  neighbour's position in `wlr-randr --json` matches the card.
- **Alternatives**: physics-style push-apart (not deterministic);
  refusing the drop (the user has to hunt for a legal place).

## R6. Which display setup matches

- **Decision**: `kanshictl status`, whose output on the laptop is
  `Current profile: undocked`. The name after the colon is shown; the
  generated `undocked` profile is shown as "Undocked". No profile line
  means "No saved setup matches".
- **Rationale**: kanshi is what matches (specs/011); asking it avoids a
  second matcher that could disagree.
- **To verify**: the exact output with an unknown display connected
  (quickstart D15); only one display was available during planning.
- **Alternatives**: match in QML against the setups written into
  `Config.qml` at build time (duplicates kanshi's criteria rules).

## R7. Copy as setup

- **Decision**: `mango-display-setup` gains `--copy`, which sends its
  output to `wl-copy` instead of the terminal. The card runs
  `mango-display-setup --copy`; the entry is named `new-setup` for the
  user to rename.
- **Rationale**: the script is the single definition of the entry format
  (spec, Assumptions). It reads the real state, so it describes the
  applied layout by construction (FR-023, US4 scenario 2).
- **Alternatives**: build the entry in QML (a second definition of the
  format); a name prompt in the card (one more control for a rare step).

## R8. Adaptive sync cannot be detected (spec changed)

- **Finding**: the protocol and `wlr-randr --json` report whether
  adaptive sync is on, not whether the display can do it.
- **Decision**: the switch is shown for every enabled display. The
  argument is sent only when the user changed it. A display that cannot
  do it makes the compositor refuse the change, which FR-018 already
  covers. FR-013 and US3 scenario 6 in the spec were reworded to this.
- **Alternatives**: hide the switch always (drops a wdisplays function,
  against SC-007); parse EDID (large, and not what the compositor uses).

## R9. Flipped transforms

- **Decision**: the card offers the four rotations only (FR-012). A
  display that is flipped keeps its flip: the rotation choice changes the
  angle part of `flipped-N` and leaves the flip.
- **Rationale**: none of the user's displays is mirrored; silently
  un-flipping one on Apply would be a change nobody asked for.

## R10. Launcher entry and command

- **Decision**: a Home Manager desktop entry "Displays" whose command is
  `qs -c mango ipc call displays toggle` by store path, and an
  `IpcHandler` with target `displays`. No default key binding.
- **Rationale**: the launcher lists desktop entries (`Apps.qml`), so this
  needs no launcher change, and it takes the place wdisplays had there
  (FR-001, FR-025).
- **Alternatives**: a built-in launcher row (special case in `Apps.qml`);
  a rail icon (spec, Assumptions: not wanted).

## R11. kanshi and the lid do not fight an Apply

- **Finding**: kanshi applies a profile when the set of connected
  displays changes, on `kanshictl reload`, and at start. A change made by
  another client leaves the set as it is, which is why wdisplays works
  beside kanshi today (specs/011 quickstart, step 2). `mango-lid-sync`
  runs from kanshi's `exec` and the lid switch only.
- **Decision**: nothing to do. A kept layout lasts until the next hotplug,
  `mango-reload` or lid open (spec, Edge Cases).
