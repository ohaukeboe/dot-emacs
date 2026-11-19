# Tasks: Honest Refresh Rate

**Input**: design documents in `specs/019-honest-refresh-rate/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/displays.md](contracts/displays.md),
[quickstart.md](quickstart.md)

**Tests**: the spec asks for none. The plan puts the new logic in the
layout module so the existing build-time test covers it (research R8,
constitution principles I and III); its tasks are T003 and T007.
Everything else is checked by `qmlCheck`, `just qs-check` and the
quickstart by hand.

**Paths**: `QS` below stands for `modules/mango/quickshell`. Edit only
the files named. No Nix file changes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no unfinished dependency)
- **[Story]**: the user story the task belongs to (US1, US2)

---

## Phase 1: Setup

- [X] T001 [P] Point specs/018 at this feature. In
  `specs/018-display-layout-card/spec.md` append to FR-018: "Replaced by
  specs/019-honest-refresh-rate, FR-002 and FR-003: the card shows the
  real state and drops the pending values." In
  `specs/018-display-layout-card/contracts/displays.md`, section
  "Applying", replace the bullet that starts "Exit 0: applied." with:
  "The exit code does not tell what changed: Mango commits display by
  display. See specs/019-honest-refresh-rate/contracts/displays.md."
  Keep lines at most 90 characters.

---

## Phase 2: Foundational

None. Both stories build on code that exists (specs/018).

---

## Phase 3: User Story 1 - The card shows the rate in use (P1) 🎯 MVP

**Goal**: after every Apply the card shows the real state, says which
display did not take the change, and asks to keep only what changed.

**Independent test**: quickstart H4, H5, H8, H9.

- [X] T002 [US1] In `QS/displayLayout.mjs` add two exported functions
  after `sameNames`, each with a one-line comment.
  `notTaken(asked, real)` → the entries of `real` whose `key(d)` (the
  existing private function) differs, as JSON, from that of the display
  with the same name in `asked`; a display missing from `asked` is not
  listed.
  `notTakenLine(asked, real)` → `""` when `notTaken` is empty;
  "Some displays did not take the change" when it has more than one
  entry; for one entry `d` with asked twin `a`: when both are enabled
  and `a.mode !== d.mode`,
  `label(d) + " cannot run at " + hz + " Hz here"` where `hz` is
  `a.modes[a.mode].refresh` rounded to at most two decimals with
  trailing zeros dropped (120.000 → "120", 119.879997 → "119.88");
  otherwise `label(d) + " did not take the change"`.
- [X] T003 [US1] In `QS/displayLayout.test.mjs` add a section
  "// notTaken" using the existing `two` layout and `L.patch`: asked
  equal to real → `[]` and `""`; asked with the Dell's `mode` set to 1
  and real unchanged → one entry named "DP-3" and the line
  "DELL U2723QE cannot run at 59.95 Hz here"; asked with the Dell's
  `x` changed → "DELL U2723QE did not take the change"; asked with both
  displays changed → "Some displays did not take the change"; asked with
  a display turned off and real still on → the "did not take the change"
  line. Run `node QS/displayLayout.test.mjs` through
  `nix-shell -p nodejs --run`; it must exit 0.
- [X] T004 [US1] In `QS/Displays.qml` make the outcome of an Apply
  depend on the state read after it, per
  [data-model.md](data-model.md), "Outcome of an Apply". Add
  `property var asked: []` and `property bool judging: false` with
  comments. In `apply()` set `asked = pending`. In `applier.onExited`:
  for `purpose === "apply"` drop the `code !== 0` early return and the
  countdown start; set `adopt = true`, `judging = true` and call
  `read()` for every exit code. The revert branch stays as it is. In
  `took(next)`, before the existing `adopt` branch, capture
  `const judge = judging; judging = false;`; after `pending = next` in
  the adopt branch, when `judge` is true: if
  `!Geo.sameNames(next, previous)` set `phase = "idle"` and
  `status = "Displays changed; layout kept"` (specs/018 FR-021); else
  set `status = Geo.notTakenLine(asked, next)` and, if
  `Geo.same(next, previous)`, `phase = "idle"`, otherwise
  `phase = "confirming"`, `secondsLeft = 10`, `countdown.restart()`.
  Then clear `asked = []`. In the reader's failure branch (`next === null`), when
  `judging` is true set `judging = false`, `phase = "idle"`. Update
  the comment above `applier` ("One call changes every display, or
  none") to say the exit code is not trusted and why (research R3).
- [X] T005 [US1] In `QS/Displays.qml` and `QS/DisplaysCard.qml` make
  the not-taken line visible and bounded. Check that the header text
  (`DisplaysCard.qml`, the `Displays.status !== "" ? Displays.status`
  binding) is shown in the confirming phase too; if the keep question
  hides it, show the line in the question's row instead, using
  `Hint`. In `Displays.qml` clear `status` in `keep()`; `revert()`
  already ends with "Reverted". `change()` already clears it on the
  next edit.

**Checkpoint**: story 1 works alone. The Odyssey's 120 Hz is still
offered, but picking it ends with 60 Hz on show and the line.

---

## Phase 4: User Story 2 - Rates known not to work are not offered (P2)

**Removed after implementation** (2026-11-18): each dry run makes the
tested display's background blink (research R5). T006 to T009 were done
and then taken out again, except `modeArg`. The tasks stay for the record.

**Goal**: the card dry-runs the rates of the shown resolution and stops
offering those that fail.

**Independent test**: quickstart H1, H2, H3, H7.

- [X] T006 [US2] In `QS/displayLayout.mjs` add four exported functions
  after `rates`, each with a one-line comment.
  `modeArg(m)` → `m.width + "x" + m.height + "@" + m.refresh + "Hz"`;
  use it in `applyArgs` in place of the same expression there.
  `probeArgs(d, index)` →
  `["--output", d.name, "--mode", modeArg(d.modes[index]), "--dryrun"]`.
  `offeredRates(d, w, h, unusable, inUse)` → `rates(d, w, h)` without
  the indexes for which `unusable` (an array of strings
  `d.name + "\n" + index`) has an entry, but "always including the
  pending mode and the mode in use": `d.mode` and `inUse` (a mode
  index or -1) are never removed.
  `probeKey(d, index)` → `d.name + "\n" + index`, used by both.
- [X] T007 [US2] In `QS/displayLayout.test.mjs` add a section
  "// probing": `probeArgs` of the panel's mode 1 equals
  `["--output", "eDP-1", "--mode", "1920x1200@60.002998Hz",
  "--dryrun"]`; `applyArgs` output is unchanged (existing cases still
  pass); `offeredRates` for the panel at 1920×1200 with nothing
  unusable equals `rates`; with mode 1 unusable and mode 0 pending →
  `[0]`; with mode 0 unusable while it is the pending mode → still
  `[0, 1]`; with mode 1 unusable while `inUse` is 1 → still `[0, 1]`;
  an unusable entry for another display's name removes nothing. Run the
  test as in T003.
- [X] T008 [US2] In `QS/Displays.qml` add the probe state and process
  per [data-model.md](data-model.md), "Unusable modes" and "Probe
  queue", and [contracts/displays.md](contracts/displays.md), "Dry run".
  Properties with comments: `property var unusable: []` (probe keys
  whose dry run failed), `property var probed: []` (probe keys done),
  `property var queue: []` (mode indexes to do, for the selected
  display), `property string probing: ""` (probe key in flight).
  `function refill()`: when `phase === "idle"` and `current` is
  enabled, take the applied twin `a` of `current` (same name in
  `applied`; return if none or not enabled), the resolution of
  `current.modes[current.mode]`, and set `queue` to
  `Geo.rates(a, w, h)` minus `a.mode` minus keys in `probed`; then
  call `next()`. `function next()`: return if `prober.running`,
  `dragging`, `phase !== "idle"` or `queue` is empty; shift the first
  index, set `probing`, set
  `prober.command = [Config.wlrRandr].concat(Geo.probeArgs(a, index))`
  and start it. A `Process { id: prober }` whose `onExited`: if
  `probing` is `""` discard; else add the key to `probed`, and to
  `unusable` when `code !== 0`, by assigning new arrays; clear
  `probing`; call `next()`. `function forget()`: empty `unusable`,
  `probed`, `queue`, set `probing = ""` (so a result in flight is
  thrown away). Call `forget()` in `took(next)` whenever
  `changed` or `hotplug` is true, before `applied = next`, and in
  `onOpenChanged` on both open and close. Call `refill()` at the end
  of `took`, from `onCurrentChanged` and from `onPhaseChanged`, and
  `next()` from `onDraggingChanged`. A dry run "changes only that
  display's mode on top of the applied layout", so always build it from
  the applied twin, never from `pending`.
- [X] T009 [US2] In `QS/DisplaysCard.qml` change `rateModes` (the
  property next to `sizes`) to
  `mode ? Geo.offeredRates(display, mode.width, mode.height,
  Displays.unusable, inUse) : []`, where `inUse` is a new
  `readonly property int` beside it: the `mode` index of the display
  with the same name in `Displays.applied` when it is enabled, else
  -1. The `Segmented` and `Chooser` below already read `rateModes`,
  so the four-rate threshold counts offered rates
  ([contracts/displays.md](contracts/displays.md), "Refresh rate
  choice"). Change nothing else in the file.

**Checkpoint**: on the Odyssey at 3840×2160 the rates 120 and 119.88 Hz
leave the choice a few seconds after it is shown.

---

## Phase 5: Polish

- [X] T010 Run `nix fmt` and revert churn in files this feature did not
  touch; run `nix flake check`; run `just qs-check`; build
  `nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'`
  for the current host so `qmlCheck` and `mango-display-layout-test`
  run. All must pass.
- [X] T011 Look at the card with the `verify-quickshell` skill: open it
  with `shell open displays ""`, take one screenshot at once and one
  after 5 s, and read both. With the Odyssey connected the second shows
  fewer rates for 3840×2160 than the first. Grep the instance's log for
  QML warnings from `Displays.qml` and `DisplaysCard.qml`: none.
- [ ] T012 Human: run [quickstart.md](quickstart.md) H1 to H9 in the
  dock and note the result of H7 (no flicker while probing) in
  [research.md](research.md), R5, in place of "To verify".

---

## Dependencies

- T001 is independent of all others.
- US1: T002 → T003 → T004 → T005.
- US2: T006 → T007 → T008 → T009. T006 edits the same file as T002, so
  do US1 first; otherwise US2 does not need US1.
- T010 and T011 need every earlier task. T012 needs a deployed build.

## Parallel opportunities

Only T001, beside anything. The rest shares two files
(`displayLayout.mjs`, `Displays.qml`) and runs in order.

## Implementation strategy

1. T001 to T005, then T010: story 1 is the MVP. The card stops lying;
   this alone closes the reported defect.
2. T006 to T009, then T010 and T011: story 2 removes the dead choices.
3. T012 by the user after a rebuild.
