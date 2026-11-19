# Research: Honest Refresh Rate

Measured on the laptop in its dock, 2026-11-18: Odyssey G80SD on `DP-7`
at 3840×2160, 59.997 Hz; ASUS PB278 on `DP-5`; panel `eDP-1`. Mango
0.18.5, wlroots 0.20, wlr-randr 0.5.0.

## R1. The failing change is refused, not ignored

- **Finding**: `wlr-randr --output DP-7 --mode 3840x2160@120.000000Hz`
  as a dry run prints `failed to apply configuration` and exits 1. The
  card's Apply runs the same request, so it also exits 1, and the card
  takes the path of specs/018 FR-018: every display is left alone, the
  pending values stay, the header says "The change was refused".
- **Conclusion**: nothing is "accepted and not made". The card shows
  120 Hz after the failure because FR-018 of specs/018 says to keep the
  pending values. That rule is the defect.
- **Decision**: after every Apply, refused or not, read the real state
  and show it. Pending values are dropped on a refusal.
- **Alternatives**: keep pending values and only mark them as not applied
  (what the card does now; the user read the choice as the state).

## R2. Unusable rates can be known beforehand

- **Finding**: `wlr-randr --dryrun` sends the protocol's test request.
  Mango answers it with `wlr_output_test_state`
  (`src/manage/monitor.c`, `output_manager_apply_or_test`), which asks
  the kernel whether the mode can be set and commits nothing. Results
  for `DP-7`, state unchanged afterwards:

  | Mode                  | Dry run | Time   |
  |-----------------------|---------|--------|
  | 3840×2160 at 120 Hz   | fails   | 537 ms |
  | 3840×2160 at 119.88   | fails   | 285 ms |
  | 3840×2160 at 60 Hz    | passes  | 327 ms |
  | 3840×2160 at 59.94    | passes  | 332 ms |
  | 3840×2160 at 30 Hz    | passes  | 357 ms |
  | 2560×1440 at 239.96   | fails   | 489 ms |
  | 2560×1440 at 120 Hz   | passes  | 478 ms |
  | 1920×1080 at 239.82   | passes  | 480 ms |

  Every tested mode of `DP-5` and `eDP-1` passes. The failing modes are
  the three with the highest data rate, which fits a link that cannot
  carry them.
- **Decision**: withdrawn, see R5. Story 2 was built on this and removed
  the same day.
- **Alternatives**: read the link's capacity from the kernel and compute
  (no stable interface, and the kernel's own check is what decides);
  parse EDID (lists what the monitor can do, not what the link carries,
  which is the list that is wrong today).

## R3. A refused change may be half made

- **Finding**: `output_manager_apply_or_test` commits display by
  display and answers "failed" if any commit failed. Displays before the
  failing one keep their new state. The contract of specs/018 ("any
  other exit: nothing changed") is wrong for Mango.
- **Decision**: the exit code decides nothing about state. After every
  Apply the card reads the real state and compares it with the layout
  from before Apply: no difference means nothing to keep; any difference
  starts the keep question, so Revert can undo the half that was made
  (FR-004, FR-005).
- **Alternatives**: revert at once on a non-zero exit (hides from the
  user what happened; a taken position change would be undone with no
  question).

## R4. When and what to probe (void, see R5)

- **Decision**: probe the rates of the selected display's shown
  resolution, except the one in use, one dry run at a time. Start when
  the card is idle and the selection, the shown resolution or the applied
  layout changes. Each dry run changes only that display's mode on top of
  the applied layout: `wlr-randr --output <name> --mode <mode> --dryrun`.
  Results are held per display and mode while the card is open and
  dropped when the applied layout changes or the card closes (FR-009).
- **Rationale**: a dry run takes 0.2 to 0.8 s. The Odyssey has 37 modes;
  all displays together about 100, so probing everything on open would
  take close to a minute. One resolution has at most seven rates: about
  2 s, after which the choice is right. Rates are offered until known
  bad (FR-007), so the card opens as fast as before (specs/018 SC-002).
- **Limit**: the answer holds for the applied layout. A rate that fails
  only because another display uses the shared link stays hidden until
  that display is changed and applied (spec, Edge Cases). Probing on top
  of the pending layout would lift this, at the price of a new probe
  round for every edit of any display. Not done.
- **Alternatives**: probe every mode on open (too slow); probe only at
  Apply (that is story 1 alone); probe resolutions too (a resolution
  whose every rate fails is rare, and story 1 covers it).

## R5. A dry run's side effects

- **Finding**: in test mode Mango still clears two flags on each monitor
  (`only_sleep`, `vrr_enable_failed`) and runs its layout-change handler
  once per request. No commit is made. The 22 dry runs of R2 left mode,
  position and scale of all three displays as they were.
- **First decision**: accept, and verify by hand that nothing flickers.
- **Result**: it flickers. With probing deployed, the Odyssey's
  background blinked between black and its colour from the moment the
  card opened. A screen recording of `DP-7` during two dry runs shows the
  background change shade at the first one. Mode, position and scale
  stay untouched, which is why R2's check missed it.
- **Decision**: no dry runs from the card. R4 is void; the probe code and
  its tests were removed. Hiding rates needs a test request that Mango
  answers without running its layout-change handler, which is a change in
  Mango, not here.

## R6. No wait is needed

- **Finding**: `wlr-randr` exits only after the compositor answered, and
  the compositor answers after its commits returned. The state read
  right after the exit is the settled one.
- **Decision**: one read after the Apply process exits. FR-006's two
  seconds are met with no timer; the card's 2 s poll (specs/018, R2)
  catches a display that changes later on its own.

## R7. What the card says

- **Decision**: one line in the header, where "The change was refused"
  is today. For each display whose mode in use differs from the mode
  asked for: "<label> cannot run at <rate> Hz here". For any other
  difference: "<label> did not take the change". With several displays
  affected: "Some displays did not take the change". The line stays
  through the keep question and until the next edit.
- **Rationale**: FR-003. "Refused" names the protocol's answer; the user
  needs the display and the rate.

## R8. Where the logic lives

- **Decision**: three pure functions in `displayLayout.mjs`, tested in
  `displayLayout.test.mjs`: the dry-run arguments for one display and
  mode; the rates to offer for a resolution, given the known-bad modes
  and the mode in use (FR-008); and the displays whose real state differs
  from the asked one, with the status line. `Displays.qml` runs the
  processes and holds the results.
- **Rationale**: constitution principle I and III; same split as
  specs/018 R4. A bug fixed here gets its guard at build time.
