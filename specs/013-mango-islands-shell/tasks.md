# Tasks: Mango Islands Shell

**Input**: Design documents from `specs/013-mango-islands-shell/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/popup-ipc.md](contracts/popup-ipc.md),
[contracts/usage-record.md](contracts/usage-record.md),
[quickstart.md](quickstart.md)

**Design reference**: canvas https://claude.ai/artifact/7Aoe3evXhJMATtbNH24pmN,
artboards "D · Islands, refined", "D + Claude usage popup", "D + KDE Connect
in quick controls", "KDE Connect detail page". Sizes, radii and spacing
come from those artboards (read them with the Artifact tool, paths
`project/AltRefined.dc.html`, `project/ExtUsage.dc.html`,
`project/ExtKde.dc.html`, `project/ExtKdePage.dc.html`).

**Tests**: two fixture tests are in scope because the plan's constitution
check names them (`checks.context-statusline`, `checks.agent-usage`).
Everything else is verified by Nix evaluation and build, `qmllint`, and the
manual checks in [quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, no dependency on an
  unfinished task. Most Mango tasks edit `modules/mango/default.nix`, so few
  are [P].
- **[Story]**: the user story the task belongs to (US1–US4).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file before
  `nix build` or `nix flake check`.
- Every package comes from nixpkgs; no new flake input or nvfetcher entry.
- Mango parts sit inside `mkIf cfg.enable` in `modules/mango/default.nix`;
  Home Manager config goes under `home-manager.users.${config.user.username}`.
- Colours come only from the `palette` attrset (T002). No other colour
  literal anywhere under `modules/mango`.
- Executables are referenced by store path (`lib.getExe`, `getExe'`), never
  bare names, in waybar strings, scripts and QML.
- Shell goes through `writeShellApplication` in `modules/mango/scripts.nix`.
- After each phase run the build gate in [quickstart.md](quickstart.md):
  `nix fmt` (revert unrelated churn), `nix flake check`, then
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`.
- The agent sandbox cannot deploy, log in, or reach the phone. Steps marked
  **(user)** are the user's, on `laptop`.
- Never commit without an explicit instruction; stage and report.

---

## Phase 1: Setup

- [X] T001 Create the beads epic `Mango islands shell (specs/013)` linking
  `specs/013-mango-islands-shell/`, and file one child ticket per task below,
  keeping the `T0NN` ids in titles.

---

## Phase 2: Foundational (blocks US1–US4)

- [X] T002 In `modules/mango/default.nix`, replace the `bg`, `card`,
  `accent` let-bindings with one attrset
  `palette = { frame = "111111"; app = "171717"; island = "212121";
  raised = "2c2c2c"; fg = "cabab4"; dim = "948985"; onAccent = "171717"; }`
  and point every existing use at it without changing the look further:
  `swaybg` and lock background → `frame`; Mango `border_color` → `app`;
  `focus_color` and other accent uses → `fg`; foot background → `app`, foot
  foreground → `fg`; fuzzel, mako and swaylock colours → `island`/`fg`;
  waybar's `#c8c5c7` → `fg`, `#555555` and `#888888` → `dim`. Drop the
  "COSMIC Dark accent" comment (research R2, R12).
- [X] T003 Split `modules/mango/quickshell/shell.qml` into
  `shell.qml` (ShellRoot, state, IPC, Process helpers), `Config.qml`
  (`pragma Singleton`; every `@placeholder@`: the seven palette keys, `mmsg`,
  `brightnessctl`, `powerMenu`), `RailPopup.qml`, `Controls.qml` (tiles plus
  Wi-Fi, Bluetooth and sound pages), `Calendar.qml`, and one file per shared
  component (`RailText.qml`, `Toggle.qml`, `Arrow.qml`, `PageHeader.qml`,
  `ListRow.qml`, `SectionLabel.qml`), plus a `qmldir` registering the
  singleton. Behaviour and look unchanged. In `default.nix`, build
  `quickshellDir` by copying the directory and running `replaceVars` on
  `Config.qml` only; make `qmlCheck` lint every `.qml` in the directory
  (research R11).
