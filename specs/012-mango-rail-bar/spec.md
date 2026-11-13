# Feature Specification: Mango Rail Bar

**Feature Branch**: `012-mango-rail-bar`

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Make the bar in the mango module also use a setup
that more closely matches the one from
https://github.com/denonmaryland/omarchy-dotfiles"

The reference is that repository's "Pebble Shell" bar (`omarchy/shell.json`
and the `denon.shell` and `denon.corner` plugins, plus the README
screenshots). This feature builds on the Mango session from
`specs/010-mango-wm-session` and `specs/011-mango-docking-essentials`, and
follows commit `e572cbf`, which already restyled the session as rounded cards
on a flat frame. "Also" means the bar now gets the same treatment.

### What the reference bar looks like

- A narrow vertical rail down the left edge that has the frame's colour, so
  the rail and the screen frame read as one surface with no seam.
- Top: workspaces as small dots; the active one is a taller rounded pill
  that shows its number.
- Middle: the time stacked vertically (hour, minutes, AM/PM), with a small
  weather glyph below it; clicking opens a calendar.
- Bottom: a column of small icons (tray chevron, a few app/status icons) and
  a settings glyph at the corner that opens a control drawer.
- No text status readouts (Wi-Fi name, volume %, battery %) on the rail
  itself; those live in drawers that open from the rail.
- The reference rail is frosted glass and theme-driven; the reference stack
  is Hyprland plus a custom Qt shell, neither of which this repo uses.

## Clarifications

### Session 2026-11-13

- Q: What does the corner control open? → A: A plain quick-controls popup:
  volume and brightness sliders, mic mute, Wi-Fi and Bluetooth toggles,
  power profile, and battery state (not the reference's quarter-circle arcs).
- Q: Include the reference's AI-agent usage rings? → A: No, leave them out.
- Q: Should the quick-controls popup give DE-style detail for Wi-Fi,
  Bluetooth and sound? → A: Yes, GNOME-style drill-down: each tile has an
  arrow that opens a detail page inside the same popup (network list with
  connect and password entry, Bluetooth discover/pair/connect, output and
  input device choice), with a back control to the tiles.
- Q: Per-app mixers are listed out of scope; keep that? → A: No, add them:
  the sound detail page lists each playing app with its own volume and mute.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rail that reads as part of the frame (Priority: P1)

In a Mango session the user sees a narrow rail on the left edge, in the
frame's colour, joined to the frame around the window cards. Workspaces sit
at the top as dots with the active one as a numbered pill, the time sits in
the middle as a vertical stack, and small icons sit at the bottom. No
readout on the rail is a run of text along the edge.

**Why this priority**: This is the visible "matches the reference" result.
On its own it already delivers the look the user asked for.

**Independent Test**: Log in to Mango, compare the rail against the reference
screenshots (`docs/menu-calendar.webp` in the reference repo): position,
width, sections and workspace/clock styling.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** the user looks at the left edge,
   **Then** the rail has the frame's colour and no visible border or seam
   where it meets the frame around the windows.
2. **Given** workspaces 1–9 with workspace 3 active, **When** the user looks
   at the top of the rail, **Then** occupied workspaces show as dots and
   workspace 3 shows as an accent-coloured pill with "3" in it.
3. **Given** the user clicks a workspace dot, **When** the click lands,
   **Then** that workspace becomes active.
4. **Given** any time of day, **When** the user looks at the middle of the
   rail, **Then** the time shows as a vertical stack readable without tilting
   the head.
5. **Given** the user clicks the time, **When** the click lands, **Then** a
   month calendar opens.

---

### User Story 2 - Status as icons, details on demand (Priority: P2)

Network, sound, battery and power profile show on the rail only as small
icons whose shape or fill tells the state (connected or not, muted or not,
charging or low). Clicking an icon, or the corner control, opens the place
where the user changes it.

**Why this priority**: Removing text readouts is what makes the rail narrow,
but the user must not lose access to any control the current bar offers.

**Independent Test**: With the rail in place, change Wi-Fi, volume, power
profile and power state (lock, log out, suspend, reboot, power off) using
only the rail.

**Acceptance Scenarios**:

1. **Given** Wi-Fi connected, **When** the user looks at the rail, **Then**
   a network icon shows the connected state, and hovering it shows the
   network name.
2. **Given** audio muted, **When** the user looks at the rail, **Then** the
   sound icon shows muted.
3. **Given** battery under 15 % and discharging, **When** the user looks at
   the rail, **Then** the battery icon shows a warning state in a distinct
   colour.
4. **Given** the rail, **When** the user activates the corner control,
   **Then** a quick-controls popup opens with volume and brightness sliders,
   mic mute, Wi-Fi and Bluetooth toggles, power profile and battery state.
5. **Given** the quick-controls popup, **When** the user activates the Wi-Fi
   tile's arrow, **Then** the popup shows nearby networks, and choosing a
   secured one asks for its password inside the popup.
6. **Given** the quick-controls popup, **When** the user opens the Bluetooth
   detail page, **Then** paired devices show with connect/disconnect, and a
   scan lists new devices that can be paired.
7. **Given** two apps playing sound, **When** the user opens the sound detail
   page, **Then** each app shows with its own volume slider and mute, next to
   the output and input device choice.
8. **Given** the rail, **When** the user opens the power entry, **Then** they
   can lock, log out, suspend, reboot or power off, as with the current
   power menu.

---

### User Story 3 - Tray tucked away (Priority: P3)

Tray icons from background apps (KDE Connect, network applet and the like)
do not fill the rail by default; a chevron at the bottom reveals them.

**Why this priority**: Keeps the rail calm, but the tray works today as a
plain row, so this is polish.

**Independent Test**: With three or more tray apps running, the rail shows
one chevron; activating it shows all tray icons, and each icon's menu works.

**Acceptance Scenarios**:

1. **Given** several tray apps running, **When** the user looks at the rail,
   **Then** they see a single chevron, not every tray icon.
2. **Given** the chevron, **When** the user activates it, **Then** all tray
   icons show and each opens its own menu.

---

### Edge Cases

- A docked setup with several displays: every enabled display gets its own
  rail, and each rail marks the workspace active on that display (011,
  FR-006).
- Workspace numbers 10 and up: the active pill still fits the number inside
  the rail width.
- No battery (desktop machine or battery removed): the battery icon is
  absent rather than showing an error state.
- No tray apps running: the chevron is hidden or inert, not an empty drawer.
- Session outside Mango (COSMIC on the same machine): unchanged.
- HiDPI panel at scale 2 and external display at scale 1: the rail has the
  same apparent width on both.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bar MUST be a vertical rail on the left edge of every
  enabled display in a Mango session, with the frame's background colour and
  no border between rail and frame.
- **FR-002**: The rail MUST be no wider than 32 logical pixels (the current
  bar is 40; the reference is 28).
- **FR-003**: The rail MUST have three groups: workspaces at the top, time in
  the middle, status icons and the corner control at the bottom.
- **FR-004**: Inactive occupied workspaces MUST show as dots without numbers;
  the active workspace MUST show as an accent-coloured rounded pill with its
  number. Empty workspaces other than the active one MUST NOT show.
- **FR-005**: Clicking a workspace MUST switch to it.
- **FR-006**: The time MUST show stacked vertically, one line per field, in
  the 24-hour format the session already uses (hour over minutes).
- **FR-007**: Activating the time MUST show a month calendar.
- **FR-008**: Network, sound, battery and power-profile state MUST show as
  icons only; their text detail MUST be available on hover.
- **FR-009**: Every control the current bar offers MUST stay reachable from
  the rail: volume mixer, network selection, power profile switch, tray app
  menus, and the power menu.
- **FR-010**: Battery at or below 15 % while discharging MUST change the
  battery icon to a warning colour.
- **FR-011**: Tray icons MUST be collapsed behind one chevron by default.
- **FR-012**: The corner control MUST open a quick-controls popup holding:
  output volume and display brightness sliders, mic mute, Wi-Fi and
  Bluetooth on/off toggles, the power profile switch, and battery level with
  charging state. Changing a control MUST take effect without closing the
  popup, and the popup MUST close on Escape or a click outside it.
- **FR-013**: The rail MUST use the session's existing flat palette (frame,
  card, accent) rather than introducing a second colour scheme.
