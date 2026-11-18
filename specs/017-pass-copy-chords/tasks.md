# Tasks: Proton Pass Copy Chords

**Input**: design documents in `specs/017-pass-copy-chords/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/keys.md](contracts/keys.md), [quickstart.md](quickstart.md)

**Tests**: the spec asks for none here. `cosmic-pass` gates every change on
`just check` (its constitution), so the backend tasks carry their tests.

**Two repositories**: Phase 2 is in `~/projects/cosmic-pass` and must be
committed and pushed (by the user) before Phase 2's last task bumps the
flake input here. Nothing in this repository builds against the new
intents before that.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no unfinished dependency)
- **[Story]**: the user story the task belongs to (US1 to US4)

---

## Phase 1: Setup

None. No new file, option or dependency (plan, Structure Decision).

---

## Phase 2: Foundational (backend intents, blocks every story)

**Purpose**: the four `serve` intents of research R1. US3's keys need none
of them, but the bump happens once, here.

- [X] T001 In `~/projects/cosmic-pass/src/serve/protocol.rs` add four unit
  variants to `enum Intent` (serde `snake_case` tags `copy_username`,
  `copy_totp`, `copy_url`, `retry`) and map them in `impl From<Intent> for
  Msg` to `Msg::CopyUsername`, `Msg::CopyTotp`, `Msg::CopyUrl` and
  `Msg::Startup`. Extend the `every_intent_reaches_its_message` table in the
  same file from 16 to 20 cases
- [X] T002 In `~/projects/cosmic-pass/tests/serve_protocol.rs` add tests
  through the real `serve` loop with the existing `backend()` fixture
  (GitHub item: username `octocat`, TOTP `CODE`): query `git` first
  (GitHub sorts after Bank), then
  (a) `copy_username` copies `octocat` and the next snapshot has
  `visible == false`;
  (b) `copy_totp` copies `CODE`;
  (c) in fields mode with the Password row selected, `copy_username` still
  copies `octocat`;
  (d) for an item with no website, `copy_url` copies nothing, `visible`
  stays `true` and `notice` is not null;
  (e) after `FakeBackend` reports `Locked`, `retry` produces a snapshot with
  `session == "checking"` or later.
  Call `serve.assert_guarantees()` at the end of each
- [X] T003 [P] Add the four rows of
  [data-model.md](data-model.md) to the intent tables in
  `~/projects/cosmic-pass/specs/004-serve-mode/contracts/serve-protocol.md`
  and `~/projects/cosmic-pass/specs/004-serve-mode/data-model.md`, keeping
  the tables aligned and at most 90 characters wide
- [X] T004 Run `just check` in `~/projects/cosmic-pass` (with
  `CARGO_BUILD_JOBS=4 CARGO_PROFILE_DEV_DEBUG=line-tables-only
  NEXTEST_TEST_THREADS=4`; `/run/user/1000/just` must exist). Stage the
  files of T001–T003 and ask the user to commit and push
- [X] T005 After T004 is pushed: `nix flake update cosmic-pass` here and
  confirm `flake.lock` locks the commit from T004

**Checkpoint**: the locked backend accepts the four intents.

---

## Phase 3: User Story 1 - Copy the username or one-time code (P1) 🎯 MVP

**Goal**: `Ctrl+U` and `Ctrl+O` copy and close, from either list.

**Independent Test**: quickstart K1, K2, K4, K5 (`Ctrl+U`, `Ctrl+O`).

- [X] T006 [US1] In `modules/mango/quickshell/PassPopup.qml`, query field
  `Keys.onPressed`: add `const shift = (event.modifiers &
  Qt.ShiftModifier) !== 0;` and, before the existing `Ctrl+R` branch,
  `ctrl && !shift && key === Qt.Key_U` → `{ t: "copy_username" }` and
  `ctrl && !shift && key === Qt.Key_O` → `{ t: "copy_totp" }`, in both
  modes. Also add `!shift` to the existing `Ctrl+R` reveal branch so
  `Ctrl+Shift+R` (US4) cannot reach it
- [X] T007 [US1] In the same file change the item-list `Hint` text to
  "Enter copy password · Ctrl+U username · Ctrl+O code · Tab all fields ·
  F5 refresh"; if it wraps at the popup's width in the T008 screenshot,
  drop "· F5 refresh" (research R6)
- [X] T008 [US1] Build gate: `nix fmt`, `nix flake check`,
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`,
  `just qs-check`; then the verify-quickshell skill to screenshot the open
  popup and check the hint line

