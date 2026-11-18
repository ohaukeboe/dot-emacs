# Feature Specification: Mango Islands Shell

**Feature Branch**: `013-mango-islands-shell`

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Restyle the Mango desktop shell (Waybar rail +
Quickshell popups in modules/mango) to design D "Islands, refined" from the
Claude Design canvas https://claude.ai/artifact/7Aoe3evXhJMATtbNH24pmN, and add
two features: a Claude usage bar pill + popup (inspired by
github.com/denonmaryland/omarchy-dotfiles plugins/denon.agents) and KDE Connect
integration (phone card in quick controls + detail page). Palette: frame/bar
#111111, apps #171717, islands/popups #212121, raised #2c2c2c,
foreground/accent #cabab4, dim #948985."

This feature builds on `specs/012-mango-rail-bar` and on commits `2b50db6`
(rail moved to the top edge) and `29e14ae` (COSMIC accent). The look is fixed
by the design canvas above; these artboards are the reference:

| Artboard                           | What it fixes                               |
|------------------------------------|---------------------------------------------|
| D · Islands, refined               | Rail, windows, quick controls, calendar     |
| D + Claude usage popup             | Usage pill on the rail and its popup        |
| D + KDE Connect in quick controls  | Phone card and its actions                  |
| KDE Connect detail page            | The phone's detail page                     |

Spec 012 left the reference's AI-usage rings out on purpose. This spec
reverses that decision: the user now asks for a Claude usage readout.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - One coherent islands look (Priority: P1)

In a Mango session the user sees the rail as three floating capsules along
the top edge: workspaces on the left, the date and clock in the middle, and
status icons on the right. The frame behind them is a darker
shade than the application windows, and every popup drops from the capsule
that opened it, in the capsule's colour, with the same rounded corners and
controls. The desktop reads as one system, the way a full desktop
environment does.

**Why this priority**: every other story sits inside this look; on its own it
already replaces the current mix of shades and shapes.

**Independent Test**: log in to Mango, open each existing popup (quick
controls, calendar, Wi-Fi, Bluetooth, sound pages) and compare it to the
"D · Islands, refined" artboard.

**Acceptance Scenarios**:

1. **Given** a Mango session, **When** the user looks at the top edge,
   **Then** they see three separate rounded capsules, not one full-width
   strip, and the frame between and around them is visibly darker than the
   application windows.
2. **Given** foot and Emacs are open, **When** the user compares their
   background with the frame, **Then** the windows are the lighter shade and
   the frame the darker one, with the same step between them as in the
   design.
3. **Given** the user clicks the clock, **When** the calendar opens,
   **Then** it appears directly below the clock capsule with no outline,
   today is a filled accent circle, and the clock capsule has no border.
4. **Given** the user clicks the phone, Wi-Fi, sound or battery icon,
   **When** quick controls open, **Then** volume and brightness are wide
   capsule sliders with their icon inside, Wi-Fi, Bluetooth and Mic are
   rows with a round toggle and an arrow to their detail page, and the power
   profile is a three-way segmented control.
5. **Given** any popup is open, **When** the user presses Escape or clicks
   outside it, **Then** it closes, as today.

---

### User Story 2 - Claude usage at a glance (Priority: P2)

The user codes with Claude Code on this machine and wants to know how much
of the current session and weekly allowance they have used, without opening
a browser. A pill on the right capsule shows a small ring filled to the session
percentage. Clicking it opens a usage popup with both limits with
meters and reset times, and token use for the last seven days or per model.

**Why this priority**: it adds new information the user asked for; the shell
works without it.

**Independent Test**: with a signed-in Claude Code, check the pill's
percentage against the usage the Claude Code CLI reports, then open the
popup and check both limits, their reset times and today's token row.

**Acceptance Scenarios**:

1. **Given** Claude Code is signed in, **When** the rail is shown, **Then**
   the usage pill shows a ring filled to the session percentage, with the
   number in its tooltip.
2. **Given** the user clicks the usage pill, **When** the popup opens,
   **Then** it shows the tool name, when the data was last updated,
   a session limit and a weekly limit each with a meter, percentage and reset
   time, and a "By day" / "By model" switch over the token breakdown.
3. **Given** the popup shows "By day", **Then** there is one row per day for
   the last seven days, today last and highlighted, each bar scaled to the
   busiest day, and a weekly total below.
4. **Given** the user switches to "By model", **Then** there is one row per
   model with its token count, bars scaled to the heaviest model.
5. **Given** the user clicks refresh in the popup, **Then** the data updates
   and the "updated" time resets.
6. **Given** the user clicks "Open Claude", **Then** a terminal opens running
   Claude Code and the popup closes.

---

### User Story 3 - Phone in quick controls (Priority: P2)

