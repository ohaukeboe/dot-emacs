# Tasks: Picker Layouts

**Input**: Design documents from `specs/015-picker-layouts/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/mango-pick.md, quickstart.md

**Tests**: no test tasks; the spec asks for none. Verification is the build
gate (`qmlCheck`, shellcheck) plus the manual checks in `quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an open task)
- **[Story]**: the user story the task serves (US1–US4)

Paths are relative to the repository root. QML lives in
`modules/mango/quickshell/`; `default.nix` fills `Config.qml` placeholders
through `pkgs.replaceVars` (`modules/mango/default.nix:104`).

---

## Phase 1: Setup

- [X] T001 Add the term **Picker** to `GLOSSARY.md` next to **Rail** and
  **Island**: the clock-island popup that `mango-pick` opens, in one of four
  layouts (list, tiles, sources, clipboard); _Avoid_: menu, dmenu, launcher

---

## Phase 2: Foundational (blocks every story)

- [X] T002 Extend `mango-pick` in `modules/mango/scripts.nix` per
  `contracts/mango-pick.md`: parse an optional `--layout LAYOUT` before
  PROMPT, pass LAYOUT (`""` when absent) as the fourth argument of
  `quickshell ipc … call picker open`, and on a reply of `alt<TAB>VALUE`
  print `VALUE` and exit 10; empty reply exits 1; anything else prints and
  exits 0
- [X] T003 Change the `picker` IPC handler in
  `modules/mango/quickshell/shell.qml` to
  `open(prompt: string, items: string, reply: string, layout: string)` and
  pass `layout` to `Picker.open`
- [X] T004 In `modules/mango/quickshell/Picker.qml` add
  `property string layout` (`"list"`, `"tiles"`, `"sources"`, `"clipboard"`;
  per data-model.md "an empty or unknown `layout` is `list`"), set it in
  `open()`, and add `chooseAlt(i)`, which replies `"alt\t" + value` (R2);
  keep cancel-on-close and one-request-at-a-time unchanged
- [X] T005 Add a `returnValue(line)` function to `Picker.qml` that `choose()`
  replies with: the label field (text before the first tab) for `tiles`, the
  whole line otherwise; keep `label()` for display
- [X] T006 In `modules/mango/quickshell/PickerList.qml` show the current list
  only when `Picker.layout === "list"` and load the layout's component
  (`PickerTiles`, `PickerClip`, `PickerSources`) otherwise, through a
  `Loader` so only one layout exists at a time; create the three files as
  empty `Item` stubs so the build passes