- [X] T004 Run the build gate; **(user)** deploy and confirm the session
  looks and behaves as before apart from the new colours.

**Checkpoint**: one palette, split QML, no behaviour change.

---

## Phase 3: User Story 1 - One coherent islands look (P1) 🎯 MVP

**Goal**: rail as three capsules, darker frame, every popup redrawn in D's
style and dropping from its capsule.

**Independent test**: quickstart "Story 1", steps 1–6.

- [X] T005 [US1] In `modules/mango/default.nix` waybar `style`, make the
  rail three capsules (FR-001): `window#waybar { background: transparent; }`;
  `.modules-left, .modules-center, .modules-right` get
  `background: #${palette.island}; border-radius: 18px; margin: 8px 12px 0;`
  with inner padding from the artboard; set `height = 36`. Workspaces:
  active pill `fg` fill with `onAccent` text, idle dots `dim`. Keep
  `margin: 0` on the centre capsule's sides.
- [X] T006 [US1] In `modules/mango/quickshell/shell.qml` and
  `RailPopup.qml`, set `railEdge` to the new rail height plus gap
  (36 + 8 + 8 = 52), popup radius 22, colour `Config.island`, no border, a
  drop shadow, and x-position under the opening capsule: `endAligned` popups
  12 px from the right edge, centred ones under the clock (FR-005). If the
  content is taller than the screen minus `railEdge`, wrap it in a
  `Flickable` so it scrolls (edge case "must still fit").
- [X] T007 [P] [US1] Add `modules/mango/quickshell/CapsuleSlider.qml`
  (44 px high, radius 22, `raised` track, `fg` fill, icon inside in
  `onAccent`), `ToggleRow.qml` (44 px round toggle: `fg` fill when on,
  `raised` when off; label; `dim` sub-label; arrow that sets `root.page`),
  `Segmented.qml` (`raised` capsule, selected segment `fg` with `onAccent`
  text) and `RoundButton.qml` (36 px, `raised`). Icons are Nerd Font glyphs.
- [X] T008 [US1] Redraw the tiles page in
  `modules/mango/quickshell/Controls.qml` with T007's components, in the
  artboard's order (FR-008): volume `CapsuleSlider` (tap the icon to open
  the sound page), brightness `CapsuleSlider`, `ToggleRow`s for Wi-Fi,
  Bluetooth and Microphone with live sub-labels ("Connected", "On", "Off",
  "Muted"), `Segmented` power profile (Saver / Balanced / Performance, the
  last hidden without a performance profile), footer with battery
  percentage and state, a lock `RoundButton` (runs swaylock) and a power
  `RoundButton` (runs `powerMenu`). Add `swaylock` to `Config.qml`.
- [X] T009 [US1] Restyle the Wi-Fi, Bluetooth and sound pages in
  `Controls.qml` and `Calendar.qml` to the palette and shapes (FR-009):
  round back button, `ListRow` radius 14 with `raised` active state,
  `Toggle` pills as in T007, today as an `fg` circle with `onAccent` text,
  round month buttons. No function from spec 012 is lost.
- [X] T010 [US1] Add IPC target `shell` with `openTarget(): string` in
  `modules/mango/quickshell/shell.qml`, and on `openTargetChanged` run
  `pkill -RTMIN+8 waybar` by store path (`procps`), added to `Config.qml`
  (contracts/popup-ipc.md, research R3).
- [X] T011 [US1] In `modules/mango/scripts.nix` add `mango-rail-module`
  (`writeShellApplication`; argument `clock` or `controls`) that prints one
  JSON line: `text` (for `clock`: `date '+%a %-d %b  %H:%M'`; for
  `controls`: the gear glyph) and `class` `open` when
  `qs -c mango ipc call shell openTarget` equals its target; a failed IPC
  call means "not open". In `default.nix` replace the built-in `clock` with
  `custom/clock` (`interval = 5`, `signal = 8`, on-click calendar toggle)
  and give `custom/controls` the same `exec` and `signal = 8`. CSS: date in
  `dim`, time bold `fg` (FR-007); `.open` on the gear is a 28 px `fg` circle
  with `onAccent` glyph, `.open` on the clock is unchanged apart from the
  popup below it (FR-006).
