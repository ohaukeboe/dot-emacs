# Feature Specification: Duplicate Display

**Feature Branch**: `020-duplicate-display`

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "A and B" (the combined mock, "A+B", of the
mocks for a duplicate option in the displays card: an arrangement switch for
the usual cases, and stacking on the canvas for a chosen pair)

Builds on specs/018-display-layout-card, which made the displays card, and
specs/019-honest-refresh-rate. Today the card can only extend the desktop
over the connected displays. This feature lets a display show the same
picture as another one. The mock is kept beside this spec as
`mocks/duplicate-display-mocks.html` (section "A+B").

Words used here: a display that shows another display's picture is a
**copy**; the display it shows is its **source**; a source and its copies,
drawn as one tile in the card, are a **stack**.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Duplicate for a presentation, from the keyboard (Priority: P1)

The user plugs the laptop into a projector to present. They open the
displays card, press the right arrow once to move the arrangement switch
from Extend to Duplicate, and press Enter. The projector now shows what the
panel shows. They press Enter again to keep it. No pointer was needed.

**Why this priority**: this is the common reason to duplicate, and it
happens in front of an audience. It must be quick and must work without
aiming a pointer at an unfamiliar screen.

**Independent Test**: with the panel and one external display connected and
extended, open the card, press Right, Enter, Enter. The external display
shows the panel's picture, including the pointer, and the card shows one
stack.

**Acceptance Scenarios**:

1. **Given** two or more enabled displays, **When** the card opens, **Then**
   an arrangement switch above the layout offers Extend and Duplicate, and
   the one that describes the applied layout is marked.
2. **Given** the card is open, **When** the user presses the left or right
   arrow, **Then** the switch moves one choice and the layout drawing shows
   the result at once, and no real display changes.
3. **Given** Duplicate is chosen, **When** the user looks at the layout,
   **Then** all enabled displays are drawn as one stack, labelled with every
   display in it.
4. **Given** Duplicate is pending, **When** the user applies, **Then** every
   copy shows its source's picture, and the card asks whether to keep the
   layout, as after any other Apply.
5. **Given** a copy whose shape differs from its source's, **When** the
   duplicate is applied, **Then** the copy shows the whole picture, as large
   as fits, undistorted, with black bars on the sides that are left over.
6. **Given** displays are duplicated, **When** the user chooses Extend and
   applies, **Then** every display shows its own part of the desktop again.

---

### User Story 2 - Duplicate one chosen pair among three or more displays (Priority: P2)

The user has the panel and two external displays. They want one external
display to show the same as the panel, for someone sitting opposite, and
keep the third as extra desktop. In the card they drag the one tile onto the
panel's tile. The two become a stack; the third stays beside it. They apply.

**Why this priority**: the switch cannot express this. It is rarer than the
presentation case, but it is the reason stacking exists.

**Independent Test**: with three enabled displays, drag one tile onto
another, apply and keep. The dragged display shows the other's picture; the
third still extends the desktop and the pointer crosses onto it.

**Acceptance Scenarios**:

1. **Given** three enabled displays, **When** the user drags one tile over
   the middle of another, **Then** the target is visibly marked as a place
   to drop, distinct from snapping to its edge.
2. **Given** the user drops a tile on another, **When** it is released,
   **Then** the two are drawn as one stack at the target's place and size,
   the dropped display is the copy and the target is the source, and the
   other displays close the gap so the arrangement stays connected.
3. **Given** a layout with a stack that no switch choice describes, **When**
   the user looks at the switch, **Then** no choice is marked.
4. **Given** a stack, **When** the user selects a copy in it and chooses to
   separate it, **Then** the copy becomes a tile of its own beside the
   arrangement, as a display that was just turned on does.
5. **Given** a stack, **When** the user makes another display in it the
   source, **Then** the stack takes that display's place in the pointer's
   desktop and the former source becomes a copy.
