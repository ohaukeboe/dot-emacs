# Feature Specification: Display Layout Card

**Feature Branch**: `018-display-layout-card`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "A" (mock A, the floating card, of the three
mocks for a Quickshell replacement of wdisplays)

Builds on specs/011-mango-docking-essentials, which chose wdisplays as the
ad-hoc display tool and kanshi for known display setups. This feature
replaces wdisplays with a card drawn by the Mango shell, in the shell's own
design system. The mock is kept beside this spec as
`mocks/display-mocks.html` (section "Mock A").

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Arrange the displays by dragging (Priority: P1)

The user plugs in a display that no display setup knows, so it lands right
of the panel although it stands to the left on the desk. They open the
displays card, see every connected display as a rectangle drawn to scale,
drag the new one to the left of the panel, and apply. The pointer now
crosses between the displays the way the desk is laid out.

**Why this priority**: this is the reason to open wdisplays at all. Without
it the card has no use.

**Independent Test**: with two displays connected, open the card, drag one
display to the other side of the other, apply and keep. Move the pointer
across the shared edge: it crosses where the card showed it.

**Acceptance Scenarios**:

1. **Given** two enabled displays, **When** the user opens the card,
   **Then** each display is drawn as a rectangle whose size and position
   match its real size and position, with its name on it.
2. **Given** the card is open, **When** the user drags a display near an
   edge of another, **Then** it snaps so the two edges touch, and it can
   still slide along that edge.
3. **Given** a display is dropped overlapping another or away from all
   others, **When** the user releases it, **Then** it settles at the
   nearest place where it touches another display without overlapping.
4. **Given** the user has moved a display, **When** they apply, **Then**
   all displays take the shown positions in one step.
5. **Given** nothing was changed, **When** the user looks at the card,
   **Then** Apply is shown as unavailable and pressing Enter does nothing.

---

### User Story 2 - A bad change undoes itself (Priority: P1)

The user applies a change that leaves the screen unreadable, for example a
mode the display cannot show or the only visible display turned off. They
cannot see the card to undo it. After ten seconds without an answer the
previous layout returns on its own.

**Why this priority**: without this, one wrong press can leave the session
unusable until a reboot or a blind key sequence. It must ship with the
first version that can apply anything.

**Independent Test**: change a display's resolution, apply, and do not
answer. After ten seconds every display has its earlier mode, position,
scale, rotation and on/off state.

**Acceptance Scenarios**:

1. **Given** a change was applied, **When** the card asks whether to keep
   it, **Then** it shows the seconds left, counting down from ten.
2. **Given** the question is shown, **When** the user chooses Keep or
   presses Enter, **Then** the new layout stays and the card returns to its
   normal state.
3. **Given** the question is shown, **When** the user chooses Revert,
   presses Esc, or the time runs out, **Then** every display returns to the
   state it had before Apply, and the card shows that state.
4. **Given** the display the card is on was turned off by the change,
   **When** the change is applied, **Then** the question appears on a
   display that is still on.

---

### User Story 3 - Change one display's settings (Priority: P2)

The user selects a display in the card and changes its resolution, refresh
rate, scale or rotation, or turns it off. The rectangle changes shape at
once to show the result, and nothing happens to the real display until
Apply.

**Why this priority**: the other half of wdisplays. Used less often than
arranging, because the defaults are usually right, but needed for a
projector, a rotated monitor or a high-density panel.

**Independent Test**: select the panel, set scale to 1.5, apply and keep.
Windows on the panel are drawn larger, and the card shows 1.5 when opened
again.

**Acceptance Scenarios**:

1. **Given** a display is selected, **When** the user looks below the
   layout, **Then** its name, connector, and current resolution, refresh
   rate, scale, rotation and on/off state are shown.
2. **Given** a display is selected, **When** the user opens the resolution
   choice, **Then** only resolutions that display reports are offered, and
   the refresh rates offered are those of the chosen resolution.
3. **Given** the user picks another scale or rotation, **When** the choice
   is made, **Then** the rectangle takes the new size or orientation and
   the neighbours stay touching it.
4. **Given** a display is turned off in the card, **When** the user looks
   at the layout, **Then** it is drawn as an outline, apart from the
   enabled displays' arrangement, and can be selected and turned on again.
5. **Given** only one display is on, **When** the user tries to turn it
   off, **Then** the card refuses and says one display must stay on.
6. **Given** an enabled display is selected, **When** the user turns
   adaptive sync on and applies, **Then** it is on, or, for a display that
   cannot do it, the change is refused and nothing changes.

---

### User Story 4 - Keep the layout as a display setup (Priority: P3)

The layout is right and the user wants it every time these displays are
connected. They press "Copy as setup", paste into
`machines/machines.nix`, and rebuild. From then on the layout is applied on
hotplug.

