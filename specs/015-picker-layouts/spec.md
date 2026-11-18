# Feature Specification: Picker Layouts

**Feature Branch**: `015-picker-layouts`

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Redesign the Mango Quickshell picker (mango-pick,
Picker.qml/PickerList.qml in modules/mango/quickshell) with three layouts chosen
per use, from the mockups at https://claude.ai/artifact/KFJa8rRuj2v7UYzzLiXBkS:
(A) Tiles for short fixed menus such as the power menu — a row of icon tiles,
picked with Left/Right, Enter or digit keys 1-N, no filter field; (B) Grouped
sources for the screencast portal's chooser — "Monitor: <name>" lines as screen
cards with live thumbnails (Quickshell ScreencopyView) and resolution,
"Window: <title>" lines as a list with app and tag, typing filters windows,
Alt+N picks; (C) List with preview pane for the clipboard history — a search
bar with a match count, rows showing type and size (text lines, or image
format/dimensions/size), a preview of the selected entry, Enter pastes,
Ctrl+Enter copies only, Delete forgets the entry via cliphist delete.
mango-pick must tell the shell which layout to use; the plain list stays as the
fallback for any other caller. The dmenu contract stays: lines on stdin, the
choice on stdout through the FIFO, exit 1 on cancel."

This feature builds on the picker added in commit `31bae88` (the **Rail**'s
clock-**Island** popup that `mango-pick` opens) and on the look from
`specs/013-mango-islands-shell`. Today every caller gets the same filterable
list. This feature gives three callers a layout fitted to their content and
keeps that list for everyone else. Mockups: artboards A, B and C of
https://claude.ai/artifact/KFJa8rRuj2v7UYzzLiXBkS (artboard 0 is the current
list).

## Clarifications

### Session 2026-11-15

- Q: When you press Enter on a clipboard entry, how should the picker paste it into the window you came from? → A: Always send Shift+Insert, which most apps and terminals read as paste.
- Q: Should the clipboard preview show every entry in full, or hide ones that look like passwords? → A: Never store entries a password manager marks as sensitive, so they never show at all.
- Q: Should Reboot and Power off run straight away when picked from the tiles, or ask for confirmation first? → A: Log out, Reboot and Power off arm on the first press and run on the second.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Power menu as tiles (Priority: P1)

The user opens the power menu (from quick controls or its key binding). Instead
of a list with a filter field, the clock island opens to a single row of five
tiles — Lock, Log out, Suspend, Reboot, Power off — each with an icon, a label
and its number. The first tile is selected. The user picks with the arrow keys
and Enter, by pressing the tile's number, or by clicking it.

**Why this priority**: The power menu is the most used picker, has a fixed and
short set of choices, and is the simplest layout; it also proves that a caller
can choose a layout at all, which the other two stories need.

**Independent Test**: Run the power menu, press `3`; the machine suspends.
Run it again, press Right twice then Enter; same result. Run it, press `4`
then Esc; nothing happens. Run it, press `4` twice; the machine reboots.

**Acceptance Scenarios**:

1. **Given** the power menu is not open, **When** the user opens it, **Then**
   the clock island shows five tiles in one row, no filter field, and the
   first tile selected.
2. **Given** the tiles are shown, **When** the user presses `1` or `3`,
   **Then** Lock or Suspend runs and the popup closes.
3. **Given** the tiles are shown, **When** the user presses `2`, `4` or `5`,
   **Then** that tile is selected and armed, shows "Press 5 again" (its own
   digit), and nothing runs; pressing the same digit again runs it.
4. **Given** a tile is armed, **When** the user presses any other key,
   moves the selection, or picks another tile, **Then** the tile disarms and
   nothing runs.
5. **Given** the tiles are shown, **When** the user presses Left or Right,
   **Then** the selection moves one tile and stops at either end.
6. **Given** the tiles are shown, **When** the user presses Enter or clicks a
   tile, **Then** Lock or Suspend runs; Log out, Reboot or Power off arms and
   runs on a second Enter or click.
