# Feature Specification: Proton Pass Quick Access

**Feature Branch**: `016-proton-pass-quick-access`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "I have previously made an application for
integrating proton pass with cosmic. Make a similar integration with
quickshell. You determine whether it is better to port that implementation
over, to expand that implementation, or to start from scratch"

The earlier application is `cosmic-pass` (`github:ohaukeboe/cosmic-pass`): a
keyboard-driven popup for the COSMIC desktop, bound to `Super+Space` by
`modules/cosmic-de`. Press the shortcut, type a few letters, press Enter; the
password is on the clipboard and the popup is gone. The Mango session has no
such popup: `specs/010-mango-wm-session/research.md` R5 recorded the gap and
bound `Super+Space` to the full Proton Pass application instead. This feature
closes that gap with a popup of the **Rail**, in the look of the picker
(`specs/015-picker-layouts`).

**Decision on port, expand or start over**: expand `cosmic-pass`. See
Assumptions for the reasoning and for what it means for this repository.

## Clarifications

### Session 2026-11-18

- Q: May the Mango module install the popup's backend from the `cosmic-pass` flake input, although `specs/010-mango-wm-session` FR-009 says every Mango package must come from nixpkgs? → A: Yes, as one stated exception for `cosmic-pass`; FR-009 stays in force for everything else.
- Q: If running the backend without its window still drags the COSMIC desktop libraries onto a machine that has COSMIC turned off, is that acceptable? → A: Acceptable for now: ship with the larger closure and record the split as follow-up work.
- Q: When the popup shows that you are signed out of Proton Pass, how should signing in work? → A: Start the sign-in from the popup; it opens the browser and shows the progress lines.
- Q: `Super+Space` opens the full Proton Pass application today; where should that application go when the key is taken by the popup? → A: The popup gets a key that opens the selected item in the full application. Withdrawn the same day: planning found the application cannot be opened on an item, so there is no such key and the application is reached from the launcher only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Copy a password from the keyboard (Priority: P1)

The user is at a sign-in form. They press `Super+Space`. A popup opens on the
Rail with a search field and their Proton Pass items, the ones they use most
first. They type a few letters; the list narrows to items whose title,
username, website or vault name matches. They press Enter. The popup closes,
the password of the selected item is on the clipboard, and focus is back in
the window they came from. A minute and a half later the password is gone
from the clipboard again.

**Why this priority**: This is the whole reason for the feature and what the
COSMIC popup is used for nearly every time. Alone it replaces opening the full
application for the common case.

**Independent Test**: With a signed-in account, press `Super+Space`, type part
of an item's title, press Enter, paste into a text field: the item's password
appears. Open the clipboard history: the password is not listed. Wait 90
seconds and paste again: nothing, or whatever was copied since.

**Acceptance Scenarios**:

1. **Given** a signed-in account with items loaded, **When** the user presses
   the shortcut, **Then** the popup opens with the search field focused and
   the items listed, most used first.
2. **Given** the popup is open, **When** the user types, **Then** the list
   shows only items whose title, username, website or vault name matches, and
   the best match is selected.
3. **Given** a login item is selected, **When** the user presses Enter,
   **Then** its password is copied, the popup closes and the previous window
   has focus again.
4. **Given** a selected item that is not a login, **When** the user presses
   Enter, **Then** its main value is copied instead: the card number of a
   card, the text of a note.
5. **Given** a secret was copied 90 seconds ago and is still the clipboard
   content, **When** the time is up, **Then** the clipboard is emptied.
6. **Given** a secret was copied and the user has copied something else
   since, **When** the 90 seconds are up, **Then** the clipboard is left
   alone.
7. **Given** the popup is open, **When** the user presses Esc or the shortcut
   again, **Then** it closes and nothing is copied.
8. **Given** a query that matches nothing, **When** the user presses Enter,
   **Then** nothing is copied and the popup says there are no matches.

---

### User Story 2 - Copy another field of an item (Priority: P2)

The user needs the username, the one-time code or a custom field rather than
the password. With the item selected they press Tab. The popup shows every
field of that item: username, password, one-time code, website, note, card
fields, custom fields. Secret values are masked. The user moves to a field
and presses Enter; that field is copied and the popup closes. Esc goes back
to the item list.

