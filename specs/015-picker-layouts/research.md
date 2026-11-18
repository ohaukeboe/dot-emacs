# Research: Picker Layouts

Versions in the laptop closure on 2026-11-15: quickshell 0.3.2, cliphist 0.7.0,
xdg-desktop-portal-wlr 0.8.5, wl-clipboard 2.3.0, wtype 0.5.

## R1. How a caller names the layout

- **Decision**: `mango-pick [--layout tiles|sources|clipboard] PROMPT`. The
  script passes the layout as a fourth argument of the `picker` IPC target's
  `open` call (`""` when absent). The shell maps an unknown or empty name to
  the list.
- **Rationale**: one optional flag keeps every current call (`mango-pick Power`)
  valid; the IPC target has a single caller, `mango-pick`, so changing its arity
  breaks nothing else.
- **Alternatives**: a layout guessed from the prompt or the lines (fragile: a
  caller's prompt change would switch layout); a separate IPC target per layout
  (three copies of the FIFO handling).

## R2. Telling the caller "copy only" without changing the line

- **Decision**: the reply on the FIFO stays the picked line; a second,
  alternate pick (Ctrl+Enter in the clipboard layout) prefixes the FIFO reply
  with a tab-terminated `alt` marker, which `mango-pick` strips and turns into
  exit status 10. Exit 0 = normal pick, 1 = cancel, 10 = alternate pick.
- **Rationale**: stdout stays exactly the picked line (the dmenu contract).
  Exit codes 10+ for custom keys are rofi's convention (`-kb-custom-1`), so
  callers written for dmenu ignore them as failure and callers that care can
  branch.
- **Alternatives**: printing a prefix on stdout (breaks the contract); a second
  FIFO (more moving parts for one bit).

## R3. Keeping passwords out of the clipboard history (FR-023)

- **Decision**: nothing to build. `cliphist store` 0.7.0 does nothing when
  `CLIPBOARD_STATE=sensitive` (`cliphist.go:70`), and `wl-paste --watch`
  (wl-clipboard ≥ 2.2) sets that variable when the source offers
  `x-kde-passwordManagerHint` with `secret`. Home Manager's `services.cliphist`
  already runs `wl-paste --watch cliphist store`. The plan adds a quickstart
  check and a one-line comment at `services.cliphist` naming the dependency.
- **Rationale**: the filter already sits where the spec wants it, when the
  history is recorded.
- **Risk**: whether Proton Pass offers the hint is unverified. If it does not,
  its passwords are stored like text (spec edge case: Delete is the remedy).
  Quickstart step Q6 checks it.

## R4. Screencast lines and window details

- **Decision**: parse xdpw's dmenu lines as written in `chooser.c:114-127`:
  `Monitor: <name> <description>` and `Window: <title> (<identifier>)`. The
  output name is the first word; the window identifier is the last
  parenthesised group (titles may contain parentheses). Match the identifier
  to `foreign_toplevel_id` in `mmsg get all-clients` for `appid` and `tags`.
  Screens map to `Quickshell.screens` by name for size and scale.
- **Rationale**: `foreign_toplevel_id` is the same `ext-foreign-toplevel`
  identifier xdpw prints (checked live: `e5289e08…` for Emacs), so the match is
  exact; no title matching, which the spec's assumption allowed for.
- **Alternatives**: Quickshell's `ToplevelManager` (wlr-foreign-toplevel) has
  `appId` but neither the ext identifier nor Mango tags.
- **Spec note**: the spec's assumption "matched by title; first match on a
  shared title" is superseded by the exact identifier match; behaviour only
  improves.

## R5. Live thumbnails

- **Decision**: `ScreencopyView { captureSource: <ShellScreen>; live: true }`
  from `Quickshell.Wayland`, shown only while the picker is open. Mango offers
  `zwlr_screencopy_manager_v1` and `ext_image_copy_capture_manager_v1`; a view
  with `hasContent` false shows the placeholder (FR-009 degrade).
- **Rationale**: built into the installed Quickshell; no extra process.

## R6. Paste into the previous window (FR-017)

- **Decision**: `mango-clip-pick` sets the clipboard with `wl-copy`, then runs
  `wtype -M shift -k Insert -m shift`. Mango offers
  `zwp_virtual_keyboard_manager_v1`, which wtype needs. The popup is closed
  before the FIFO reply is written (`Picker.choose`), so keyboard focus is back
  on the previous window when wtype runs; a 50 ms sleep covers the compositor
  handing focus back.
- **Alternatives**: Ctrl+V (terminals ignore it), per-app keys (spec Q1 chose
  Shift+Insert).

## R7. Clipboard rows, preview and Delete

- **Decision**: rows come from `cliphist list` as today. An image row is a line
  matching `[[ binary data <size> <format> <W>x<H> ]]`; its detail is
  `<format> · <W>×<H> · <size>`. A text row's line count needs the full entry,
  so each visible row decodes its entry once (`cliphist decode | wc -l` in a
  Quickshell `Process`), cached by cliphist id. The preview decodes the
  selected entry: text read through a `StdioCollector` capped at 64 KiB, an
  image written to `$XDG_RUNTIME_DIR/mango-pick/<id>` and shown by `Image`.
  Delete runs `cliphist delete` with the line on stdin, then drops the row.
- **Rationale**: only visible rows (about ten) decode, so a 750-entry history
  costs ten small processes per scroll page, not 750.
- **Alternatives**: line count only in the preview (would change FR-015).

## R8. Tile items

- **Decision**: a tiles line is `label<TAB>icon[<TAB>confirm]`. The picker
  returns `label` alone. Icons are keys into `Icons.qml` (Nerd Font glyphs, the
  rail's existing set); an unknown or missing key shows a generic glyph.
- **Rationale**: tabs never appear in the power menu labels; the cliphist
  layout already uses the tab as a field separator.