7. **Given** the tiles are shown, **When** the user presses Esc or clicks
   outside the popup, **Then** the popup closes and no action runs.

---

### User Story 2 - Clipboard history with preview (Priority: P2)

The user presses Super+v. The popup shows a search bar labelled Clipboard with
a match count ("3 of 48"), a list of history entries, and a preview pane. Each
row shows the start of the entry and a dim detail line: for text, the number of
lines; for an image, its format, dimensions and size. The preview pane shows
the selected entry in full: text as text, an image as the picture. The user can
paste the entry into the window they came from, only copy it, or forget it.

**Why this priority**: Clipboard entries are long or binary, and the plain
list shows only a truncated first line, so the user often cannot tell entries
apart. Forgetting an entry (a pasted password, a large image) has no way in
today.

**Independent Test**: Copy three texts and one screenshot. Press Super+v, type
part of the second text: the count drops and the preview shows it in full.
Press Enter: it is pasted into the focused window. Reopen, select the
screenshot: the preview shows the image. Press Delete: the row disappears and
the entry is absent the next time the picker opens.

**Acceptance Scenarios**:

1. **Given** the clipboard history holds entries, **When** the user opens the
   clipboard picker, **Then** it shows the search bar with "N of N", the rows
   newest first with the first one selected, and that entry's preview.
2. **Given** the picker is open, **When** the user types, **Then** rows that do
   not match are hidden, the count updates, and the selection and preview move
   to the first match.
3. **Given** a text entry is selected, **When** the user presses Enter,
   **Then** the popup closes, the entry becomes the clipboard content, and it
   is pasted into the window that had focus before the picker opened.
4. **Given** an entry is selected, **When** the user presses Ctrl+Enter,
   **Then** the popup closes and the entry becomes the clipboard content
   without being pasted.
5. **Given** an entry is selected, **When** the user presses Delete, **Then**
   the entry is removed from the history, its row disappears, the count drops,
   the selection moves to the next row, and the popup stays open.
6. **Given** an image entry is selected, **When** the preview shows, **Then**
   it shows the picture scaled to fit, and the row's detail shows format,
   dimensions and size.

---

### User Story 3 - Screencast source cards (Priority: P3)

An application asks to share the screen. The popup titled "Share your screen"
shows a Screens group, one card per display with a live thumbnail of what is
on it, its name, model and resolution; and a Windows group, one row per window
with its title, application and tag. Typing filters the windows. The user picks
with the arrow keys and Enter, Alt+1 to Alt+9, or a click.

**Why this priority**: Screen sharing happens less often than the other two,
and the thumbnails depend on live screen capture; but picking the wrong output
in a meeting is the costliest mistake the current list allows, since
`eDP-1` and `HDMI-A-1` say little about which screen is which.

**Independent Test**: With an external display attached, start a screen share
in a browser. Both screens appear as cards with live thumbnails; the windows
appear below. Type part of a window title: only matching windows remain and the
screen cards stay. Press Alt+2: the browser shares the external display.

**Acceptance Scenarios**:

1. **Given** a share request with two displays and several windows, **When**
   the picker opens, **Then** it shows one card per display with a thumbnail,
   name, model and resolution, then the windows as rows, and the first screen
   card selected.
2. **Given** the picker is open, **When** the user types, **Then** only
   windows whose title or application matches remain; the screen cards stay.
3. **Given** the picker is open, **When** the user presses Alt+N, **Then** the
   Nth source counted over cards then rows is shared.
4. **Given** the picker is open, **When** the user moves with the arrow keys,
   **Then** the selection moves across cards and down into the window rows and
   back.
5. **Given** a thumbnail cannot be captured, **When** the picker opens,
   **Then** that card shows a blank placeholder and is still pickable.
6. **Given** the picker is open, **When** the user presses Esc, **Then** the
   share request is cancelled and the application is told so.

---

### User Story 4 - Other callers keep the list (Priority: P3)