**Why this priority**: Two-step sign-ins need the username and the one-time
code as often as the password. Without this the user still has to open the
full application for them.

**Independent Test**: Select a login with a one-time code, press Tab, move to
the code, press Enter, paste: a six-digit code that the site accepts.

**Acceptance Scenarios**:

1. **Given** an item is selected, **When** the user presses Tab, **Then** the
   popup lists that item's fields by name, with secret values masked.
2. **Given** the field list, **When** the user presses Enter on a field,
   **Then** that field's current value is copied and the popup closes.
3. **Given** the field list, **When** the user picks a one-time code field,
   **Then** the code valid at that moment is copied.
4. **Given** the field list, **When** the user copies a field that is not a
   secret (username, website), **Then** it stays on the clipboard and may
   appear in clipboard history.
5. **Given** the field list, **When** the user presses Esc, **Then** the item
   list returns with the same query and selection.

---

### User Story 3 - Know why it is not working (Priority: P2)

The user presses the shortcut and something is wrong: they are signed out of
Proton Pass, the keyring is locked, the network is down, or the Proton Pass
command-line tool is missing or older than the tested version. The popup
opens anyway and says which of these it is and what to do, in one or two
lines. When signed out it offers to sign in and shows the progress of the
sign-in. When only the network is down it still lists the items it knew
about, and says they may be out of date.

**Why this priority**: A popup that opens empty with no explanation is worse
than no popup; the user cannot tell a broken install from an empty vault.
It ranks with story 2 because it is needed from the first day of use, but
after story 1 because it adds nothing when everything works.

**Independent Test**: Sign out of Proton Pass, press the shortcut: the popup
says so and offers sign-in. Complete the sign-in: the items appear without
restarting anything.

**Acceptance Scenarios**:

1. **Given** no signed-in account, **When** the popup opens, **Then** it says
   the user is signed out and offers to sign in.
2. **Given** the user starts the sign-in, **When** it completes, **Then** the
   items load and the popup is usable without a restart.
3. **Given** the item list cannot be refreshed, **When** the popup opens,
   **Then** the last known items are listed with a note that they may be out
   of date.
4. **Given** a copy fails, **When** the failure is reported, **Then** the
   popup stays open, says what failed and leaves the clipboard unchanged.
5. **Given** the command-line tool is older than the tested version, **When**
   the popup opens, **Then** it shows a warning and still works.
6. **Given** the command-line tool cannot read its own session store,
   **When** the popup opens, **Then** it names the fix (sign out with force,
   sign in again).

---

### User Story 4 - Look at a secret without copying it (Priority: P3)

In the field list the user presses `Ctrl+R` on a masked field. Its value is
shown in place. Pressing it again, moving away, or closing the popup hides
it. A revealed one-time code keeps itself current.

**Why this priority**: Useful for reading a PIN aloud or typing a password
into another device, but rare next to copying.

**Independent Test**: Tab into an item, press `Ctrl+R` on the password: it is
readable. Press Esc and Tab again: it is masked.

**Acceptance Scenarios**:

1. **Given** a masked field is highlighted, **When** the user presses
   `Ctrl+R`, **Then** its value is shown.
2. **Given** a revealed field, **When** the user presses `Ctrl+R` again,
   moves to another field, goes back or closes the popup, **Then** the value
   is masked and no longer held by the popup.
3. **Given** a revealed one-time code, **When** its period rolls over,
   **Then** the shown code changes to the new one.

---

### Edge Cases

- The popup is opened seconds after login, before the first item list has
  arrived: it shows that items are loading and fills in when they arrive,
  keeping what the user has typed.
- An item is deleted or changed in Proton Pass while the popup lists the old
  version: copying fetches the current value; if the item is gone the popup
  says so and refreshes.
- A refresh finishes while the user is moving through the list: the selected
  item stays selected if it still exists.
- The user presses Enter twice quickly, or closes the popup while a copy is
  still being fetched: one copy happens, or none; never a copy that lands
  after the user has moved on to something else.
- The screen locks or the session ends with a secret on the clipboard: the
  90-second clearing still happens.
- Another Rail popup (launcher, picker, quick controls) is open when the
  shortcut is pressed: the Proton Pass popup replaces it, as Rail popups
  already do for each other.