- [X] T012 [US1] Run the build gate; **(user)** deploy and walk quickstart
  "Story 1".

**Checkpoint**: MVP. The shell matches artboard D with no new features.

---

## Phase 4: User Story 2 - Claude usage at a glance (P2)

**Goal**: usage pill on the rail and a usage popup, fed by two state files.

**Independent test**: quickstart "Story 2", steps 1–7.

- [X] T013 [US2] **Verify first (research R4)**: **(user)** capture one
  status-line input (temporarily `tee` it from `context-statusline`, or run
  Claude Code with a throwaway status-line command) and record in
  `specs/013-mango-islands-shell/research.md` the exact `rate_limits` field
  names and the unit of `resets_at`. If the field is absent, stop and ask
  the user before using the OAuth-endpoint fallback.
- [X] T014 [US2] Create `workstation/agents/usage.nix` with
  `options.agents.usage.enable` (`mkEnableOption`), import it from
  `workstation/agents/default.nix`, and pass a `usageTap` boolean from
  `workstation/agents/statusline.nix` into `context-statusline`.
- [X] T015 [US2] In `workstation/agents/packages/context-statusline.nix`,
  when `usageTap` is true and the input has rate limits, write
  `${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage/limits.json` as
  `{updated_at, session:{used_percentage, resets_at}, weekly:{…}}` (epoch
  seconds, percentages 0–100) to a temp file in the same directory, then
  `mv`. Any failure is swallowed: output and exit code of the status line
  never change (contracts/usage-record.md).
- [X] T016 [P] [US2] Extend `tests/context-statusline.nix`: input with rate
  limits writes the expected `limits.json`; input without them leaves an
  existing file untouched; an unwritable state directory still prints the
  normal status line and exits 0.
- [X] T017 [P] [US2] Write `workstation/agents/packages/agent-usage-tokens.py`
  and build it in `usage.nix` with `writers.writePython3Bin`. It reads
  `~/.claude/projects/**/*.jsonl` (honouring `CLAUDE_CONFIG_DIR`) modified
  in the last 8 days, counts each assistant message once keyed on
  `(message.id, requestId)`, sums input + output + cache-creation +
  cache-read tokens, and writes `tokens.json` atomically: `days` with
  exactly 7 entries, oldest first, today last, zero-filled; `models` sorted
  by tokens descending; `week_tokens`; `updated_at`. On failure it keeps the
  previous content and adds `"error": "<one line>"`. It logs counts only,
  never message content.
- [X] T018 [P] [US2] Add `tests/agent-usage.nix` and `checks.agent-usage`
  in `flake.nix` (fixture-only, with a "see the file" comment like its
  neighbours): fixture transcripts with a duplicated streamed message, two
  models, a day outside the window and a malformed line; assert the JSON.
- [X] T019 [US2] In `workstation/agents/usage.nix`, under
  `mkIf cfg.enable`, add `systemd.user.services.agent-usage` (oneshot, runs
  the collector) and `systemd.user.timers.agent-usage` (`OnStartupSec=1min`,
  `OnUnitActiveSec=15min`). Enable `agents.usage.enable` where Claude Code
  is enabled.
- [X] T020 [US2] In `modules/mango/scripts.nix` extend `mango-rail-module`
  with `usage`: read `limits.json` with jq; missing or unparseable → print
  an empty line; else `text` `"<n>%"`, `percentage` n, `class` `open`
  and/or `stale` (`updated_at` older than 30 minutes); a limit whose
  `resets_at` has passed reads 0. In `default.nix` add
  `custom/claude-usage` before `network` in `modules-right`:
  `format = "{icon} {text}"`, `format-icons` the eight Nerd Font
  circle-slice glyphs, `interval = 60`, `signal = 8`, on-click
  `usage toggle`. CSS: `.open` is an `fg` pill with `onAccent` text,
  `.stale` is `dim` (FR-011, FR-018, research R7).