**Why this priority**: `mango-display-setup` already prints this in a
terminal. The button saves a step and makes it clear that the card itself
does not remember anything.

**Independent Test**: arrange two displays, keep, press "Copy as setup",
paste into `machines/machines.nix`: the configuration evaluates, and after
a rebuild a replug restores the same layout.

**Acceptance Scenarios**:

1. **Given** an applied layout, **When** the user presses "Copy as setup",
   **Then** the clipboard holds a display setup entry that describes every
   connected display as it is now, and the card confirms the copy.
2. **Given** changes that are not applied yet, **When** the user presses
   "Copy as setup", **Then** the copied entry describes the applied layout,
   not the pending one, and the card says so.
3. **Given** the connected displays match a declared display setup,
   **When** the card opens, **Then** it shows that setup's name; otherwise
   it says that no saved setup matches.

---

### Edge Cases

- A display is plugged in or removed while the card is open: the card
  shows the new set of displays and drops pending changes, with a line
  that says why.
- A display is plugged in or removed during the keep question: the
  question ends and the layout is not reverted, because the earlier state
  no longer fits the connected displays.
- The compositor refuses the change (for example a mode the cable cannot
  carry): nothing is changed, the card stays open with the pending values
  and says the change was refused.
- Only one display is connected: the card still opens and shows its
  settings; there is nothing to drag.
- Three or more displays: all are drawn, and the layout scales down so
  every one fits in the card.
- A display with a very long list of resolutions: the list scrolls inside
  the card, the card does not grow past the screen.
- A display reports no make or model: the connector name is its label.
- The card is closed with pending changes: they are dropped; nothing was
  applied.
- The card is closed during the keep question: the layout reverts, as if
  the time ran out.
- A kept layout is later replaced when kanshi applies a display setup
  again (hotplug, `mango-reload`, lid opened): expected, and the reason
  the card offers "Copy as setup".
- The lid is closed, so the panel is off by `mango-lid-sync`: the panel is
  shown as off, and turning it on in the card is allowed.

## Requirements *(mandatory)*

### Functional Requirements

**Opening and closing**

- **FR-001**: The shell MUST offer a displays card that opens from the
  launcher (as "Displays") and from a command, so a key can be bound to it.
- **FR-002**: The card MUST open centred on the focused display, over the
  windows, and take keyboard focus.
- **FR-003**: Esc and a click outside the card MUST close it. Closing MUST
  drop pending changes and MUST NOT change any display, except as FR-016
  says.
- **FR-004**: The card MUST be built from the shell's design system
  (`modules/mango/quickshell/README.md`): its tokens and existing controls.

**Layout**

- **FR-005**: The card MUST draw every connected display as a rectangle,
  to one common scale, at its position in the layout, labelled with its
  name. The size drawn MUST be the size after scale and rotation.
- **FR-006**: The layout MUST always fit inside the card's layout area,
  whatever the number and size of displays.
- **FR-007**: Exactly one display MUST be selected whenever the card is
  open; clicking a display or pressing Tab or Shift+Tab selects one. The
  selected display MUST be visibly marked.
- **FR-008**: The user MUST be able to drag an enabled display. While
  dragging, it MUST snap to the edges and corners of other enabled
  displays.
- **FR-009**: After every drop and every change of scale, rotation,
  resolution or on/off state, the enabled displays MUST form one connected
  arrangement with no overlap: each enabled display touches at least one
  other along an edge when more than one is on. The card MUST move a
  display to the nearest such place when a change breaks this.
- **FR-010**: Displays that are off MUST be drawn as outlines, apart from
  the arrangement, and MUST NOT be draggable.

**Settings of the selected display**

- **FR-011**: For the selected display the card MUST show and let the user
  change: on/off, resolution, refresh rate, scale and rotation. Resolutions
  and refresh rates offered MUST be only those the display reports.
- **FR-012**: Scale MUST offer 1, 1.25, 1.5 and 2, plus the current value
  when it is none of these. Rotation MUST offer 0, 90, 180 and 270 degrees.
- **FR-013**: The card MUST show an adaptive sync switch for every
  enabled display. Whether a display can do it is not known beforehand
  (research R8); one that cannot refuses the change, as FR-018 says.
- **FR-014**: The card MUST refuse to turn off the last enabled display
  and say why.

**Apply, keep, revert**

- **FR-015**: No display MUST change before Apply. Apply (the button or
  Enter) MUST change all displays to the shown state in one step, so no
  half-applied layout is ever visible. Apply MUST be unavailable when
  nothing is pending.