6. **Given** a hand-made stack is pending or applied, **When** the user
   picks a switch choice, **Then** the layout becomes exactly what that
   choice describes and the hand-made stack is gone.

---

### User Story 3 - Show only one side (Priority: P3)

The user docks the laptop and wants only the external displays, or unplugs
from a talk and wants only the panel while the cable is still in. The
arrangement switch has "Only panel" and "Only external" beside Extend and
Duplicate, reachable with the same arrow keys.

**Why this priority**: the card can already do this by turning displays off
one by one. The two choices only make it one step, and they complete the
set of four a user expects from other desktops.

**Independent Test**: with the panel and one external display on, open the
card, move the switch to "Only external", apply and keep. The panel is off
and the external display holds the whole desktop.

**Acceptance Scenarios**:

1. **Given** the machine has a panel and at least one external display is
   connected, **When** the card opens, **Then** the switch also offers
   "Only panel" and "Only external".
2. **Given** "Only external" is chosen, **When** the user looks at the
   layout, **Then** the panel is drawn as off and the external displays are
   extended.
3. **Given** the machine has no panel, **When** the card opens, **Then**
   the switch offers only Extend and Duplicate.
4. **Given** only one display is connected, **When** the card opens,
   **Then** the switch is not shown.

---

### Edge Cases

- A copy or its source is unplugged: the duplicate ends for that pair. A
  remaining source is an ordinary display again; a remaining copy shows its
  own desktop again. The card, if open, shows the new state and says why.
- A display is plugged in while others are duplicated: it is placed as any
  new display is. It does not join a stack on its own.
- The source is turned off (in the card, or the panel by a closed lid):
  its copies cannot show an off display. The first copy becomes the source
  and keeps the desktop; with one copy the stack simply ends.
- A copy is turned off in the card: it leaves the stack and is drawn with
  the displays that are off.
- The user tries to drop a tile on a display that is off, or on itself:
  nothing happens.
- A tile is dropped on a copy or on a stack: it joins that stack as another
  copy of the same source. A copy is never the source of another copy.
- A stack is dragged: it moves as one tile and snaps like any display.
- A tile that has copies is dropped on another display: the whole stack
  joins the target's stack.
- Windows were open on a display that becomes a copy: they move to its
  source, so none is left where it cannot be seen.
- The session is locked while displays are duplicated: every display shows
  the lock screen. A copy never shows the desktop of a locked session.
- The picture on a copy stops following its source for any reason: the
  display returns to its own desktop within a few seconds, and the card
  shows it as not duplicated the next time it reads the state.
- Revert after a duplicate was applied: every copy returns to what it was
  before Apply, and windows that moved to the source stay on the source.
- A display setup is applied again (hotplug, reload, lid opened) while
  displays are duplicated: the display setup wins and the duplicate ends,
  as any kept layout is replaced today.
- "Copy as setup" while displays are duplicated: a display setup cannot
  describe a duplicate. The copied entry describes the displays as
  extended, and the card says that the duplicate is not part of it.
- More copies or a taller layout than the shell can duplicate (plan,
  research R3: three copies, and under 8192 pixels tall): the card
  refuses the change and says why.
- The copy and the source have the same size: the picture fills the copy
  with no bars.
- A copy is rotated: it shows the source's picture upright for someone who
  looks at the rotated display.

## Requirements *(mandatory)*

### Functional Requirements

**Duplicating**

- **FR-001**: The card MUST let an enabled display show the picture of
  another enabled display. The picture on the copy MUST include the pointer
  and everything the shell draws on the source.
- **FR-002**: A copy MUST show the source's whole picture, as large as
  fits, with its proportions kept, centred, and black where the picture
  does not reach.
- **FR-003**: A source MAY have several copies. A copy MUST NOT be the
  source of another display.
- **FR-004**: A copy MUST NOT be part of the pointer's desktop: the pointer
  cannot move onto it, no window opens on it, and no keyboard focus goes to
  it.