- [X] T021 [US2] Add `modules/mango/quickshell/Usage.qml` and target
  `usage` in `shell.qml` (IpcHandler `toggle`, `endAligned` popup, width
  360). Two `FileView`s watch `limits.json` and `tokens.json`. Layout per
  the artboard (FR-012, FR-013): header (44 px `fg` circle, "Claude Code",
  "updated N min ago" in `dim`, marked stale after 30 minutes, refresh
  `RoundButton` running `systemctl --user start agent-usage.service` by
  store path, failures ignored); two limits with label, percentage, 8 px
  meter and reset text ("Resets in 2 h 14 min" under a day, else weekday
  and time); `Segmented` "By day" / "By model" bound to `usageView`; seven
  day rows (today bold with `fg` bar, others `dim` bar, scaled to the
  busiest day) or model rows (scaled to the heaviest); footer with
  `week_tokens` and "Open Claude". Missing `tokens.json` shows limits only;
  a record `error` is shown in `dim` above the rows. `usageView` resets when
  the popup closes.
- [X] T022 [US2] "Open Claude" (FR-017): in `modules/mango/default.nix`
  pass a `claude` placeholder into `Config.qml` built from the Home Manager
  `programs.claude-code` package when it is enabled, else an empty string;
  the button runs `${terminal} <claude>`, closes the popup, and is hidden
  when the string is empty.
- [X] T023 [US2] Run the build gate; **(user)** deploy and walk quickstart
  "Story 2" and the first "Off cases" item.

**Checkpoint**: usage pill and popup work; hidden when there is no data.

---

## Phase 5: User Story 3 - Phone in quick controls (P2)

**Goal**: phone card with four actions, and a phone icon on the rail.

**Independent test**: quickstart "Story 3 and 4", steps 1, 2, 4, 5.

