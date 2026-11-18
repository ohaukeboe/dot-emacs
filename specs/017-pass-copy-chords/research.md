# Research: Proton Pass Copy Chords

## R1. Backend: new intents, not new behaviour

- **Decision**: add four intents to `cosmic-pass serve`, each mapped to a
  message the reducer already handles for the COSMIC popup:
  `copy_username` → `Msg::CopyUsername`, `copy_totp` → `Msg::CopyTotp`,
  `copy_url` → `Msg::CopyUrl`, `retry` → `Msg::Startup`.
- **Rationale**: `src/app/keys.rs` maps the COSMIC chords to exactly these
  messages. `copy_with` already picks the target item in both modes
  (`target_item()`), falls back from username to email, and posts the
  "This item has no …" notice when the value is missing (FR-001 to FR-004).
  The copy runs through the same `start_copy` path as `Enter`, so FR-005
  holds by construction.
- **Alternatives considered**: copying through `activate` with the index of
  the username or code row. Rejected: it needs the field list's order in
  the shell, works only in fields mode, and duplicates the reducer's choice
  of username-or-email.

## R2. Paging and sign-in need no backend change

- **Decision**: send the existing `page_up`/`page_down` in fields mode too,
  and the existing `login` for `Ctrl+Shift+S`.
- **Rationale**: `move_selection` already moves the field highlight by a
  page and clears any reveal (FR-009). `StartLogin` is already ignored
  unless sign-in is offered; the shell also gates on `can_login`, as the
  Sign in button does (FR-010).

## R3. Where retry is gated

- **Decision**: the shell sends `retry` only while `session` is `locked`,
  `error` or `cli_missing` (FR-011).
- **Rationale**: this is the COSMIC popup's rule — its "Try again" button is
  shown for exactly those three states (`src/app/view/status.rs`). The
  intent→message conversion in `serve` is pure and has no model, so the
  gate sits where the state is drawn. `Startup` while signed in is harmless
  anyway (it re-probes and reloads), so a stray `retry` costs a refresh.
- **Alternatives considered**: gating in the reducer. Rejected: it would
  change the COSMIC popup's code path for a rule its view already enforces.

## R4. `Left`, `Right`, `Shift+Tab`

- **Decision**: `Right` sends `open_fields` only in the item list with an
  empty query (otherwise the text field moves its cursor); `Left` and
  `Shift+Tab` (`Qt.Key_Backtab`) send `back` in the field list.
- **Rationale**: matches the COSMIC contract. `back` rather than `escape`:
  in the COSMIC popup `Esc` cancels a pending fetch first, `Left` goes back
  directly; `Msg::Back` is that.
- In fields mode the query field is collapsed but focused (specs/016), so
  `Left`/`Right` must be consumed there to keep a hidden cursor from moving.

## R5. Compatibility

- **Decision**: no protocol version bump.
- **Rationale**: contract rule 5 of `serve`: an unknown `t` is logged and
  skipped. A new shell against an old backend gets no-op chords (FR-014);
  the two are pinned together in `flake.lock` anyway.

## R6. Hint line

- **Decision**: item list hint becomes
  "Enter copy password · Ctrl+U username · Ctrl+O code · Tab all fields ·
  F5 refresh"; fields hint adds nothing new (the chords are listed in the
  contract). If the line does not fit at the popup's width, `F5 refresh`
  goes first.
- **Rationale**: FR-012 asks for `Ctrl+U` and `Ctrl+O` on the hint line;
  `Ctrl+L` is rarer and stays contract-only, as in the COSMIC footer.
