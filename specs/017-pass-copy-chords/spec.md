# Feature Specification: Proton Pass Copy Chords

**Feature Branch**: `017-pass-copy-chords`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "Add keybinds in the quickshell menu to copy OTP
and Username. Use the same keybinds as in the cosmic ui. ctrl+u for username
and ctrl+o for OTP. Also, check if there are any other keybinds from the
cosmic ui that is missing"

Extends specs/016-proton-pass-quick-access. The reference for "the same keys
as the COSMIC popup" is the COSMIC popup's keyboard contract,
`~/projects/cosmic-pass/specs/001-quick-access-launcher/contracts/keyboard.md`
(as amended by its feature 002).

## Gap found against the COSMIC popup

Keys the COSMIC popup has and the Mango popup lacks today:

| COSMIC key                       | What it does                          | Here     |
|----------------------------------|---------------------------------------|----------|
| `Ctrl+U`                         | copy the username (or email), close   | US1      |
| `Ctrl+O`                         | copy the current one-time code, close | US1      |
| `Ctrl+L`                         | copy the first website, close         | US2      |
| `Ctrl+J`, `Ctrl+K`               | next, previous                        | excluded |
| `Right` with an empty query      | open the field list                   | US3      |
| `Left`, `Shift+Tab`              | back from the field list              | US3      |
| `PageUp`, `PageDown` in fields   | move the field highlight by a page    | US3      |
| `Ctrl+Shift+S`                   | sign in, from the status lines        | US4      |
| `Ctrl+Shift+R`                   | retry after an error, lock or no CLI  | US4      |
| `Ctrl+,`                         | open preferences                      | excluded |

`Ctrl+,` stays out: the Mango popup has no preferences screen by design
(specs/016, Assumptions). `Ctrl+J` and `Ctrl+K` stay out by the user's
choice; `Ctrl+N`/`Ctrl+P` and the arrows already move the highlight. The COSMIC popup's mouse rules (click selects,
double-click copies) also stay out: the Mango popup's single-click copy is
specs/016's decision and not a key.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Copy the username or one-time code from the keyboard (Priority: P1)

The user opens the popup, types a few letters, and presses `Ctrl+U` to copy
the highlighted item's username, or `Ctrl+O` to copy its current one-time
code. The value lands on the clipboard and the popup closes, exactly as
`Enter` does for the password. No trip through the field list is needed.

**Why this priority**: it is what the user asked for. Logging in usually
needs the username and a code as well as the password; today each takes
`Tab`, arrows and `Enter`.

**Independent Test**: with an item that has a username and a one-time code,
open the popup, type part of its title, press `Ctrl+U`, paste: the username
appears and the popup is closed. Repeat with `Ctrl+O`: a six-digit code
that matches the Proton Pass app appears.

**Acceptance Scenarios**:

1. **Given** the item list with an item highlighted that has a username,
   **When** the user presses `Ctrl+U`, **Then** the username is copied and
   the popup closes.
2. **Given** an item with no username but an email, **When** the user
   presses `Ctrl+U`, **Then** the email is copied and the popup closes.
3. **Given** an item with a one-time code, **When** the user presses
   `Ctrl+O`, **Then** the code valid at that moment is copied and the popup
   closes.
4. **Given** the field list of an item, **When** the user presses `Ctrl+U`
   or `Ctrl+O`, **Then** the same happens as in the item list, for the open
   item, whatever row is highlighted.
5. **Given** an item with no username, email or one-time code, **When** the
   user presses the matching key, **Then** the clipboard is unchanged, the
   popup stays open, and the notice line says which value the item lacks.

---

### User Story 2 - Copy the website (Priority: P2)

`Ctrl+L` copies the highlighted item's first website and closes the popup,
as in the COSMIC popup.

**Why this priority**: same shape as US1 and nearly free once US1 exists,
but used less often.

**Independent Test**: with an item that has a website, press `Ctrl+L`,
paste: the address appears and the popup is closed.

**Acceptance Scenarios**:

1. **Given** an item with one or more websites, **When** the user presses
   `Ctrl+L`, **Then** the first website is copied and the popup closes.
2. **Given** an item with no website, **When** the user presses `Ctrl+L`,
   **Then** the clipboard is unchanged and the notice line says so.

---

### User Story 3 - Move around with the COSMIC popup's keys (Priority: P2)

A user who learned the COSMIC popup can open
the field list with `Right` when nothing is typed, leave it with `Left` or
`Shift+Tab`, and page through a long field list.

**Why this priority**: the user switches between both sessions; keys that
work in one and not the other cost a wasted press each time.

**Independent Test**: in the popup, with an empty query press `Right`,
then `Left`.

**Acceptance Scenarios**:

1. **Given** the item list with an empty query, **When** the user presses
   `Right`, **Then** the field list of the highlighted item opens.
2. **Given** the item list with text in the query, **When** the user presses
   `Right` or `Left`, **Then** the text cursor moves and nothing else
   happens.
3. **Given** the field list, **When** the user presses `Left` or
   `Shift+Tab`, **Then** the item list returns, as with `Esc`.
4. **Given** the field list, **When** the user presses `PageDown` or
   `PageUp`, **Then** the highlight moves by a page and any revealed value
   is masked, as an arrow press does.

---

### User Story 4 - Sign in and retry from the keyboard (Priority: P3)

When the popup shows why it cannot list items, `Ctrl+Shift+S` starts the
sign-in and `Ctrl+Shift+R` checks the session again, as the COSMIC popup's
status panel does.