- [X] T024 [US3] **Verify first (research R8)**: in
  `modules/mango/default.nix`, when `services.kdeconnect.enable` is true,
  add `${pkgs.kdePackages.kdeconnect-kde}/lib/qt-6/qml` to the Quickshell
  unit's `QML_IMPORT_PATH` (`systemd.user.services.quickshell.Service
  .Environment`) and to `qmlCheck`'s `-I` list. Add a minimal
  `modules/mango/quickshell/Phone.qml` that imports `org.kde.kdeconnect`
  and instantiates `DevicesModel`. Build; **(user)** deploy and confirm
  `journalctl --user -u quickshell` shows no import error. If it fails, stop
  and ask the user before the `kdeconnect-cli` fallback.
- [X] T025 [US3] In `Phone.qml`, expose the **active phone** (data-model:
  "the first reachable paired device in the model's order; if none is
  reachable, the first paired one, shown as 'Not reachable'") with name,
  reachable, battery and charging (battery interface factory) and unread
  count (`NotificationsModel` row count). Only copy `Phone.qml` into
  `quickshellDir` and load it from `Controls.qml` (through a `Loader`) when
  KDE Connect is enabled, so nothing references the module otherwise
  (FR-023).
- [X] T026 [US3] Draw the phone card in `Phone.qml` and place it in
  `Controls.qml` under the Microphone row (FR-019): `raised` panel radius
  18, 44 px `fg` circle with phone glyph, name, sub-label "Connected · 78% ·
  2 notifications" or "Not reachable" in `dim`, arrow setting
  `root.page = "phone"`. With no paired device show one `ToggleRow`-shaped
  row "Set up phone" that opens the same page.
- [X] T027 [US3] Add the four actions under the card as a 4-column row of
  52 px `raised` buttons (FR-020, research R9), disabled when not
  reachable: Ring (find-my-phone `ring()`); Clipboard (`sendClipboard()`);
  Send file (close the popup, open a `FileDialog` from `QtQuick.Dialogs`,
  share the chosen URL; on failure or cancel-after-error send a desktop
  notification with `notify-send` by store path); Browse (SFTP
  `mountAndWait()`, then `xdg-open` the mount point by store path, popup
  closes).
- [X] T028 [US3] Rail icon (FR-021, research R10): in
  `modules/mango/scripts.nix` extend `mango-rail-module` with `phone`
  (prints the phone glyph when `kdeconnect-cli -a --id-only` is non-empty,
  else an empty line). In `default.nix`, only when KDE Connect is enabled,
  add `custom/phone` after `custom/claude-usage` with `signal = 9`,
  `interval = "once"`, on-click `controls toggle`. In `Phone.qml` run
  `pkill -RTMIN+9 waybar` when the reachable count changes.
- [X] T029 [US3] In `modules/mango/default.nix` set
  `services.kdeconnect.indicator = false` and remove the
  `kdeconnect-indicator` `bindToSession` line (FR-024).
- [X] T030 [US3] Run the build gate; **(user)** deploy and walk the Story 3
  steps.

**Checkpoint**: daily phone actions are one click from quick controls.

---

## Phase 6: User Story 4 - Phone detail page (P3)

**Goal**: a `phone` page inside quick controls.

**Independent test**: quickstart "Story 3 and 4", step 3.

- [X] T031 [US4] In `Phone.qml` add the `phone` page (shown when
  `root.page === "phone"`, FR-022) per the artboard: `PageHeader`
  "KDE Connect"; device header with 52 px circle, name, "Connected · 78% ·
  charging"; the four actions as a 2-column grid of 48 px buttons reusing
  T027's handlers.
- [X] T032 [US4] Add the notifications section: "Notifications" label with
  "Clear all" (`dismissAll` on the model), then one `raised` row per
  notification, newest first, with app, text and time; clicking a
  dismissable row dismisses it on the phone. Empty list shows "No
  notifications" in `dim`.
- [X] T033 [US4] Add "Other devices": each other paired device with
  "Paired · not reachable" or "Connected"; tapping a reachable one makes it
  the active phone for this session; a "Forget" action unpairs. Then "Pair
  a new device": lists reachable unpaired devices and sends a pairing
  request on click, showing "Pairing…" until the model reports paired.
- [X] T034 [US4] Run the build gate; **(user)** deploy and walk Story 4,
  then the KDE Connect "Off cases" item by building once with
  `services.kdeconnect.enable = false`.

**Checkpoint**: all four stories work independently.

---

## Phase 7: Polish & Cross-Cutting

- [X] T035 [P] Update `GLOSSARY.md`: **Rail** (top edge, three capsules in
  the island colour on the frame); **Quick controls** (adds the phone card);
  new **Island**, **Usage pill**, **Phone card**, each with an _Avoid_ line.
- [X] T036 [P] Add a line at the top of
  `specs/012-mango-rail-bar/contracts/popup-ipc.md` pointing to
  `specs/013-mango-islands-shell/contracts/popup-ipc.md` as its successor.
- [X] T037 Check FR-010 and FR-004: confirm `dim` on `island` and on
  `raised` is at least 4.5:1 (adjust `palette.dim` once if not), and that
  `grep -rnE '[0-9a-fA-F]{6}' modules/mango` matches only the `palette`
  definition and store hashes.
- [X] T038 **(user)** Walk every remaining quickstart item, including the
  second monitor and the COSMIC session, and compare against the four
  artboards (SC-001).

---

## Dependencies

- Phase 2 blocks everything. T002 before T003.
- US1 (T005–T012) blocks US2's and US3's Mango tasks, which reuse its
  components (`Segmented`, `RoundButton`, `ToggleRow`) and the `shell` IPC.
- US2's writer tasks (T013–T019) touch only `workstation/agents` and
  `tests`; they can run alongside US1.
- US3 before US4. US2 and US3 are independent of each other.
- T013 gates T015; T024 gates T025–T033.

## Parallel examples

- During US1: T007 (new component files) alongside T005 (waybar CSS).
- After T014–T015: T016, T017 and T018 together (three different files).
- Polish: T035 and T036 together.
- With two workers: one takes US2's writer side (T013–T019) while the other
  finishes US1.

## Implementation strategy

1. **MVP**: Phases 1–3. The shell matches design D; nothing new to maintain.
2. **Usage**: Phase 4. Lands in two commits' worth: writers (agents module),
   then pill and popup (Mango module).
3. **Phone**: Phases 5–6.
4. **Polish**: Phase 7.

Stop after any checkpoint; each leaves a working session.
