# Feature Specification: Mango Docking and Session Essentials

**Feature Branch**: `011-mango-docking-essentials`

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Let's add the recommendations from the research
report. The laptop will be docked into multiple (both known and unknown)
setups often."

The research report is `docs/mangowm-components-research.md`. This feature
builds on the Mango session from `specs/010-mango-wm-session`.

## Clarifications

### Session 2026-11-13

- Q: Default arrangement for displays that match no recorded setup? → A:
  Extend: each external display turns on at its preferred mode to the right
  of the laptop panel; the panel stays on.
- Q: Which optional extras from the report are in scope? → A: Screenshot
  annotation only. Night light, screen recording and notification history are
  out of scope.
- Q: Which known setups are recorded in this change? → A: None. The change
  ships the mechanism and a way to print the connected displays in the
  recorded-setup format; the user adds setups later, one entry each.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dock into a known setup (Priority: P1)

The user docks the laptop at a place they use regularly (home desk, office
desk). The external displays come up in the arrangement, resolution and scale
recorded for that place, with no manual step. Undocking returns everything to
the laptop panel.

**Why this priority**: The laptop is docked often. Rearranging displays by hand
each time makes the Mango session worse than COSMIC on the most frequent
daily action.

**Independent Test**: With a known setup recorded, plug the laptop into it,
check the arrangement, unplug, check that the laptop panel alone is in use
and every window is still reachable.

**Acceptance Scenarios**:

1. **Given** a recorded setup and a Mango session, **When** the user connects
   that setup, **Then** each display gets its recorded position, resolution,
   refresh rate and scale, and the laptop panel is on or off as recorded.
2. **Given** a docked session, **When** the user disconnects, **Then** the
   laptop panel turns on and windows from the removed displays move to it.
3. **Given** a recorded setup, **When** the laptop boots or logs in while
   already docked, **Then** the recorded arrangement applies from the start.
4. **Given** two recorded setups that share one display model, **When** the
   user connects either, **Then** the right one is chosen, because setups are
   told apart by the full set of connected displays.

---

### User Story 2 - Dock into an unknown setup (Priority: P1)