- **FR-014**: The COSMIC session MUST be unaffected.
- **FR-015**: The Wi-Fi, Bluetooth and sound tiles in quick controls MUST
  each open a detail page inside the same popup, with a back control to the
  tiles. Wi-Fi: scan, list networks with signal and security, connect
  (asking for a password inline when needed) and forget. Bluetooth: list
  paired devices with connect/disconnect and battery where reported, scan,
  and pair new devices. Sound: choose the output and the input device.
- **FR-016**: The sound detail page MUST list each app currently playing or
  recording, with its own volume slider and mute.

### Key Entities

- **Rail**: The bar as a narrow strip on the left edge, joined to the frame.
- **Corner control**: The entry point at the rail's bottom corner that opens
  quick controls.
- **Frame / card**: The session's existing flat background and the window
  surfaces drawn on it (from commit `e572cbf`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Placed side by side with the reference screenshot, the rail
  matches it on all of: edge, colour continuity with the frame, three-group
  layout, dot-and-pill workspaces, stacked clock, icon-only status.
- **SC-002**: The rail takes at most 32 logical pixels of screen width,
  giving windows at least 8 more pixels than the current bar.
- **SC-003**: Each control listed in FR-009 is reachable in at most two
  clicks from the rail.
- **SC-004**: No text readout on the rail is rotated along the edge.
- **SC-005**: The rail appears on every enabled display within the time the
  current bar takes, in every display setup 011 supports.

## Assumptions

- Visual match, not a port: the reference's Hyprland-only shell, frosted
  glass and theme picker are out of scope. The rail stays flat, in line with
  the flat frame chosen in `e572cbf`.
- The 24-hour clock stays (010 spec); the reference's AM/PM line is dropped.
- Out of scope: AI-agent usage rings, the weather glyph, the search-first
  menu, the "studio" look drawer, and the reference's
  quarter-circle arc styling of the control drawer.
- The existing launcher, notifier, OSD and locker stay as they are; only the
  bar changes.
- Mango and the bar program already in use can draw a left-edge bar with
  icon fonts; if the chosen bar cannot do a piece (for example a drawer),
  planning picks the closest equivalent.