**Checkpoint**: after the user deploys, K1, K2, K4, K5 pass.

---

## Phase 4: User Story 2 - Copy the website (P2)

**Goal**: `Ctrl+L` copies the first website and closes.

**Independent Test**: quickstart K3, K5 (`Ctrl+L`).

- [X] T009 [US2] In `modules/mango/quickshell/PassPopup.qml`
  `Keys.onPressed`: `ctrl && !shift && key === Qt.Key_L` →
  `{ t: "copy_url" }`, in both modes, next to T006's branches

---

## Phase 5: User Story 3 - Move around with the COSMIC popup's keys (P2)

**Goal**: `Right`, `Left`, `Shift+Tab` and paging in the field list.

**Independent Test**: quickstart K6, K7, K8, K9.

- [X] T010 [US3] In `modules/mango/quickshell/PassPopup.qml`
  `Keys.onPressed`:
  `key === Qt.Key_Right && !popup.fieldsMode && queryField.text === ""` →
  `{ t: "open_fields" }` (use the query field's actual id);
  in fields mode, `key === Qt.Key_Left || key === Qt.Key_Backtab` →
  `{ t: "back" }`; in fields mode `Left`/`Right` are always accepted so the
  collapsed field's cursor does not move. In the item list, `Left`, and
  `Right` with text, fall through to `return` (text cursor). Do not bind
  `Ctrl+J` or `Ctrl+K` (FR-013)
- [X] T011 [US3] In the same handler drop `&& !popup.fieldsMode` from the
  `PageUp` and `PageDown` branches (research R2: the reducer pages the field
  highlight and masks the reveal)

---

## Phase 6: User Story 4 - Sign in and retry from the keyboard (P3)

**Goal**: `Ctrl+Shift+S` and `Ctrl+Shift+R` from the status view.

**Independent Test**: quickstart K10, K11.

- [X] T012 [US4] In `modules/mango/quickshell/PassPopup.qml`
  `Keys.onPressed`, first in the chain:
  `ctrl && shift && key === Qt.Key_S` → `{ t: "login" }` only when
  `popup.snap.can_login`, otherwise accepted and nothing sent;
  `ctrl && shift && key === Qt.Key_R` → `{ t: "retry" }` only when
  `popup.snap.session` is `"locked"`, `"error"` or `"cli_missing"`
  (research R3), otherwise accepted and nothing sent

---

## Phase 7: Polish

- [X] T013 [P] Replace the keys table in
  `specs/016-proton-pass-quick-access/contracts/shell.md` with the table in
  [contracts/keys.md](contracts/keys.md) section 2, and add its note about
  the COSMIC defaults under it
- [X] T014 Final gate: `nix fmt`, `nix flake check`, the toplevel build of
  every machine in `machines/machines.nix`, `just qs-check`; stage and ask
  the user to commit; the user deploys and runs quickstart K1–K12

---

## Dependencies & Execution Order

```text
T001 → T002 → T004 → T005;  T003 [P] with T001–T002
T005 → T006 → T007 → T008 (US1, MVP)
T008 → T009 (US2), T010 → T011 (US3), T012 (US4)   # same file: one at a time
T009, T011, T012 → T013 [P], T014
```

- T006, T009–T012 all edit the same handler in `PassPopup.qml`: do them in
  order, not in parallel. T006 adds the `shift` variable the others use.
- T013 touches only the 016 contract and can run any time after T005.

## Parallel Opportunities

- T003 (docs in `cosmic-pass`) alongside T001–T002.
- T013 (contract here) alongside any of T006–T012.

## Implementation Strategy

1. Phase 2 in `cosmic-pass`, user pushes, bump (T001–T005).
2. US1 (T006–T008): the asked-for keys; deployable on its own.
3. US2–US4 (T009–T012): one sitting, same handler.
4. Polish and final gate (T013–T014).