The user connects to a display they have not seen before (meeting room,
projector, a colleague's monitor). It turns on and is usable at once in a
predictable arrangement. If that is not what they want, they can rearrange it
from a graphical tool without editing configuration.

**Why this priority**: Unknown setups happen as often as known ones, and a
blank external display in a meeting is the failure the user notices most.

**Independent Test**: Connect a display that matches no recorded setup. Check
that it lights up in the default arrangement, then change its position or
mirroring with the graphical tool.

**Acceptance Scenarios**:

1. **Given** no recorded setup matches, **When** the user connects a display,
   **Then** it turns on at its preferred mode to the right of the laptop
   panel, and the panel stays on (with several unknown displays, each is
   placed to the right of the previous one).
2. **Given** an unknown setup is on, **When** the user opens the display tool,
   **Then** they can change position, scale, resolution and on/off, and the
   change takes effect at once.
3. **Given** an ad-hoc arrangement, **When** the user disconnects, **Then** the
   laptop returns to the panel-only layout; nothing ad-hoc is kept.

---

### User Story 3 - Every display is a full part of the desktop (Priority: P2)

Whatever the setup, each enabled display has the bar, the wallpaper and its
own tags, the lock screen covers all of them, and notifications and popups
appear on the display the user is working on.

**Why this priority**: Docking that turns displays on but leaves them without
a bar, unlocked, or blank behind the lock screen is not usable.

**Independent Test**: In a two-display setup, check the bar and wallpaper on
both, lock, and confirm both are covered; hot-plug a third display and repeat.

**Acceptance Scenarios**:

1. **Given** any setup, **When** a display is added, **Then** it shows the bar
   and the wallpaper within a few seconds.
2. **Given** a locked session, **When** a display is connected, **Then** it
   shows the lock screen, not desktop content.
3. **Given** the laptop lid is closed with an external display connected and
   power attached, **When** the lid closes, **Then** the laptop keeps running
   on the external displays, and the panel turns off.
4. **Given** the lid is closed with no external display, **When** the lid
   closes, **Then** suspend-then-hibernate runs as it does today (ADR 0001).

---

### User Story 4 - Session gaps found by the research are closed (Priority: P2)

The everyday functions COSMIC gave and the current Mango session lacks or
gets wrong work: screenshots from browsers and sandboxed apps, a screen-share
picker, clipboard content that survives closing the app it came from, an
on-screen display for volume and brightness, Bluetooth and audio device
controls, and a power menu.

**Why this priority**: These are the gaps that make a day in Mango worse than
a day in COSMIC; each is small.

**Independent Test**: In a Mango session: take a screenshot from a browser,
start a screen share and pick a display, copy from an app and close it then
paste, press volume and brightness keys, pair a Bluetooth device, switch the
audio output, open the power menu and lock from it.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** a browser or sandboxed app asks for a
   screenshot, **Then** it gets one.
2. **Given** a Mango session with several displays, **When** a browser starts
   screen sharing, **Then** the user picks which display to share.
3. **Given** text copied from an app, **When** that app is closed, **Then**
   the text can still be pasted.
4. **Given** a Mango session, **When** the user presses a volume or
   brightness key, **Then** a popup shows the new level.
5. **Given** a Mango session, **When** the user opens the Bluetooth or audio
   controls from the bar, **Then** they can pair a device and choose the
   audio output and input.
6. **Given** a Mango session, **When** the user opens the power menu, **Then**
   they can lock, log out, suspend, reboot or power off.

---

### User Story 5 - Look stays dark and consistent without COSMIC (Priority: P3)

GTK3, GTK4/libadwaita and Qt applications use the dark theme, and the cursor
has one theme and size in every app and on every display, whether or not
COSMIC is still enabled on the machine.

**Why this priority**: The research found that part of the current dark theme
comes from the COSMIC module. Fixing it now is what lets COSMIC be switched
off later in one step.

**Independent Test**: Evaluate `laptop` with COSMIC turned off; deploy it to a
test boot or VM; open a GTK3, a GTK4 and a Qt app and check theme and cursor.

**Acceptance Scenarios**:

1. **Given** Mango on and COSMIC off, **When** the user opens GTK3, GTK4 and
   Qt apps, **Then** all render dark.
2. **Given** a mixed-DPI setup, **When** the pointer crosses displays,
   **Then** the cursor keeps one theme and a size that matches each
   display's scale.

---

### User Story 6 - Annotate a screenshot (Priority: P3)

After taking a region screenshot, the user can draw on it (arrows, boxes,
text, blur) before saving or copying it.

**Why this priority**: Useful for bug reports and chat, but the plain
screenshot already works.

**Independent Test**: Take a region screenshot with the annotate shortcut,
add an arrow, copy it, paste it into a chat.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** the user takes an annotated region
   screenshot, **Then** an editor opens with the shot, and the result can be
   saved to a file or copied to the clipboard.
2. **Given** a Mango session, **When** the user takes a plain screenshot,
   **Then** it behaves as today, with no editor.

### Edge Cases

- A recorded display is connected through a different port or dock than last
  time: the setup is still recognised.
- Two identical monitors with the same make and model: they are told apart
  (by serial or port), so they do not swap positions between docks.
- A display is unplugged while a fullscreen video or a screen share is
  running on it: the window moves to a remaining display; the share stops
  cleanly rather than freezing.
- The dock is connected while the session is locked or before login: the
  login and lock screens appear on the displays, and the recorded arrangement
  applies after login.
- The display tool's ad-hoc changes conflict with a recorded setup: the
  recorded setup wins on the next connect.
- Docked with the lid closed and the external display is removed: the laptop
  then follows the normal lid-closed rule (suspend), it does not stay awake
  with no display.
- A display's preferred mode is unusable (wrong refresh, overscan): the user
  fixes it from the display tool for the current session.
- Mixed scales (1.0 external, 1.5 panel): XWayland apps stay readable on both.
- A nixpkgs bump changes a Mango config key the display rules use: the build
  fails, not the login (as `mango -p` does today).

## Requirements *(mandatory)*

### Functional Requirements

**Displays and docking**

- **FR-001**: Known display setups MUST be recorded as data in this
  repository, each identified by the set of connected displays (make, model
  and, where available, serial), with position, mode, scale and on/off for
  each display, including the laptop panel.
- **FR-002**: When the connected displays match a recorded setup, the session
  MUST apply it automatically, on hot-plug and at session start.
- **FR-003**: When no recorded setup matches, the session MUST turn on every
  connected display at its preferred mode in one documented default
  arrangement (see User Story 2).
- **FR-004**: The session MUST provide a graphical display tool for ad-hoc
  changes to position, mode, scale and on/off, with no configuration edit.
- **FR-005**: When a display is removed, windows and tags on it MUST move to a
  remaining display.
- **FR-006**: Every enabled display MUST get the bar and the wallpaper; the
  lock screen MUST cover every display, including ones connected while locked.
- **FR-007**: With the lid closed and an external display connected, the
  laptop MUST stay awake and turn the panel off; with no external display,
  lid close MUST keep the suspend-then-hibernate behaviour of ADR 0001.
- **FR-008**: Adding a new known setup MUST be a data change only (one entry),
  checked at evaluation for well-formedness.
- **FR-008a**: The session MUST provide a command that prints the currently
  connected displays in the recorded-setup format, so the user can paste it
  as a new entry.
- **FR-008b**: The default arrangement for unmatched displays MUST be: every
  external display on at its preferred mode, placed to the right of the
  laptop panel, with the panel on.

**Session gaps from the report**

- **FR-009**: Screenshot requests from browsers and sandboxed apps MUST be
  served under Mango (report §2, R1).
- **FR-010**: Screen sharing MUST offer a picker for which display to share
  that works regardless of the portal service's environment (report §12).
- **FR-011**: Clipboard content MUST persist after the source app closes
  (report §10).
- **FR-012**: Volume and brightness changes MUST show an on-screen level
  popup (report §16).
- **FR-013**: The session MUST provide Bluetooth pairing and audio
  input/output selection reachable from the bar (report §17).
- **FR-014**: The session MUST provide a power menu with lock, log out,
  suspend, reboot and power off (report §23).
- **FR-014a**: The session MUST offer an annotated region screenshot next to
  the plain one (report §11).
- **FR-014b**: Night light, screen recording and notification history are
  out of scope for this feature.

**Theming**

- **FR-015**: The Mango module MUST itself set the GTK3 dark theme, the
  GTK4/libadwaita dark preference, the Qt theme and a cursor theme and size,
  and MUST NOT rely on the COSMIC module for any of them (report §21).
- **FR-016**: These settings MUST NOT change how the COSMIC session looks
  when COSMIC is chosen at login.

**Constraints carried over**

- **FR-017**: Every new component MUST come from nixpkgs (spec 010, FR-009).
- **FR-018**: Every new long-running service MUST run only in the Mango
  session, not under COSMIC.
- **FR-019**: With the Mango module off, none of this MUST reach a machine's
  configuration; other machines MUST evaluate unchanged.
- **FR-020**: The stale and wrong statements the report lists in
  `specs/010-mango-wm-session/research.md` MUST be corrected or marked
  superseded, pointing to the report.

### Key Entities

- **Display setup**: a named, recorded combination of connected displays
  (identified by make, model, serial) and, for each, position, mode, scale
  and on/off. Belongs to a machine.
- **Default arrangement**: what the session does with displays that match no
  setup.
- **Session component**: each added piece (OSD, clipboard persistence,
  Bluetooth and audio controls, power menu, display manager tool) tied to the
  Mango session's lifetime.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Connecting a known setup gives the recorded arrangement within
  5 seconds, with zero manual steps, in 10 out of 10 docks.
- **SC-002**: Connecting an unknown display shows desktop content on it within
  5 seconds, with zero manual steps.
- **SC-003**: Rearranging an unknown setup with the display tool takes under
  1 minute and no configuration edit.
- **SC-004**: Adding a new known setup is one data entry and one deploy.
- **SC-005**: All 6 checks in User Story 4 pass on the first try after deploy.
- **SC-006**: With COSMIC turned off on `laptop`, GTK3, GTK4 and Qt test apps
  all render dark and with the same cursor.
- **SC-007**: Undocking never leaves a window unreachable: 100% of windows are
  on a visible display afterwards.
- **SC-008**: Zero new packages come from outside nixpkgs, and the other three
  machines evaluate to the same result before and after.

## Assumptions

- Applies to the `laptop` machine through the existing Mango module; COSMIC
  stays enabled and selectable. Turning COSMIC off is not part of this
  feature, only made possible by it.
- The report's "keep" verdicts stand: the bar, launcher, notifier, locker,
  idle handler, polkit agent, clipboard history, screenshot tool, wallpaper
  tool and greeter are not replaced.
- No full desktop shell (Noctalia, Dux Shell) is adopted; the assembled pieces
  stay (report §5).
- Switching the bar to native Mango modules waits until nixpkgs ships the bar
  version that has them (report §4); out of scope here.
- Reporting the portal key misspelling to nixpkgs upstream is a separate
  action, not part of this feature.
- Known setups are recorded from real hardware identifiers. No setup is
  recorded in this change; the user adds each later with the print command
  (FR-008a). SC-001 is checked once the first setup is added.
- Docking happens with power attached in most cases; lid-closed docked use
  without power follows the same rule as with power.
- Display rules belong to the user session; the login screen uses the
  displays' defaults.