- [X] T007 Build gate: `git add` the new files, `nix fmt`,
  `nix flake check`, and
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`

**Checkpoint**: callers without `--layout` behave as before (US4 holds).

---

## Phase 3: User Story 1 - Power menu as tiles (Priority: P1) 🎯 MVP

**Goal**: the power menu is a row of five icon tiles; Lock and Suspend run on
one pick, Log out, Reboot and Power off arm first.

**Independent Test**: quickstart Q3 and Q4; press `3` in the power menu to
suspend.

- [X] T008 [P] [US1] Add `logout`, `sleep` and `restart` glyphs to
  `modules/mango/quickshell/Icons.qml` (Material Design Nerd Font code points,
  like the existing `lock` and `power`) and a `generic` glyph for unknown keys
- [X] T009 [US1] Add arming to `modules/mango/quickshell/Picker.qml`:
  `property int armed: -1`; a `pick(i)` used by tiles that, per data-model.md,
  replies when item `i` has no `confirm` field, arms when it has one and
  `armed !== i`, and replies when `armed === i`; reset `armed` to -1 on any
  other key, selection move, `open()` or close
- [X] T010 [US1] Build `modules/mango/quickshell/PickerTiles.qml` from mockup
  artboard A: one wrapping row of 96×104 tiles (radius 18, `Config.raised`
  plus a 2 px `Config.fg` ring when selected), each with the `Icons` glyph
  named by field 2 (`generic` when missing), the label, and its digit; an armed
  tile shows "Press N again"; a hint line "← → move · Enter or 1–N pick · Esc
  cancel"; no filter field
- [X] T011 [US1] Key handling in `PickerTiles.qml`: Left/Right move and stop at
  the ends, digits 1–9 call `Picker.pick` for that tile (beyond the count: do
  nothing), Enter picks the selection, click picks, Esc closes; take focus when
  `Rail.openTarget` becomes `"picker"`
- [X] T012 [US1] Change `mango-power-menu` in `modules/mango/scripts.nix` to
  print tab-separated `label\ticon[\tconfirm]` lines
  (`Lock lock`, `Log out logout confirm`, `Suspend sleep`,
  `Reboot restart confirm`, `Power off power confirm`) and call
  `mango-pick --layout tiles Power`; the `case` on the label stays
- [ ] T013 [US1] Build gate as T007, switch, run quickstart Q3 and Q4 (build gate passed; manual quickstart pending)

**Checkpoint**: power menu works as tiles; other callers unchanged.

---

## Phase 4: User Story 2 - Clipboard with preview (Priority: P2)

**Goal**: Super+v opens search, rows with type and size, a preview; Enter
pastes, Ctrl+Enter copies only, Delete forgets.

**Independent Test**: quickstart Q6–Q10.

- [X] T014 [P] [US2] Add a `cliphist` placeholder to
  `modules/mango/quickshell/Config.qml` (`readonly property string cliphist:
  "@cliphist@"`) and `cliphist = getExe pkgs.cliphist;` to the `replaceVars`
  set in `modules/mango/default.nix`
- [X] T015 [P] [US2] Add a comment above `services.cliphist` in
  `modules/mango/default.nix`: `cliphist store` skips entries
  `wl-paste --watch` marks `CLIPBOARD_STATE=sensitive` (password managers'
  `x-kde-passwordManagerHint`), which is what keeps passwords out of the
  picker (spec FR-023, research R3)
- [X] T016 [US2] Add clip-entry parsing to `Picker.qml` per data-model.md:
  `id` (before the tab), `kind` `image` when the preview matches
  `[[ binary data <size> <format> <W>x<H> ]]` else `text`, and for images
  `format`, `width`, `height`, `size`
- [X] T017 [US2] Add `forget(i)` to `Picker.qml`: run
  `Config.cliphist delete` with the raw line on stdin (`Quickshell.execDetached`
  through `/bin/sh -c 'printf "%s\n" "$1" | "$2" delete'`), remove the item
  from `items`, keep `index` on the next row, and stay open; deleting the last
  item leaves "No matches" shown
- [X] T018 [US2] Build `modules/mango/quickshell/PickerClip.qml` from mockup
  artboard C: a 40 px search capsule (search glyph, prompt label, `TextInput`
  bound to `Picker.query`, "M of N" count), a 300 px row list (first line bold
  when selected; detail `text · N lines` or `<format> · W×H · <size>`) and a
  preview pane in `Config.app` with a hint line "Enter paste · Ctrl+Enter copy
  only · Del forget"
- [X] T019 [US2] Lazy line counts in `PickerClip.qml`: each visible row runs a
  `Process` (`/bin/sh -c 'printf "%s\n" "$1" | "$2" decode | wc -l'`) once,
  cached in a map keyed by cliphist id on `Picker` (R7)
- [X] T020 [US2] Preview in `PickerClip.qml`: on selection change decode the
  entry; text through a `StdioCollector` capped at 64 KiB
  (`… decode | head -c 65536`), shown monospace in a scrolling `Flickable`;
  images written to `$XDG_RUNTIME_DIR/mango-pick/<id>` and shown by an `Image`
  with `fillMode: Image.PreserveAspectFit`; a failed decode shows the detail
  line instead
- [X] T021 [US2] Keys in `PickerClip.qml`: typing filters, Up/Down and
  C-p/C-n move, Enter calls `Picker.choose`, Ctrl+Enter `Picker.chooseAlt`,
  Delete `Picker.forget`, Alt+1–9 pick, Esc closes
- [X] T022 [US2] Change `mango-clip-pick` in `modules/mango/scripts.nix`: add
  `wtype` and `coreutils` to `runtimeInputs`; run
  `mango-pick --layout clipboard Clipboard`, capturing its status; on 0 run
  `cliphist decode | wl-copy`, `sleep 0.05`, then
  `wtype -M shift -k Insert -m shift`; on 10 only `wl-copy`; on anything else
  exit 0 without touching the clipboard
- [ ] T023 [US2] Build gate as T007, switch, run quickstart Q6–Q10 (build gate passed; manual quickstart pending)

**Checkpoint**: clipboard layout works; power tiles still work.

---

## Phase 5: User Story 3 - Screencast source cards (Priority: P3)

**Goal**: the share chooser shows screen cards with live thumbnails and window
rows with app and tag.

**Independent Test**: quickstart Q5.

- [X] T024 [US3] Add source parsing to `Picker.qml` per research R4:
  `Monitor: <name> <desc>` gives `name` (first word) and `description`;
  `Window: <title> (<id>)` gives `title` and `identifier` from the last
  parenthesised group (`/^Window: (.*) \(([^()]*)\)$/`), else the whole rest
  as the title
- [X] T025 [US3] Add a client lookup to `Picker.qml`: when a `sources` request
  opens, run `Config.mmsg get all-clients` once, parse the JSON and map
  `foreign_toplevel_id` to `{ appid, tags }`; a missing match leaves app and
  tag empty
- [X] T026 [US3] Build `modules/mango/quickshell/PickerSources.qml` from mockup
  artboard B: title from the prompt, a "Screens" group as a two-column grid of
  cards (a `ScreencopyView { captureSource: <screen>; live: true }` 128 px
  tall, a `Config.app` placeholder while `!hasContent` or when no
  `Quickshell.screens` entry matches, the name, description and
  `width×height` in device pixels), then a "Windows" group of 40 px rows
  (initial-letter badge, title, `app · tag N`); hide an empty group
- [X] T027 [US3] Keys in `PickerSources.qml`: typing filters window rows by
  title or app (cards stay), arrows move left/right across cards and up/down
  between cards and rows, Enter picks, Alt+1–9 pick counted over cards then
  rows, click picks, Esc closes
- [X] T028 [US3] Change `chooser_cmd` in `modules/mango/default.nix` to
  `…/bin/mango-pick --layout sources 'Share your screen'`
- [ ] T029 [US3] Build gate as T007, switch, run quickstart Q5 (restart the
  `xdg-desktop-portal-wlr` user service first: its chooser is read at start) (build gate passed; manual quickstart pending)

---

## Phase 6: User Story 4 - Other callers keep the list (Priority: P3)

**Goal**: no layout or an unknown one gives today's list.

**Independent Test**: quickstart Q1 and Q2.

- [ ] T030 [US4] Run quickstart Q1 and Q2 against the switched system; fix any
  difference from the list in `PickerList.qml` or `mango-pick` (build gate passed; manual quickstart pending)

---

## Phase 7: Polish

- [X] T031 [P] Update the header comments of `Picker.qml`, `PickerList.qml`
  and `shell.qml` (the IPC usage line) to name the layouts and status 10
- [X] T032 Run the full build gate, then `/speckit-converge` or a review of the
  diff against spec FR-001–FR-023

---

## Dependencies & Execution Order

- Phase 1 has no dependencies.
- Phase 2 (T002–T007) blocks all stories.
- US1, US2 and US3 each depend only on Phase 2 and touch different layout
  files, but all three edit `Picker.qml`, so do their `Picker.qml` tasks one
  story at a time.
- US4 is verification of Phase 2 and can run any time after it.
- Polish follows the stories it documents.

## Parallel Opportunities

- T008 (Icons.qml) alongside T009 (Picker.qml).
- T014 and T015 (default.nix and Config.qml) alongside T016–T017.
- Within a story, the layout file and the caller in `scripts.nix` are
  independent once `Picker.qml` is done: T010–T011 with T012, T018–T021 with
  T022, T026–T027 with T028.

## Implementation Strategy

1. Phase 1 and Phase 2, then stop: every caller still works (US4).
2. US1 (tiles) as the MVP: smallest layout, proves `--layout` end to end.
3. US2 (clipboard), then US3 (sources); each ends on its own build gate and
   quickstart checks, so either can ship without the other.

---

## Phase 8: Convergence

- [X] T033 [US2] In `modules/mango/quickshell/PickerClip.qml`, treat an image
  the `Image` element cannot load as a failed preview: set
  `pane.previewFailed = true` when the preview `Image`'s `status` becomes
  `Image.Error` (e.g. `onStatusChanged`), so the pane shows the detail line
  (`<format> · W×H · <size>`) instead of an empty box; today only a non-zero
  `cliphist decode` exit does this, per spec Edge Cases ("A clipboard image
  cannot be decoded for the preview") and FR-016 (partial)
- [X] T034 [US1] In `modules/mango/quickshell/PickerTiles.qml` `Keys.onPressed`,
  disarm on a digit beyond the tile count: when `event.key - Qt.Key_1 >=
  tiles.count`, set `Picker.armed = -1` and do nothing else (today
  `Picker.pick` returns early and an armed tile stays armed), per FR-007a
  ("Any other key … MUST disarm") and spec Edge Cases (digits beyond the
  tiles do nothing) (partial)