The user's phone is paired through KDE Connect. Quick controls show a phone
card under the Wi-Fi, Bluetooth and Mic rows with the phone's name,
connection state, battery and number of unread notifications, plus four
one-tap actions: ring the phone, send a file, send the clipboard, and browse
the phone's files. The rail's status capsule shows a phone icon while the
phone is connected.

**Why this priority**: same weight as Story 2; each is independent.

**Independent Test**: with a paired, reachable phone, open quick controls,
check the card's battery against the phone, then use each action once.

**Acceptance Scenarios**:

1. **Given** a paired phone is reachable, **When** quick controls open,
   **Then** the phone card shows its name, "Connected", its battery
   percentage and its unread notification count.
2. **Given** the card is shown, **When** the user taps Ring, **Then** the
   phone rings.
3. **Given** the user taps Send file, **Then** a file chooser opens and the
   chosen file arrives on the phone.
4. **Given** the user taps Clipboard, **Then** the desktop clipboard's text
   arrives on the phone's clipboard.
5. **Given** the user taps Browse, **Then** the phone's shared storage opens
   in the file manager.
6. **Given** the phone is connected, **When** the user looks at the status
   capsule, **Then** a phone icon is shown; when it disconnects, the icon
   disappears.

---

### User Story 4 - Phone detail page (Priority: P3)

The phone card's arrow opens a detail page inside quick controls, like the
Wi-Fi and Bluetooth pages. It shows the phone with its battery and charging
state, the four actions as larger buttons, the phone's mirrored
notifications with a "Clear all", the other paired devices with their
reachability, and a way to pair a new device.

**Why this priority**: the card covers the daily actions; the page is for
less frequent tasks.

**Independent Test**: open the page, compare its notification list with the
phone, dismiss one, pair or unpair a second device.

**Acceptance Scenarios**:

1. **Given** the user taps the phone card's arrow, **Then** the detail page
   replaces the quick-controls content and a back control returns to it.
2. **Given** the phone has notifications, **Then** each is listed with its
   app, title and text, in the order KDE Connect reports them (it gives no
   time); "Clear all" dismisses them on the phone.
3. **Given** another device is paired but not reachable, **Then** it is
   listed as "Paired · not reachable".
4. **Given** the user chooses "Pair a new device", **Then** nearby unpaired
   devices are listed and choosing one sends a pairing request.

---

### Edge Cases

- Claude Code is installed but not signed in, or the usage service rejects
  the request: the pill shows a muted state with no percentage, and the popup
  says why and still shows local token use.
- Claude Code has never been used on this machine: the usage pill is not
  shown at all.
- The usage data is older than two refresh intervals (offline): the popup
  marks the "updated" time as stale; the pill keeps the last known value.
- A limit reaches 100%: the meter is full and the reset time stays visible;
  the pill's ring is full.
- No phone is paired: no phone icon on the rail; quick controls show no phone
  card, only a single "Set up phone" row that opens the detail page's pairing
  list.
- A paired phone is out of reach: the card shows "Not reachable" with the
  actions disabled, and the rail shows no phone icon.
- Several phones are reachable: the card shows the most recently connected
  one; the detail page lists the others.
- Sending a file fails or is cancelled: the user gets a desktop notification
  saying so; nothing else changes.
- A second monitor is connected: popups open on the monitor whose rail was
  clicked, as today.
- Quick controls with the phone card must still fit on the laptop panel; if
  the screen is too short, the popup scrolls rather than running off screen.

## Requirements *(mandatory)*

### Functional Requirements

**Look (all surfaces)**

- **FR-001**: The rail MUST be three floating rounded capsules on the top
  edge (workspaces, clock, status) instead of one full-width strip.
- **FR-002**: Surfaces MUST use one shared palette: frame and gaps `#111111`;
  application backgrounds `#171717`; capsules and popups `#212121`; raised
  controls `#2c2c2c`; text and accent `#cabab4`; secondary text `#9c918d`
  (the requested `#948985`, lightened to reach 4.5:1 on `#2c2c2c`); text on
  accent fills `#171717`.
- **FR-003**: foot and Emacs backgrounds MUST stay `#171717`, so the frame
  is darker than the windows.
- **FR-004**: The palette MUST be defined once and reused by the rail, every
  popup, the window borders and the lock screen, not repeated per file.
- **FR-005**: Popups MUST open directly under the capsule that opened them,
  with rounded corners, a shadow and no outline.
- **FR-006**: The control that opened a popup MUST show an open state while
  its popup is open: a filled accent for the usage pill, the `raised` fill
  for the clock, so the centre island stays quiet. Quick controls are the
  exception: the phone, Wi-Fi, sound and battery icons that open them share
  one `raised` capsule instead, since waybar cannot mark a group as open.
- **FR-007**: The clock capsule MUST show the date before the time, with no
  border.
- **FR-008**: Quick controls MUST use the controls in the "D" artboard:
  capsule sliders with the icon inside, list rows with a round toggle and an
  arrow, a three-way segmented power profile, and a footer with battery
  state, a lock button and a power button.
