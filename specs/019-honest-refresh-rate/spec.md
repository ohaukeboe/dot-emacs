# Feature Specification: Honest Refresh Rate

**Feature Branch**: `019-honest-refresh-rate`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "In the current display setup, it does not
work to set the Odyssey monitor to a higher refresh rate than 60, but the
option of it is available. If I select a higher refresh rate nothing
happens, and the display popup shows a different refresh rate than is
actually in use. Cosmic handled this by simply having the selection box
revert to the refresh rate that is actually in use instead of showing the
wrong one. If it is not possible to understand that it won't work until I
try it, fix it the same way. But if it is possible to understand that it
won't be able to drive the display at this rate, then hide the option."

Builds on specs/018-display-layout-card. That card offers every refresh
rate a display reports (FR-011 there) and, when a change is refused,
keeps the pending values on show (FR-018 there). This feature covers the
case where a display reports a rate that the current connection cannot
carry: the change is refused, the display keeps its old rate, and the
card goes on showing the rate that was asked for. FR-018 of specs/018 is
replaced by FR-002 and FR-003 here.

## Clarifications

### Session 2026-11-18

- Q: Can it be known before Apply that a rate will not work? → A: Yes.
  The session can test a change without making it, and the test fails for
  exactly the rates that fail on Apply (research R1, R2). Story 2 is
  therefore in scope.
- Q: Is the failing change accepted and ignored, or refused? → A: Refused
  (research R1). The wrong rate stayed on show because specs/018 kept the
  pending values after a refusal.
- Q: Is a test before Apply free of side effects? → A: No. Each test
  makes the tested display's background blink (research R5, seen by the
  user after the first build). Story 2 is dropped: by the user's rule,
  a rate that can only be known with a visible disturbance counts as not
  knowable beforehand. Every reported rate is offered; story 1 covers a
  rate that fails.
- Q: Does a refused change leave every display as it was? → A: No. The
  session changes displays one by one, so the displays before the failing
  one may have changed (research R3). Story 1, scenario 3 covers this.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The card shows the rate in use (Priority: P1)

The user selects the Odyssey monitor in the displays card, picks a refresh
rate above 60 Hz and applies. The monitor stays at 60 Hz. The card's
refresh rate choice goes back to 60 Hz and one line says that the display
did not take the rate that was asked for. The user is not asked to keep a
change that did not happen.

**Why this priority**: the card states something false today. A settings
card that cannot be trusted to show the real state is worse than one that
offers a choice that fails.

**Independent Test**: with the Odyssey monitor connected as it is today,
pick a rate above 60 Hz and apply. Within two seconds the refresh rate
choice and the summary line under the display's name both show 60 Hz, and
the card says the rate was not taken.

**Acceptance Scenarios**:

1. **Given** a display running at 60 Hz that reports a higher rate it
   cannot be driven at, **When** the user picks the higher rate and
   applies, **Then** the refresh rate choice returns to 60 Hz and the card
   says that the display did not take the rate.
2. **Given** that rate was the only pending change, **When** the apply
   ends, **Then** no keep question is shown and Apply is unavailable
   again, because nothing changed.
3. **Given** the user also moved the display in the same Apply, **When**
   the position is taken and the rate is not, **Then** the keep question
   is shown for the part that changed, the card shows the rate in use,
   and it says which display did not take its rate.
4. **Given** the keep question from scenario 3, **When** the user reverts
   or the time runs out, **Then** every display returns to its state from
   before Apply.
5. **Given** a display that takes the rate that was asked for, **When**
   the user applies, **Then** the card behaves as before this feature.

---

### User Story 2 - Rates known not to work are not offered (Dropped)

Dropped on 2026-11-18, see Clarifications. Kept for the record.

Where the session can tell beforehand that a display cannot be driven at
a rate it reports, the card does not offer that rate. The user sees only
choices that work.

**Why this priority**: better than a choice that fails, but only
possible if the session has this knowledge. Story 1 is the fallback that
must hold in every case, so it comes first.

**Independent Test**: with a display for which a reported rate is known
beforehand not to work, open the card and select it: that rate is absent
from the refresh rate choice, and every rate that is offered can be
applied.

**Acceptance Scenarios**:

1. **Given** a rate of the selected resolution is known beforehand not to
   work, **When** the user looks at the refresh rate choice, **Then** that
   rate is not offered.