- Several monitors: the popup opens on the focused monitor, like the picker.
- Thousands of items: typing stays responsive; the list shows the 50 best
  matches and scrolls within them.
- Two items with the same title: the username and vault name tell them apart
  in the row.
- A field name inside a section of an item (custom sections): it is listed
  and copies the right value.

## Requirements *(mandatory)*

### Functional Requirements

**Opening and closing**

- **FR-001**: In the Mango session, `Super+Space` MUST toggle the quick-access
  popup, replacing the binding that opens the full Proton Pass application.
  The full application MUST remain reachable from the launcher. The popup
  has no key for it.
- **FR-002**: The popup MUST be a popup of the Rail, built from the same
  tokens and components as the picker, and MUST open with the search field
  focused and empty.
- **FR-003**: Esc MUST close the popup from the item list and go back from
  the field list. Closing MUST return focus to the window that had it.
- **FR-004**: The popup MUST be fully usable from the keyboard; every action
  MUST also be reachable with the pointer.

**Finding items**

- **FR-005**: The popup MUST search the active items of every vault of the
  signed-in account and list the best matches, at most 50, each row showing
  title, username or equivalent, and vault name. With an empty query these
  are the 50 most used.
- **FR-006**: Typing MUST filter the list by title, username, website and
  vault name, tolerant of gaps between the typed letters, and MUST select the
  best match.
- **FR-007**: With an empty query, and between equally good matches, items
  the user has copied from more often and more recently MUST come first.
- **FR-008**: Up/Down and `Ctrl+P`/`Ctrl+N` MUST move the selection.
- **FR-009**: The item list MUST be available without waiting for the network
  when the popup opens, and MUST be refreshed in the background when the
  session starts, when the popup opens with items older than five minutes,
  and when the user presses `F5`.

**Copying**

- **FR-010**: Enter on an item MUST copy its main value (password for a
  login, number for a card, text for a note) and close the popup.
- **FR-011**: Tab on an item MUST show all of its fields; Enter on a field
  MUST copy that field and close the popup.
- **FR-012**: One-time code fields MUST yield the code valid at the moment of
  copying or revealing.
- **FR-013**: Every copied or revealed value MUST be fetched at that moment,
  not taken from a stored copy.
- **FR-014**: A copied secret MUST be marked so that the session's clipboard
  history does not record it.
- **FR-015**: A copied secret MUST be removed from the clipboard after 90
  seconds, only if it is still the clipboard's content.
- **FR-016**: `Ctrl+R` in the field list MUST reveal the highlighted secret
  and hide it again as described in User Story 4.

**Secrets at rest**

- **FR-017**: Secret values MUST NOT be written to disk, logs, notifications
  or the shell's own state beyond the moment they are shown or copied.
- **FR-018**: Whatever item information is kept between sessions (titles,
  usernames, websites, vault names) MUST be stored encrypted with a key held
  in the user's keyring, and MUST NOT be stored at all when the keyring is
  unavailable.

**Status**

- **FR-019**: The popup MUST distinguish and name these states: loading,
  signed out, out-of-date items, keyring unavailable, command-line tool
  missing, command-line tool older than tested, session store unreadable, and
  a failed copy; each with the action that resolves it where one exists.
- **FR-020**: The user MUST be able to start the Proton Pass sign-in from the
  popup, without a terminal. Starting it MUST open the sign-in page in the
  browser, and the popup MUST show the sign-in's progress lines as they
  arrive. A sign-in that fails or times out MUST be reported in the popup,
  which then offers to start again.

**Configuration**

- **FR-021**: The feature MUST be part of the Mango module and MUST
  contribute nothing when that module is off.
- **FR-022**: The feature MUST work with the COSMIC module off, and MUST NOT
  change the COSMIC session's own popup or shortcut when both are on.
- **FR-023**: The clipboard clearing time MUST be a typed option of the Mango
  module with 90 seconds as its default.
- **FR-024**: Both sessions and a terminal MUST see the same Proton Pass
  sign-in: signing in once MUST serve the COSMIC popup, the Mango popup and
  the command line.
- **FR-025**: The popup's backend MUST come from the `cosmic-pass` flake
  input. This is the only exception to `specs/010-mango-wm-session` FR-009;
  every other package the Mango module installs MUST still come from nixpkgs,
  and the exception MUST be recorded where FR-009 is stated.

