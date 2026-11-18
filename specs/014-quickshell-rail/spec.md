# Feature Specification: Quickshell Rail

**Feature Branch**: `014-quickshell-rail`

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Replace waybar with a Quickshell-drawn top bar
(the Mango rail) in modules/mango. The rail's three islands (workspaces left;
clock centre; tray drawer, Claude usage ring, and controls group with
phone/network/sound/battery right) are drawn by the existing Quickshell config
instead of waybar, keeping the current look and behaviour from specs 012 and
013 (dots with numbered active pill, hide empty tags, click to activate, urgent
ring, clock date/time, usage ring with tooltip and hiding when no data, phone
icon when a paired phone is reachable, tray drawer with click-to-reveal and app
menus, battery warning style, hover tint, accent state while a popup is open,
one bar per monitor). Workspaces come from mango via `mmsg watch all-tags`.
Popups anchor to their capsule directly. Remove waybar, the mango-rail-module
script, the SVG usage rings, and the waybar signal/runtime-file IPC. Supersedes
spec 012 decision R2 (rail stays waybar)."

This feature builds on `specs/012-mango-rail-bar` and
`specs/013-mango-islands-shell`. Their look and behaviour stay as they are; only
the program that draws the **Rail** changes. It reverses spec 012's research
decision R2, which kept the rail in waybar because a Quickshell rail needed a
hand-written workspace source.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Same rail, one program (Priority: P1)

The user logs in to Mango and sees the same three islands along the top edge
as today: workspaces on the left, date and clock in the middle, status on the
right. Everything they click does what it did before. The difference is not
visible: the rail and its popups are now one program, so there is no second
bar process to start, crash or fall out of step with the popups.

**Why this priority**: it is the whole feature. Without it, waybar stays.

**Independent Test**: log in to Mango with this change, compare the rail
side by side with a screenshot taken before it, then use every rail item
once.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** the user looks at the top edge,
   **Then** they see the three islands with the same position, size, gaps,
   colours, fonts and icons as before the change.
2. **Given** a Mango session, **When** the user lists running processes,
   **Then** no waybar process is running.
3. **Given** two monitors are connected, **When** the user looks at each,
   **Then** each monitor has its own rail, showing that monitor's tags.
4. **Given** a monitor is plugged in or out during the session, **Then** a
   rail appears on or disappears from it without restarting anything.
5. **Given** the user hovers any clickable rail item, **Then** it shows the
   same hover tint as the popups' clickable elements.

---

### User Story 2 - Workspaces island (Priority: P1)

The left island shows one dot per occupied tag on that monitor and a numbered
pill for the active tag. Clicking a dot switches to that tag. A tag that wants
attention gets a ring.

**Why this priority**: workspaces are the rail's most-used item and the one
part with no ready-made data source; the rail is not usable without it.

**Independent Test**: open windows on tags 1, 3 and 5, switch between them by
keyboard and by click, and trigger an urgent window on another tag.

**Acceptance Scenarios**:

1. **Given** windows on tags 1, 3 and 5 and tag 3 active, **Then** the island
   shows a dot, a pill reading "3", and a dot, in that order; empty tags are
   not shown.
2. **Given** the user clicks a dot, **Then** that tag becomes active on that
   monitor and the pill moves to it.
3. **Given** the user switches tag by keyboard, **Then** the island follows
   within the same moment, with no visible lag.
4. **Given** a window on an inactive tag requests attention, **Then** that
   tag's dot gets a ring; it clears once the tag is visited.
5. **Given** the last window on a tag closes, **Then** its dot disappears.

---

### User Story 3 - Status island and popups (Priority: P1)

The right island holds the tray drawer, the Claude usage ring, and the
controls capsule (phone, network, sound, battery). Each opens what it opened
before, and popups drop from the capsule that opened it on the same monitor.

**Why this priority**: the right island carries every popup entry point; the
rail is not a replacement without it.

**Independent Test**: click each item on the right island and the clock on
each monitor, check where each popup appears, and use a tray app's menu.

**Acceptance Scenarios**:

1. **Given** the user clicks the clock, **Then** the calendar opens under the
   clock island and the clock shows its open state until it closes.
2. **Given** usage data exists, **Then** the usage ring shows the session
   percentage, its tooltip shows session and weekly percentages, and clicking
   it opens the usage popup with the ring in its filled open state.
3. **Given** no usage data exists, **Then** the usage ring is not shown and
   leaves no gap.
4. **Given** the user clicks the phone, network, sound or battery icon,
   **Then** quick controls open, aligned to the right island.
5. **Given** a paired phone becomes reachable or unreachable, **Then** the
   phone icon appears or disappears within a few seconds.
6. **Given** tray apps are running, **When** the user clicks the chevron,
   **Then** the tray icons are revealed; left click activates an app and
   right click opens its menu, whose entries work.
7. **Given** no tray apps are running, **Then** the tray drawer takes no
   space.
8. **Given** the battery is at or below 15 % and discharging, **Then** the
   battery icon shows the accent-filled warning style.
9. **Given** the user hovers the network, sound, battery or usage item,
   **Then** a tooltip shows the same text as before (network name and
   strength, sink and volume, charge and time left, usage percentages).
10. **Given** a popup is open, **When** the user clicks the item that opened
    it, presses Escape, or clicks outside, **Then** the popup closes and the
    open state clears.