- **FR-005**: When a display becomes a copy, the windows on it MUST move to
  its source.
- **FR-006**: A copy MUST keep its own resolution, refresh rate and
  rotation, and the card MUST let the user change them. Scale and position
  MUST NOT be offered for a copy, because the source decides them.
- **FR-007**: When a display stops being a copy, it MUST show its own
  desktop again and take a place in the arrangement by the rule specs/018
  uses for a display that is turned on.

**The arrangement switch**

- **FR-008**: With two or more connected displays, the card MUST show an
  arrangement switch between its header and the layout, with the choices
  Extend and Duplicate. On a machine with a panel and at least one external
  display connected it MUST also offer "Only panel" and "Only external".
  With one connected display the switch MUST NOT be shown.
- **FR-009**: Each choice MUST set the pending layout as follows.
  Extend: every display on, none a copy. Duplicate: every display on, one
  source, all others its copies. Only panel: the panel on, all others off.
  Only external: the panel off, all others on and none a copy.
- **FR-010**: For Duplicate the source MUST be the panel when the machine
  has one and it is not held off by a closed lid; otherwise the selected
  display.
- **FR-011**: A choice MUST change as little as it needs to: displays that
  already are as the choice describes keep their position and settings.
  Displays that leave a stack or are turned on are placed by the rule of
  FR-007.
- **FR-012**: The switch MUST mark the choice that describes the pending
  layout, and mark none when no choice does.
- **FR-013**: The left and right arrow keys MUST move the switch by one
  choice whenever the card is open in its normal state and no list of
  choices is open. With no choice marked, right picks the first and left
  the last.
- **FR-014**: A choice MUST be a pending change like any other: nothing
  real changes before Apply, and Apply is followed by the keep question.

**Stacking on the layout**

- **FR-015**: Dropping an enabled display's tile on the inner part of
  another enabled display's tile MUST make the dropped display a copy of
  the target. While the tile is held there, the target MUST be visibly
  marked. Near the target's edges, snapping as in specs/018 MUST still
  apply.
- **FR-016**: A stack MUST be drawn as one tile at the source's position
  and size, visibly different from a single display, and labelled so every
  display in it can be told. It MUST be draggable as one tile.
- **FR-017**: Every display in a stack MUST be selectable, by Tab and
  Shift+Tab and by the pointer. The settings shown MUST be those of the
  selected display, and MUST say what it duplicates or what duplicates it.
- **FR-018**: For a selected copy the card MUST offer to separate it from
  its stack, and to make it the source. Making it the source swaps the two
  roles and keeps the stack's place in the arrangement.
- **FR-019**: After every change that makes or ends a copy, the sources and
  single displays MUST still form one connected arrangement with no
  overlap, as specs/018 FR-009 requires of the enabled displays.
- **FR-020**: The card's key hint MUST name the arrow keys and dropping on
  a display.

**Apply, keep, revert, staying in step**

- **FR-021**: Which display copies which MUST be part of the layout the
  card compares, applies, keeps and reverts. A change of it alone MUST make
  Apply available.
- **FR-022**: Revert, the end of the countdown, and closing the card during
  the keep question MUST restore which display copied which, together with
  everything specs/018 FR-016 restores.
- **FR-023**: The keep question MUST be visible on a display that is in the
  pointer's desktop after the Apply, never only on a copy.
- **FR-024**: The card MUST show the real state each time it opens and
  after each Apply, Keep and Revert, including which display copies which.
- **FR-025**: When a copy can no longer show its source (the source was
  unplugged or turned off, or the picture stopped following), the display
  MUST return to its own desktop without the user doing anything, and MUST
  NOT stay black or frozen for more than 5 seconds.
- **FR-026**: When the source of a stack is turned off and copies remain,
  the first copy MUST become the source, so the desktop stays visible.
- **FR-027**: While the session is locked, a copy MUST show the lock screen
  and MUST NOT show any part of the desktop.