- **FR-009**: The existing Wi-Fi, Bluetooth and sound detail pages and the
  calendar MUST be restyled to the same palette and shapes without losing any
  function from spec 012.
- **FR-010**: Secondary text MUST stay readable: at least 4.5:1 contrast on
  every surface it appears on.

**Claude usage**

- **FR-011**: The status capsule MUST show a usage pill with a ring filled to
  the current session percentage whenever usage data exists for this
  machine; the number is in its tooltip.
- **FR-012**: Clicking the pill MUST open the usage popup; it MUST show the
  session and weekly limits with meter, percentage and reset time, the time
  of the last update, and a refresh control. It shows no plan name: Claude
  Code's status line does not report one.
- **FR-013**: The popup MUST offer a "By day" view (last seven days, today
  highlighted, scaled to the busiest day, weekly total) and a "By model" view
  (tokens per model, scaled to the heaviest model).
- **FR-014**: Usage data MUST refresh on its own at a fixed interval and on
  demand from the refresh control, without blocking the rail.
- **FR-015**: Limits MUST come from the account's own usage as Claude Code
  sees it, using the credentials Claude Code already holds; token counts MUST
  come from Claude Code's local session records.
- **FR-016**: The credentials MUST NOT be copied, logged or shown, and the
  usage data MUST NOT leave the machine except in the request for the
  account's own usage.
- **FR-017**: "Open Claude" MUST open the user's terminal running Claude
  Code.
- **FR-018**: When limits cannot be read, the pill and popup MUST show the
  states in Edge Cases rather than stale or empty numbers without comment.

**KDE Connect**

- **FR-019**: Quick controls MUST show a phone card for the active paired
  phone with name, connection state, battery and unread notification count.
- **FR-020**: The card MUST offer Ring, Send file, Clipboard and Browse,
  each doing what User Story 3 describes.
- **FR-021**: The status capsule MUST show a phone icon while a paired phone
  is connected, and none otherwise.
- **FR-022**: The card's arrow MUST open a detail page with the phone's
  battery and charging state, the four actions, mirrored notifications with
  "Clear all", other paired devices with reachability, and pairing of new
  devices.
- **FR-023**: The phone card, detail page and phone icon MUST appear only
  when KDE Connect is enabled for the session; with it off they MUST NOT
  appear and nothing related to it MUST run.
- **FR-024**: The existing KDE Connect tray indicator MUST be removed from
  the Mango session once the card and page cover its functions, so the phone
  is not shown twice.

### Key Entities

- **Palette**: the named surface and text colours in FR-002, shared by every
  part of the shell.
- **Usage record**: for one account — session and weekly limits (used
  percentage, reset time), tokens per day for seven days, tokens per model,
  time of last update, and an error state.
- **Phone**: a paired KDE Connect device — name, kind (phone or tablet),
  reachable, battery and charging state, unread notifications.
- **Mirrored notification**: app, title, text, and whether it can be
  dismissed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Side by side with the four design artboards, every element on
  them is present in the running session with the same colours, order and
  shape; a reviewer finds no element missing or out of palette.
- **SC-002**: The user can see their current session usage in one glance
  and their weekly usage in one click, without opening a browser.
- **SC-003**: The usage pill's session percentage matches what the Claude
  Code CLI reports at the same moment, within 1 percentage point.
- **SC-004**: Each phone action takes one click from opened quick controls
  and takes effect on the phone within 5 seconds on the same network.
- **SC-005**: Opening any popup feels instant: it appears within a quarter of
  a second of the click, including the usage popup.
- **SC-006**: With KDE Connect turned off, or Claude Code never used, no
  empty or broken element appears anywhere in the shell.

## Assumptions

- The rail stays on the top edge (commit `2b50db6`); the glossary entry for
  **Rail** still says "left edge" and is updated as part of this feature.
- The Claude accent `#cabab4` replaces the COSMIC accent as the shell's
  accent; it is no longer read from the COSMIC theme.
- Mock values on the canvas (percentages, tokens, phone names,
  notifications) are sample data only.
- The usage readout covers Claude Code only. Other agents in the reference
  (Codex, Fireworks) and its cross-device sync are out of scope.
- Usage limits use the same account usage service the reference uses for
  Claude; local token counts come from Claude Code's session files under the
  user's Claude directory. A refresh interval of 15 minutes is the default,
  as in the reference.
- KDE Connect's daemon already runs in the Mango session
  (`services.kdeconnect` in `modules/mango`); its firewall ports are opened
  by that service. The phone runs the KDE Connect app.
- Mirrored notifications already appear as desktop notifications; this
  feature lists them in the detail page. The popups themselves are drawn by
  Quickshell (`Notifications.qml`), which replaced mako.
- The power menu, lock screen behaviour and workspace logic are unchanged;
  only their look follows the palette.
- The canvas shows both popups open at once for review; the shell still opens
  one popup at a time.