Any caller of the picker that names no layout, or a layout the shell does not
know, gets today's filterable list unchanged, so existing scripts keep working.

**Why this priority**: Protects behaviour that already works; small.

**Independent Test**: `printf 'a\nb\n' | mango-pick Test` shows the current
list and prints the picked line.

**Acceptance Scenarios**:

1. **Given** a caller that passes no layout, **When** it runs the picker,
   **Then** the current list appears and behaves as today.
2. **Given** a caller that names an unknown layout, **When** it runs the
   picker, **Then** the current list appears.

---

### Edge Cases

- The power menu tiles get more items than fit in one row on the current
  screen: the row wraps rather than clipping.
- Digit keys in the tiles layout beyond the number of tiles do nothing.
- The screencast picker gets only window lines, or only screen lines: the
  empty group is not shown.
- A screen line names a display that is no longer connected: its card shows the
  name with a placeholder and no resolution; picking it returns the line as
  given.
- A window's application or tag cannot be found: the row shows the title alone.
- The clipboard history is empty: the picker closes at once and reports a
  cancel, as the current list does with no lines.
- The user deletes the last remaining clipboard entry: the list shows
  "No matches" and the popup stays open until Esc.
- A clipboard image cannot be decoded for the preview: the preview shows the
  detail line instead of the picture.
- A very long text entry: the preview shows the start and scrolls; the row
  shows only its first line.
- A second picker request arrives while one is open: the first is cancelled,
  as today.
- The paste target window closed while the picker was open: the entry is still
  copied to the clipboard.
- A password copied from Proton Pass: it is on the live clipboard but absent
  from the history, so Super+v does not show it.
- A secret copied by an application that does not mark it as sensitive: it is
  stored like any text; Delete is the remedy.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A caller of the picker MUST be able to name a layout: `tiles`,
  `sources`, `clipboard`, or none.
- **FR-002**: With no layout or an unknown one, the picker MUST behave exactly
  as the current list.
- **FR-003**: In every layout the dmenu contract MUST hold: the caller's lines
  in, the picked line returned unchanged, and a cancel reported as a cancel
  (exit status 1) on Esc, a click outside, another popup opening, or a new
  picker request.
- **FR-004**: The tiles layout MUST show the items as one row of tiles with an
  icon, label and number each, no filter field, and the first tile selected.
- **FR-005**: The tiles layout MUST pick by Left/Right then Enter, by digit
  1–9 for the first nine tiles, and by click.
- **FR-006**: A caller of the tiles layout MUST be able to give each item an
  icon; an item without one MUST show a generic icon.
- **FR-007**: The power menu MUST use the tiles layout with an icon for each of
  its five items, and mark Log out, Reboot and Power off as needing
  confirmation.
- **FR-007a**: A caller of the tiles layout MUST be able to mark an item as
  needing confirmation. Picking a marked item by digit, Enter or click MUST
  only arm it, showing "Press N again" on the tile; the same pick again MUST
  return it. Any other key, selection move or pick MUST disarm it. Unmarked
  items MUST return on the first pick.
- **FR-008**: The sources layout MUST group `Monitor:` lines as screen cards
  and `Window:` lines as rows, screens first, and hide an empty group.
- **FR-009**: Each screen card MUST show a live thumbnail of that display, its
  name, its model when known, and its resolution.
- **FR-010**: Each window row MUST show the title, and the application and
  Mango tag when they can be found.
- **FR-011**: In the sources layout, typing MUST filter window rows by title or
  application; screen cards MUST stay visible.
- **FR-012**: The sources layout MUST pick by arrow keys then Enter, by Alt+1 to
  Alt+9 counted over cards then rows, and by click.
- **FR-013**: The screencast portal's chooser MUST use the sources layout.
- **FR-014**: The clipboard layout MUST show a search bar with the caller's
  prompt and an "M of N" count, the entry rows, and a preview pane of the
  selected entry.