---

### Edge Cases

- The compositor's workspace stream stops or restarts (e.g. after a Mango
  reload): the workspaces island reconnects on its own and shows the current
  state, without a session restart.
- The Quickshell config is rebuilt while the session runs: the rail comes
  back with the new config, as the popups do today.
- Usage data is older than 30 minutes: the ring keeps its last value, as
  today.
- Battery missing (desktop machine): no battery icon and no gap.
- No network: the disconnected icon in the dim colour, as today. Sound muted:
  the muted icon in the dim colour.
- A tray app has no menu: right click does nothing.
- A tray icon has no symbolic variant: it is drawn as is, at the same size.
- Two popups requested at once: only one is open at a time, as today.
- A fullscreen window: the rail stays where it is today relative to
  fullscreen windows.

## Requirements *(mandatory)*

### Functional Requirements

**Rail**

- **FR-001**: The rail MUST be drawn by the session's existing Quickshell
  config; waybar MUST NOT be installed or started by the Mango module.
- **FR-002**: Every monitor MUST have its own rail, added and removed with
  the monitor.
- **FR-003**: The rail MUST keep the islands look from spec 013: three
  capsules (left, centre, right) on the top edge with the same height,
  margins, gaps, radii, palette, fonts and icon set.
- **FR-004**: The rail MUST reserve its space so windows do not go under it,
  as today.
- **FR-005**: Every clickable rail item MUST use the hover tint the popups
  use, with the stronger tint on the dim workspace dots kept.

**Workspaces**

- **FR-006**: The left island MUST show the monitor's occupied tags only: a
  dot for each inactive one, a numbered pill for the active one, in tag
  order.
- **FR-007**: Clicking a tag MUST make it the active tag on that monitor.
- **FR-008**: A tag with an urgent window MUST show a ring until visited.
- **FR-009**: The island MUST follow tag changes as they happen, not by
  polling, and MUST reconnect if the compositor's stream ends.

**Centre and status**

- **FR-010**: The clock MUST show the dim date before the bold time, and
  open the calendar on click.
- **FR-011**: The usage item MUST show a ring filled to the session
  percentage in 5 % steps or finer, hide when there is no usage data, show
  session and weekly percentages in its tooltip, and open the usage popup.
- **FR-012**: The tray MUST sit in a drawer revealed by a chevron click, use
  the symbolic icon variant where one exists, and support activate and
  context menu for each item.
- **FR-013**: The controls capsule MUST hold the phone icon (only while a
  paired phone is reachable and KDE Connect is enabled), network, sound and
  battery icons, each opening quick controls, with the states and tooltips
  listed in User Story 3.

**Popups**

- **FR-014**: Each popup MUST open on the monitor whose rail was clicked,
  positioned from the opening capsule itself rather than from fixed offsets.
- **FR-015**: The item that opened a popup MUST show its open state while the
  popup is open, as defined in spec 013 FR-006.
- **FR-016**: The popups' IPC entry points (`qs -c mango ipc call <target>
  toggle`) MUST keep working, so key bindings and scripts that use them are
  unaffected.

**Removal**

- **FR-017**: The waybar configuration and style, the rail module script,
  the pre-rendered usage ring images, the signals sent to waybar, and the
  runtime file that carried the open popup MUST be removed.
- **FR-018**: The **Rail** glossary entry MUST be updated to say Quickshell
  draws it, and spec 012's decision R2 MUST be marked superseded by this
  spec.

### Key Entities

- **Tag state**: per monitor — which tags are occupied, which is active,
  which are urgent.
- **Rail**: one per monitor — the three islands and the currently open popup
  target, if any.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Side by side with a screenshot from before the change, a
  reviewer finds no difference in the rail's layout, colours or icons at
  normal viewing distance.
- **SC-002**: Every rail interaction listed in User Stories 1 to 3 works on
  first try on both the laptop panel and an external monitor.
- **SC-003**: A tag switch shows on the rail within 100 ms, as perceived by
  the user: no visible delay between the window change and the pill moving.
- **SC-004**: The session runs one shell process for rail, popups and
  notifications, instead of two.
- **SC-005**: The Mango module shrinks: the replaced waybar config, rail
  script and ring images add up to more lines than the new rail code adds.
- **SC-006**: After a Mango reload or a Quickshell restart, the rail shows
  the correct state within 2 seconds without user action.

## Assumptions

- The look is spec 013's as it stands at commit `b1b7772`, including the
  hover tints from that commit; this spec adds no visual change.
- Quick controls keep their shared `raised` capsule; spec 013 FR-006's
  reason for it (waybar cannot mark a group open) goes away, but changing
  that look is out of scope.
- The compositor's IPC offers a live stream of tag state per monitor
  (`mmsg watch all-tags`, checked in nixpkgs `mangowc`); the pinned Mango
  build is assumed to offer the same. If it does not, planning picks the
  closest stream it does offer.
- Tag state on the compositor side is the source of truth; the rail does not
  remember tags itself.
- Tooltips may look slightly different from waybar's GTK tooltips but use the
  island palette.
- The phone, usage and notification parts already in Quickshell (spec 013)
  are reused as they are.
- Only NixOS machines running the Mango module are affected; other sessions
  never used this rail.