### Key Entities

- **Item**: One Proton Pass entry (login, card, note, identity, alias or
  custom). Has a title, a vault, a kind, and fields. Only its non-secret
  summary (title, username, websites, vault name) is kept for searching.
- **Vault**: A named collection of items in the signed-in account.
- **Field**: A named value of an item. Either secret (password, one-time
  code seed, card number, security code, hidden custom field) or not
  (username, website, note title). May sit inside a named section.
- **Usage record**: How often and how recently the user copied from an item;
  orders the list. Holds no field values.
- **Session status**: Which of the states of FR-019 applies, and the account
  that is signed in.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From pressing the shortcut to having the password of a known
  item on the clipboard takes under 5 seconds and no pointer use.
- **SC-002**: The popup is visible and accepts typing within half a second of
  the shortcut, at any time after the session has started, with or without a
  network connection.
- **SC-003**: With 2,000 items the list updates within a tenth of a second of
  each keystroke.
- **SC-004**: After any number of secret copies, the clipboard history holds
  none of them.
- **SC-005**: A copied secret that is still on the clipboard is gone within 95
  seconds of the copy.
- **SC-006**: No secret value appears in any file under the user's home
  directory or in the session's logs after a day of normal use.
- **SC-007**: In each failure state of FR-019 the popup names the state; the
  user never sees an empty popup with no explanation.
- **SC-008**: Every key listed for the COSMIC popup (type, Enter, Up/Down,
  `Ctrl+P`/`Ctrl+N`, Tab, `Ctrl+R`, Esc, `F5`) does the same thing in the
  Mango popup.
- **SC-009**: A machine with the Mango module off evaluates to the same
  system as before this feature.

## Assumptions

- **Expand, do not port or start over.** `cosmic-pass` is about 15,000 lines,
  of which roughly 1,000 draw the COSMIC popup. The rest is desktop-neutral:
  the driver for the Proton Pass command-line tool with 1,400 lines of output
  parsing, contract tests that run the pinned tool, the encrypted item cache,
  search and usage ranking, the clipboard helper that sets the secret hint
  and clears after a timeout, and the state machine behind every scenario
  above. That tool has renamed and removed commands in patch releases, so the
  parser and its tests are the expensive part and the part this repository
  could not verify (it has no runtime test suite, by its constitution).
  A port would fork that code; starting over would rewrite it untested.
  Therefore `cosmic-pass` gains a way to run without its own window and to be
  driven by another front end, and this repository adds only the Rail popup
  and the wiring. How the two talk is for the plan.
- **Work spans two repositories.** The backend change lands in `cosmic-pass`
  and is tested there; this repository consumes it through the existing
  `cosmic-pass` flake input.
- **Exception to `specs/010-mango-wm-session` FR-009.** That requirement says
  every package the Mango module installs comes from nixpkgs, and R5 used it
  to leave this popup out. The exception of FR-025 is confirmed (see
  Clarifications). The input is pinned by `flake.lock` (constitution II), and
  FR-014 of that spec still holds, since the input is independent of the
  COSMIC module being on.
- The backend may bring the COSMIC desktop's libraries onto a machine that
  has COSMIC off. This larger closure is accepted for the first version.
  Building the backend without those libraries is follow-up work, to be
  filed as a ticket when this feature is planned; it does not block shipping.
- Proton Pass is reached only through its official command-line tool, already
  installed and signed in the same way the COSMIC popup needs
  (`PROTON_PASS_LINUX_KEYRING=dbus`, already set by the Mango module).
- A keyring provider runs in the Mango session, as it already does.
- The session's clipboard history already skips entries marked as sensitive
  (`modules/mango/session.nix`); this feature relies on that and does not
  change it.
- The Proton Pass application cannot be opened on a given item (version
  1.42.0 has no item link), so the popup offers no key to open it. FR-026,
  which asked for one, is withdrawn and its number is not reused.
- Out of scope: creating, editing or deleting items; filling fields into
  applications or browsers; choosing between several Proton accounts;
  a preferences screen (the one setting is a module option); the
  1Password shortcut on `Super+Shift+Space`, which stays as it is.
- Only the Mango session on NixOS is covered. The COSMIC popup keeps working
  unchanged.