2. **Given** nothing is known beforehand about a rate, **When** the user
   looks at the refresh rate choice, **Then** the rate is offered, and
   story 1 covers it when it fails.
3. **Given** the card is closed and opened again, or the applied layout
   changed, **When** the user looks at the refresh rate choice, **Then**
   it is found out anew which rates work: the cause may be a cable that
   was replaced or another display that was turned off.

---

### Edge Cases

- The display takes another rate than the one asked for and another than
  the one it had (for example the nearest one it can do): the card shows
  the rate in use, whatever it is, and says the asked rate was not taken.
- A resolution is not taken either: the card shows the resolution and
  rate in use, by the same rule.
- The display needs a moment to change mode, so the first look after
  Apply still shows the old rate: the card must not report a failure for
  a change that is only slow.
- The change is refused and no display changed: the card shows the real
  state and says so; pending values are dropped. This replaces FR-018 of
  specs/018.
- A rate is hidden because of what another display uses of a shared
  connection: it appears once that display is changed and applied.
- Every rate of a resolution but one is hidden by story 2: the remaining
  rate is shown as the only choice.
- The rate in use is one that story 2 would hide: it stays offered, so
  the card never shows a display with no rate selected.
- The display is unplugged between Apply and the check: the hotplug rule
  of specs/018 (FR-021 there) wins.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: After every Apply the card MUST compare each display's real
  state with the state that was asked for.
- **FR-002**: Where they differ, the card MUST show the real state in
  every place that shows it: the refresh rate choice, the resolution
  choice, the summary line and the layout.
- **FR-003**: Where they differ, the card MUST say in one line that the
  display did not take the change, naming the display when more than one
  is connected.
- **FR-004**: When nothing changed on any display, the card MUST NOT ask
  whether to keep the layout, and Apply MUST be unavailable.
- **FR-005**: When some of the change was taken, the card MUST ask whether
  to keep the layout as specs/018 says, and Revert MUST restore every
  display's state from before Apply.
- **FR-006**: The card MUST NOT report a change as not taken before the
  display had time to settle. A change that is taken within two seconds
  MUST count as taken.
- **FR-007**: The card MUST NOT test rates before Apply: a test disturbs
  the display (Clarifications). Every reported rate is offered.
- **FR-008**: The rate in use MUST always be offered and shown as
  selected.
- **FR-009**: The card MUST NOT remember failed rates or hide a rate
  because it failed.
- **FR-010**: "Copy as setup" MUST keep describing the real state
  (specs/018, FR-023), never a rate that was asked for and not taken.

### Key Entities

- **Asked layout**: the state of all displays that the last Apply asked
  for. Held only until it has been compared with the applied layout.
- **Applied layout**: as in specs/018: what is real.
- **Unusable rate**: a rate a display reports for a resolution that the
  current connection cannot carry. Either known beforehand (story 2) or
  found by trying (story 1).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Two seconds after any Apply, every value the card shows for
  every display equals the value in use, in every case tried: rate taken,
  rate not taken, rate not taken together with a change that is taken.
- **SC-002**: On the Odyssey monitor as connected today, picking a rate
  above 60 Hz and applying never leaves the card showing a rate above
  60 Hz for longer than two seconds.
- **SC-003**: A rate that was not taken never produces a keep question
  when it was the only change.
- **SC-004**: A change that is taken is never reported as not taken, in
  ten tries of each kind of change on each connected display.
- **SC-005**: Opening the card and selecting displays causes no visible
  change on any display.

## Assumptions

- The fault is that the display reports rates the present connection
  (cable, dock or port) cannot carry, and the session accepts the change
  without making it. Finding the hardware cause, or making the higher
  rates work, is out of scope.
- The user's rule decides between the stories: hide when it can be known
  beforehand, otherwise show the truth after trying. It can be known
  only by a test that makes the display blink (Clarifications), so story
  1 alone is built.
- One line in the card's header, where the card already reports refused
  changes, is enough notice. No dialog and no notification.
- Two seconds is long enough for a display to change mode, and short
  enough that the user still connects the message with the press.
- Other settings that are accepted and not made (scale, rotation,
  position, adaptive sync) get the same treatment from FR-001 to FR-005
  at no extra cost, but only refresh rate and resolution are tested.
- Display setups applied by kanshi are not checked by this feature; it
  concerns changes made in the card.