- **FR-016**: After a successful Apply the card MUST ask whether to keep
  the layout, with a visible countdown from ten seconds. Keep or Enter
  keeps it. Revert, Esc, closing the card, or the end of the countdown
  MUST restore every display's state from before Apply.
- **FR-017**: The keep question MUST be visible on an enabled display,
  also when the change turned off the display the card was on.
- **FR-018**: When the change is refused, the card MUST leave every
  display as it was, keep the pending values, and say that the change was
  refused. Replaced by specs/019-honest-refresh-rate, FR-002 and FR-003:
  the card shows the real state and drops the pending values.
- **FR-019**: The top-left corner of the applied layout MUST be at 0,0;
  the card shifts the whole arrangement to make it so.

**Staying in step**

- **FR-020**: The card MUST show the real state each time it opens and
  after each Apply, Keep and Revert.
- **FR-021**: When a display is connected or removed while the card is
  open, the card MUST show the new set, drop pending changes and say so.
  During the keep question it MUST end the question without reverting.

**Display setups**

- **FR-022**: The card MUST show the name of the declared display setup
  that the connected displays match, or that none matches.
- **FR-023**: "Copy as setup" MUST put on the clipboard one display setup
  entry for the applied layout, in the form `machines/machines.nix`
  takes, identical to what `mango-display-setup` prints, and confirm the
  copy in the card.
- **FR-024**: The card MUST NOT store a layout itself. Lasting layouts are
  display setups only (specs/011).

**Replacing wdisplays**

- **FR-025**: wdisplays MUST be removed from the Mango session's packages
  in the same change that adds the card, and
  specs/011-mango-docking-essentials' quickstart step that names wdisplays
  MUST point to the card.
- **FR-026**: With the Mango module disabled, nothing of this feature MUST
  be installed (constitution, principle V).
- **FR-027**: Every program the card runs MUST be referenced by its store
  path, so a missing one fails the build (constitution, principle I).

### Key Entities

- **Display**: one connected output. Has a connector name, make, model and
  serial (any may be missing), the resolutions and refresh rates it
  reports, and its state: on/off, resolution, refresh rate, position,
  scale, rotation, adaptive sync.
- **Layout**: the state of all connected displays together. The card holds
  three: the applied layout (what is real), the pending layout (what the
  card shows), and during the keep question the previous layout (what
  Revert restores).
- **Display setup**: as in `GLOSSARY.md`: a known combination of displays
  with each one's state, declared in the machine configuration and applied
  by kanshi. The card reads its name and can produce one; it never writes
  one.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With two displays connected, the user moves one to the other
  side and has it applied and kept in under 20 seconds from opening the
  card.
- **SC-002**: The card shows the current layout within one second of
  being asked to open.
- **SC-003**: An unanswered change is fully undone between 10 and 11
  seconds after Apply, in every case tried: position, resolution, scale,
  rotation, and a display turned off.
- **SC-004**: No sequence of actions in the card leaves the session with
  every display off.
- **SC-005**: Every layout the card can apply has no overlapping displays
  and no display the pointer cannot reach.
- **SC-006**: A copied display setup evaluates without edits when pasted
  into the machine configuration, and after a rebuild restores the same
  layout on replug.
- **SC-007**: Everything the user did with wdisplays (position, resolution,
  refresh rate, scale, rotation, on/off, adaptive sync) can be done in the
  card, and wdisplays is no longer installed.
- **SC-008**: The card is not told apart from the shell's other cards by
  colour, radius, type or motion when shown beside them.

## Assumptions

- "A" means mock A, the floating card, as shown in
  `mocks/display-mocks.html`. Mocks B and C are not part of this feature.
- The card replaces wdisplays rather than living beside it; the user asked
  for a Quickshell version of what wdisplays gives them.
- Display setups stay the only lasting store (specs/011). A layout kept in
  the card lasts until kanshi applies a setup again. This matches wdisplays
  today and is not a defect of the card.
- Ten seconds is the revert time, as in the mock and common in display
  settings elsewhere.
- Positioning is by pointer. The keyboard selects a display, applies,
  keeps, reverts and closes, and works the settings controls; moving a
  display with keys is out of scope.
- Enabled displays always touch. Free gaps between displays are out of
  scope: they leave a display the pointer cannot reach and have no use in
  this setup.
- Mirroring one display on another, a live picture of each display inside
  its rectangle, custom resolutions and fractional scales other than the
  listed ones are out of scope.
- The card appears on one display, the focused one, not on all.
- No rail icon is added; the launcher entry and a bindable command are
  enough for a tool used a few times a month.
- Mango keeps implementing the output management protocol that wdisplays,
  kanshi and `wlr-randr` already use (specs/011, research R1), and
  `mango-display-setup` stays the single definition of the display setup
  entry format.