- **FR-015**: Each clipboard row MUST show the entry's first line and a detail
  line: the number of lines for text; format, dimensions and size for an image.
- **FR-016**: The preview pane MUST show a text entry in full in a monospace
  face, scrolling when long, and an image entry as the picture scaled to fit.
- **FR-017**: In the clipboard layout, Enter MUST set the entry as the
  clipboard content and paste it into the window that had focus before the
  picker opened, by sending Shift+Insert to that window.
- **FR-018**: In the clipboard layout, Ctrl+Enter MUST set the entry as the
  clipboard content without pasting.
- **FR-019**: In the clipboard layout, Delete MUST remove the selected entry
  from the clipboard history, update the list and count, and keep the popup
  open.
- **FR-020**: Super+v MUST open the clipboard layout.
- **FR-021**: Every layout MUST open in the clock island's popup, in the
  session palette, like the current list, and close the same ways.
- **FR-022**: The keys of each layout MUST be shown in the popup (a hint line)
  so the user need not remember them.
- **FR-023**: Clipboard content that the copying application marks as
  sensitive (a password manager's hint) MUST NOT be added to the clipboard
  history, so it never appears in the clipboard layout's rows or preview.
  It MUST still be pasteable from the live clipboard as usual.

### Key Entities

- **Picker request**: a prompt, the lines, the layout name (optional), and
  the place to answer. One at a time.
- **Picker item**: one input line. For tiles, it may carry an icon name and a
  needs-confirmation mark. For
  sources, its `Monitor:`/`Window:` kind decides its group. For clipboard, its
  history id decides what Delete removes and what the preview shows.
- **Layout**: list (default), tiles, sources or clipboard; decides how items
  are drawn and which keys pick.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Lock and Suspend take one key press after the menu opens; Log
  out, Reboot and Power off take two presses of the same key, and no single
  stray key press ends the session.
- **SC-002**: A user can tell which display a screen card shares without
  knowing output names, on the first attempt, with two displays attached.
- **SC-003**: The selected clipboard entry is readable in full, or visible as
  a picture, without picking it.
- **SC-004**: An unwanted clipboard entry can be forgotten in two key presses
  after opening the picker (select, Delete).
- **SC-005**: Every existing caller that names no layout behaves the same as
  before, verified by running it.
- **SC-006**: Every layout opens and is ready for input in under 200 ms after
  the request, as the current list does.
- **SC-007**: No layout leaves a waiting caller hanging: every way the popup
  closes returns a choice or a cancel.

## Assumptions

- The layout is named by the caller on the `mango-pick` command line; how it
  reaches the shell is a planning decision.
- Tile icons and confirmation marks come from the caller (for example
  tab-separated fields after the label), so the power menu stays the only
  place that knows its items; the returned line is the label alone.
- An armed tile stays armed until another input; there is no timeout.
- "Paste" sends Shift+Insert to the window that had focus, after the
  clipboard is set; foot, GTK and Qt apps, browsers and Emacs all read it as
  paste. An app that does not ignores it, and the entry stays on the
  clipboard.
- Sensitive entries are recognised only by the marker the copying application
  sets (for example the `x-kde-passwordManagerHint` type password managers
  offer); the picker does not guess from content. Filtering happens when the
  history is recorded, not in the picker.
- Forgetting a clipboard entry happens while the picker stays open, so the
  picker itself removes it from the history rather than returning it to the
  caller.
- Window application and tag come from the compositor's window list, matched
  by the window identifier the screencast request carries (research R4), so
  windows with the same title are told apart.
- Thumbnails need live screen capture, which Quickshell provides on Mango; if
  it is unavailable, cards show placeholders (FR-009 degrades, picking still
  works).
- Only screens get thumbnails; window thumbnails are out of scope.
- The mockups are the visual reference; exact sizes follow the session's
  existing popup measures.
- Out of scope: new pickers for other callers, a launcher redesign, fuzzy
  matching (filtering stays substring), and mouse-wheel tile scrolling.