**Why this priority**: rare (only after a sign-out, a lock or an error), and
`Enter` and the button already start the sign-in.

**Independent Test**: lock the `pass-cli` session, open the popup, unlock it
in a terminal, press `Ctrl+Shift+R`: the items appear without closing the
popup.

**Acceptance Scenarios**:

1. **Given** the popup shows that the user is signed out or in error with
   sign-in offered, **When** the user presses `Ctrl+Shift+S`, **Then**
   sign-in starts, as with the Sign in button.
2. **Given** the popup shows locked, error or missing CLI, **When** the user
   presses `Ctrl+Shift+R`, **Then** the session is checked again and the
   popup shows the new state.
3. **Given** a signed-in session with items listed, **When** the user
   presses either chord, **Then** nothing happens.

---

### Edge Cases

- A key pressed while a copy is still being fetched: the COSMIC popup's rule
  applies, the later request replaces the earlier one; at most one value
  reaches the clipboard.
- A one-time code that is about to expire: the code valid at the moment of
  the press is copied, as in the COSMIC popup; no wait for the next period.
- An item with several one-time codes: `Ctrl+O` copies the first, as in the
  COSMIC popup; the others stay reachable in the field list.
- No item highlighted (empty result list): every copy chord does nothing.
- The backend is stopped: the copy chords do nothing; `Esc` still closes.
- A backend older than this feature: it ignores the new requests, so the
  key does nothing and the popup stays open; no crash, no wrong value.
- `Ctrl+O` once meant "open the item in the Proton Pass app" in specs/016
  (FR-026, withdrawn). It now means copy the one-time code only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: In both the item list and the field list, `Ctrl+U` MUST copy
  the username of the highlighted (item list) or open (field list) item, or
  its email when it has no username, then close the popup.
- **FR-002**: `Ctrl+O` MUST, in both lists, copy that item's first one-time
  code as it is at the moment of the press, then close the popup.
- **FR-003**: `Ctrl+L` MUST, in both lists, copy that item's first website,
  then close the popup.
- **FR-004**: When the item lacks the value a copy chord asks for, the popup
  MUST leave the clipboard unchanged, stay open, and show on its notice line
  which value is missing.
- **FR-005**: The values copied by FR-001 to FR-003 MUST follow the same
  rules as every other copy in specs/016: cleared after the configured
  time, marked as sensitive for the clipboard history, never written to
  logs, and never part of what the popup draws.
- **FR-006**: Withdrawn (`Ctrl+J`/`Ctrl+K` left out by the user); the
  number is not reused.
- **FR-007**: `Right` MUST open the field list when the query is empty and
  the item list is shown; with text in the query it MUST only move the text
  cursor.
- **FR-008**: `Left` and `Shift+Tab` in the field list MUST return to the
  item list, as `Esc` does there.
- **FR-009**: `PageUp` and `PageDown` in the field list MUST move the
  highlight by a page and mask any revealed value.
- **FR-010**: `Ctrl+Shift+S` MUST start sign-in when, and only when, sign-in
  is offered.
- **FR-011**: `Ctrl+Shift+R` MUST check the session again when the popup
  shows locked, error or missing CLI, and do nothing otherwise.
- **FR-012**: The key hint line MUST name `Ctrl+U` and `Ctrl+O`; the full
  list of keys MUST be in the popup's key contract (specs/016
  `contracts/shell.md`, updated by this feature).
- **FR-013**: Every key in this spec MUST keep the meaning it has in the
  COSMIC popup, with no new key added that the COSMIC popup lacks.
  `Ctrl+J` and `Ctrl+K` MUST stay unbound in the popup.
- **FR-014**: The backend MUST accept a request for each of: copy username,
  copy one-time code, copy website, and retry; the COSMIC popup already has
  these as actions. A backend that does not know a request MUST ignore it.

### Key Entities

- **Copy chord**: a key that copies one named value of an item (username,
  one-time code, website) and closes the popup. Existing: `Enter` for the
  main value. New: `Ctrl+U`, `Ctrl+O`, `Ctrl+L`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Copying a username or a one-time code takes the same number of
  key presses as copying the password: the shortcut, the search text, one
  chord.
- **SC-002**: Every key in the COSMIC popup's list and field-list tables,
  except `Ctrl+,`, `Ctrl+J` and `Ctrl+K`, does the same thing in the Mango
  popup (checked row by row against the gap table above).
- **SC-003**: None of the new copy chords puts a value into the popup's
  drawn content, its logs, or the clipboard history.
- **SC-004**: A chord the open item cannot serve leaves the clipboard as it
  was, in 100% of tries.

## Assumptions

- The keys follow the COSMIC popup's defaults; the COSMIC popup's ability
  to rebind them is not carried over (the Mango popup has no preferences
  screen, specs/016).
- The backend (`cosmic-pass serve`) already performs these copies for the
  COSMIC popup; exposing them to the Mango popup is a small addition there,
  shipped and pushed before the Mango side builds, as in specs/016.
- "Retry" checks the session again, which is what the COSMIC popup's retry
  does; it does not sign in.
- The status lines already show where sign-in is offered (specs/016); no new
  status text is needed apart from the missing-value notices, which the
  backend already words.
- Out of scope: `Ctrl+,` (preferences), `Ctrl+J`/`Ctrl+K`, rebinding keys,
  mouse behaviour, and any change to the COSMIC popup.