**Display setups and lasting state**

- **FR-028**: The card MUST NOT store a duplicate. A duplicate lasts until
  the user ends it, one of its displays goes away, a display setup is
  applied, or the session ends.
- **FR-029**: "Copy as setup" MUST describe every connected display as
  extended, and the card MUST say that the duplicate is not part of the
  copied entry when one is applied.

**Build and module rules**

- **FR-030**: New controls MUST be built from the shell's design system
  (`modules/mango/quickshell/README.md`).
- **FR-031**: With the Mango module disabled, nothing of this feature MUST
  be installed (constitution, principle V).
- **FR-032**: Every program this feature runs MUST be referenced by its
  store path, so a missing one fails the build (constitution, principle I).
- **FR-033**: The rules for stacks (FR-003, FR-009, FR-011, FR-019,
  FR-026) MUST be covered by the layout tests that run at build time.

### Key Entities

- **Display**: as in specs/018, with one more piece of state: the display
  it copies, or none.
- **Copy**: an enabled display that shows another display's picture. Keeps
  its own resolution, refresh rate and rotation; has no position or scale
  of its own; is not part of the pointer's desktop.
- **Source**: an enabled display that at least one copy shows. In every
  other way an ordinary display.
- **Stack**: a source and its copies, drawn and dragged as one tile.
- **Arrangement**: one of Extend, Duplicate, Only panel, Only external. A
  name for a layout of all connected displays, not stored anywhere: the
  switch derives it from the layout and writes a layout when one is picked.
- **Layout**: as in specs/018, now including which display copies which.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the panel and one external display connected, the user
  duplicates them and keeps the result with four key presses after opening
  the card, in under 10 seconds, without touching a pointer.
- **SC-002**: With three displays, the user makes one a copy of another by
  one drag and Apply, in under 20 seconds, and the third display still
  extends the desktop.
- **SC-003**: A change on the source (pointer movement, a new slide) is
  visible on the copy within 0.1 seconds, and video played on the source
  looks smooth on the copy.
- **SC-004**: After any Apply, Revert, unplug or failure, no display stays
  black or frozen for more than 5 seconds, and the card's drawing matches
  what the displays show the next time it is opened, in every case tried.
- **SC-005**: No window is ever left on a display that shows another
  display's picture.
- **SC-006**: A locked session never shows desktop content on any display,
  duplicated or not.
- **SC-007**: Every arrangement the switch offers, applied and then
  followed by Extend, leaves all displays on and none a copy.

## Assumptions

- Mango has no duplicate mode of its own (checked in 0.18.5). The picture
  on a copy comes from capturing the source and showing it full screen on
  the copy. A trial with `wl-mirror` on this session showed the capture
  works with the memory-copy path; the faster graphics-buffer path and the
  frame rate at 3840×2160 are not measured yet and are the main risk to
  SC-003. Planning chose the shell's own screen view instead (research
  R2) and parks the copy away from the desktop for FR-004 (research R3).
- A copy stays a connected, enabled display for the compositor. Keeping the
  pointer, windows and focus off it (FR-004, FR-005) is a requirement on
  the plan, not something Mango gives for free.
- Duplicates are not part of display setups in this feature. A display
  setup that duplicates on hotplug (for a known projector, say) would be a
  later feature; nothing here blocks it.
- Stacking a chosen pair needs a pointer. The keyboard reaches the four
  arrangements only.
- "Panel" is the laptop's built-in display, as in `GLOSSARY.md`. A machine
  without one gets Extend and Duplicate only.
- Sound is not part of this feature: where audio plays does not change when
  displays are duplicated.
- The copy's resolution is not forced to match the source's. Bars on a copy
  of another shape are accepted.
- The ten-second keep question, the one-step Apply and the honest state
  after a refused change stay as specs/018 and specs/019 define them.
- `GLOSSARY.md` gains "copy", "source" and "stack" for displays in the
  change that implements this.
