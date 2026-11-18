# Tasks: Proton Pass Quick Access

**Input**: Design documents from `specs/016-proton-pass-quick-access/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/serve-protocol.md, contracts/shell.md, quickstart.md

**Tests**: test tasks only for the backend, in the `cosmic-pass` repository,
as `contracts/serve-protocol.md` lists them. This repository gets none
(constitution I and III); its verification is the build gate (`qmlCheck`)
plus `just qs-check` and the manual checks in `quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an open task)
- **[Story]**: the user story the task serves (US1–US4)

Paths are relative to this repository's root, except those starting with
`~/projects/cosmic-pass/`, which are in the backend's repository. QML lives
in `modules/mango/quickshell/`; `modules/mango/quickshell.nix` fills
`Config.qml` placeholders through `pkgs.replaceVars`.

Commits and pushes are the user's: where a task needs one, stage, summarize
and ask.

---

## Phase 1: Setup

- [X] T001 Add the term **Quick access** to `GLOSSARY.md` next to **Picker**:
  the Rail popup on `Super+Space` that finds a Proton Pass item and copies
  one of its fields, drawn by the shell and driven by `cosmic-pass serve`;
  _Avoid_: password manager, vault popup, cosmic-pass (that is the backend)

---

## Phase 2: Foundational (blocks every story)

### Backend, in `~/projects/cosmic-pass`

- [X] T002 Create `~/projects/cosmic-pass/specs/004-serve-mode/spec.md` by
  running `/speckit-specify` in `~/projects/cosmic-pass` (that repository is
  a Spec Kit repo) for the `serve` subcommand, and copy
  `contracts/serve-protocol.md` from here to
  `~/projects/cosmic-pass/specs/004-serve-mode/contracts/serve-protocol.md`
  as the authoritative copy
- [X] T003 In `~/projects/cosmic-pass/src/cli.rs` add
  `Command::Serve { clipboard_clear_secs: u32 }` with
  `--clipboard-clear-secs` required and range-checked by clap against
  `config::CLIPBOARD_CLEAR_RANGE` (`10..=600`), so a value outside it exits 2
  before any output
- [X] T004 Create `~/projects/cosmic-pass/src/serve.rs` with a serde `Intent`
  enum tagged by `"t"` holding exactly the 16 intents of the contract's
  table (`show`, `hide`, `query {text}`, `next`, `prev`, `page_down`,
  `page_up`, `select {index}`, `copy_primary`, `open_fields`,
  `activate {index: Option<usize>}`, `reveal`, `back`, `escape`, `refresh`,
  `login`) and `impl From<Intent> for Msg` mapping each to the `Msg` the
  table names; unknown fields are ignored; export the module from
  `~/projects/cosmic-pass/src/lib.rs`
- [X] T005 In `~/projects/cosmic-pass/src/serve.rs` add a serde `Snapshot`
  struct with the fields of the contract (`v: 1`, `visible`, `session`,
  `session_detail`, `can_login`, `login`, `mode`, `query`, `selected`,
  `rows`, `item`, `fields`, `busy`, `stale`, `notice`, `cli_warning`) and
  `Snapshot::of(&Model, now)` that projects the model: `session` from
  `SessionState` (`Locked` is `"locked"`, `Error(text)` is `"error"` with
  `session_detail`), `mode` `"list"` or `"fields"` from `Mode`
  (`Preferences` cannot occur), `rows` from `view.results`, `fields` from
  `Model::actions()` with `value` set only for a stored plain value or
  `Model::revealed_value(index)`, `totp` from `Model::revealed_totp()`,
  `stale` from `Model::stale_notice()`. A copied value must appear nowhere.
  Before naming it, read what sets `SessionState::Locked` in
  `src/core/state.rs`; if it is not the keyring, correct the `locked` line
  in both contract files and the status text in T023
- [X] T006 In `~/projects/cosmic-pass/src/serve.rs` add
  `pub fn main(clipboard_clear_secs: u32) -> ExitCode`: a tokio runtime; a
  `Model` with default `Preferences`, `clipboard_clear_secs` set and
  `max_results` set to 50 (inside `MAX_RESULTS_RANGE`); `Deps`
  built as `app` builds them but with `save_preferences: false`; feed
  `Msg::Startup`; then loop over stdin lines, parse each as `Intent` (log and
  skip a line that does not parse), run `Model::update`, run each `Effect`
  through `runtime::execute` (`Step::Future` and `Step::Stream` feed their
  messages back, `ShowWindow`/`HideWindow`/`Unhandled` need no action), send
  `Msg::Tick(now)` each second while `Snapshot.fields` holds a `totp`, and
  write a snapshot line to stdout after every update whose snapshot differs
  from the last written one; exit 0 when stdin closes. Never log a snapshot
  or a field value. Dispatch `Command::Serve` to it in
  `~/projects/cosmic-pass/src/main.rs` before `app::run`
- [X] T007 Create `~/projects/cosmic-pass/tests/serve_protocol.rs` using
  `testing::FakeBackend` and `insta`, covering the contract's test list:
  every intent reaches its `Msg`; one snapshot per state of spec FR-019
  (loading, signed out, out of date, keyring unavailable, tool missing, tool
  older than tested, session store unreadable, failed copy); guarantees 1 to
  3 including a refresh that reshapes the revealed item; a garbage line is
  skipped; closing stdin exits 0; `--clipboard-clear-secs 5` exits 2; with
  2,000 fake items a `query` intent yields its snapshot in under 100 ms
  (SC-003) and an empty query lists the most used items first, 50 at most
- [X] T008 Document `cosmic-pass serve` in `~/projects/cosmic-pass/README.md`
  (one section: what it is for, the flag, a link to the contract), run
  `just check` in `~/projects/cosmic-pass`, then stage and ask the user to
  commit and push

### This repository

- [X] T009 After T008 is pushed: `nix flake update cosmic-pass` (updates
  `flake.lock`), and confirm the locked revision is the commit that has
  `serve`. Then do T030 at once, so the contract is not kept twice
- [X] T010 [P] Declare `options.modules.mango.pass.clipboardClearSeconds` in
  `modules/mango/default.nix`: `types.ints.between 10 600`, default `90`,
  description "Seconds a secret copied from the Proton Pass quick access
  stays on the clipboard."
- [X] T011 [P] Add `passBackend` (string, the backend's path) and
  `passClearSecs` (int) properties with `@passBackend@` / `@passClearSecs@`
  placeholders to `modules/mango/quickshell/Config.qml`, and fill them in
  `modules/mango/quickshell.nix`: `passBackend` is
  `getExe inputs.cosmic-pass.packages.${pkgs.stdenv.hostPlatform.system}.default`
  (take `inputs` as a module argument, as `modules/cosmic-de/default.nix`
  does), `passClearSecs` is
  `toString cfg.pass.clipboardClearSeconds`
- [X] T012 Create `modules/mango/quickshell/Pass.qml`, a `pragma Singleton`
  per data-model.md: `property var snapshot: ({})`, `property bool alive`,
  `property string openedUrl: ""`; a `Process` running
  `[Config.passBackend, "serve", "--clipboard-clear-secs", String(Config.passClearSecs)]`
  with `stdinEnabled: true` and a `SplitParser` on stdout that replaces
  `snapshot` whole with `JSON.parse(line)` (ignore a line that does not
  parse; never log it); `function send(intent)` writing
  `JSON.stringify(intent) + "\n"`; on exit set `alive` false, reset
  `snapshot` to `{}` and restart after 2 s with a `Timer`, at most 5 times
  in a row (a parsed snapshot resets the count); then stay stopped until the
  popup is next opened; a `Connections`
  on `Rail` that sends `{t:"show"}` when `openTarget` becomes `"pass"` and
  `{t:"hide"}` when it stops being `"pass"`; and when a snapshot has
  `visible === false` while `Rail.openTarget === "pass"`, call `Rail.close()`
- [X] T013 Create `modules/mango/quickshell/PassPopup.qml` as an empty
  `ColumnLayout` stub, then in `modules/mango/quickshell/shell.qml` add
  `IpcHandler { target: "pass"; function toggle(): void { Rail.toggle("pass"); } }`
  and a `Variants { model: Quickshell.screens; RailPopup { target: "pass";
  island: Component { ClockIsland {} }; PassPopup {} } }` beside the
  picker's, and add `"pass"` to the `openTarget` comment in
  `modules/mango/quickshell/Rail.qml`
- [X] T014 [P] In `modules/mango/compositor.nix` change
  `"bind=SUPER,space,spawn,${protonPass}"` to spawn
  `${getExe pkgs.quickshell} -c mango ipc call pass toggle`, delete the
  now-unused `protonPass` binding, and reword the comment above it (the
  quick-access popup, specs/016)
- [X] T015 Build gate: `git add` the new files, `nix fmt` (revert unrelated
  churn), `nix flake check`, and
  `nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'`; set the option to `5` once and
  confirm evaluation fails, then restore it

**Checkpoint**: `Super+Space` opens an empty popup on the focused monitor
and closes it again; `pgrep -f 'cosmic-pass serve'` finds one process.

---

## Phase 3: User Story 1 - Copy a password from the keyboard (P1) 🎯 MVP

**Goal**: shortcut, type, Enter; the password is on the clipboard and the
popup is gone.

**Independent Test**: quickstart V1 and V2.

- [X] T016 [US1] In `modules/mango/quickshell/PassPopup.qml` build the item
  list from the design system (`modules/mango/quickshell/README.md`): a
  `QueryInput` that is cleared and focused whenever `Rail.openTarget`
  becomes `"pass"` and sends `{t:"query", text}` on every change (the field
  owns the query; never write `Pass.snapshot.query` back into it, research
  R3); below it a scrolling list of `ListRow`s over `Pass.snapshot.rows`
  showing `title`, `subtitle` and `vault`, the row at `Pass.snapshot.selected`
  highlighted and kept in view; shown only when `Pass.snapshot.mode` is
  `"list"`
- [X] T017 [US1] In `modules/mango/quickshell/PassPopup.qml` handle the item
  list's keys per `contracts/shell.md`: `Up`/`Ctrl+P` send `prev`,
  `Down`/`Ctrl+N` send `next`, `PageUp`/`PageDown` send `page_up`/
  `page_down`, `Enter` sends `copy_primary`, `F5` sends `refresh`, `Esc`
  sends `escape`; a click on a row sends `{t:"select", index}` then
  `copy_primary`
- [X] T018 [US1] In `modules/mango/quickshell/PassPopup.qml` show one status
  line (`Detail`) where the rows would be when there are none: "Loading
  items…" while `session` is `unknown` or `checking`, or `busy.refreshing`
  with no rows; "No matches" when the query is not empty; and show
  `Pass.snapshot.notice` under the list when set
- [X] T019 [US1] Build gate as T015, `just qs-check`, deploy, then run
  quickstart V1 and V2; screenshot the open list with the `verify-quickshell`
  skill

**Checkpoint**: the feature replaces the full application for copying a
password.

---

## Phase 4: User Story 2 - Copy another field of an item (P2)

**Goal**: Tab lists every field of the selected item; Enter copies one.

**Independent Test**: quickstart V3.

- [X] T020 [US2] In `modules/mango/quickshell/PassPopup.qml` add the field
  list, shown when `Pass.snapshot.mode` is `"fields"`: a header with
  `Pass.snapshot.item.title` and `subtitle`, then a `ListRow` per entry of
  `Pass.snapshot.fields` showing `label` and, on the right, `value` when
  `secret` is false or dots when it is true and `value` is `null`; the row
  at `Pass.snapshot.selected` highlighted; the `QueryInput` keeps focus but
  ignores typing in this mode
- [X] T021 [US2] In `modules/mango/quickshell/PassPopup.qml` add the keys:
  `Tab` in the item list sends `open_fields`; in the field list `Up`/
  `Ctrl+P`/`Down`/`Ctrl+N` send `prev`/`next`, `Enter` sends
  `{t:"activate", index: null}`, a click on a row sends
  `{t:"activate", index}`, `Esc` sends `escape` (back to the item list with
  the same query and selection), `F5` sends `refresh`. Pointer (FR-004,
  `contracts/shell.md`): each item-list row gets a trailing `IconButton`
  that sends `{t:"select", index}` then `open_fields`; the field list's
  header gets a back `IconButton` that sends `escape`; the popup's title row
  gets a refresh `IconButton` that sends `refresh`
- [X] T022 [US2] Build gate as T015, `just qs-check`, deploy, then run
  quickstart V3; screenshot the field list with the `verify-quickshell` skill

---

## Phase 5: User Story 3 - Know why it is not working (P2)

**Goal**: the popup always names its state and offers the fix.

**Independent Test**: quickstart V5, V6 and the `pkill` step of V12.

- [X] T023 [US3] In `modules/mango/quickshell/PassPopup.qml` replace T018's
  single line with the full table of `contracts/shell.md` "Status lines":
  `signed_out`, `locked`, `cli_missing`, `error` (text from
  `session_detail`), backend not running (`!Pass.alive`: "Backend stopped;
  restarting"), and `Pass.snapshot.v !== 1` ("Backend and shell disagree;
  rebuild", hiding everything else); and show `stale` and `cli_warning`
  under the list as `Detail` lines whenever set, rows or not
- [X] T024 [US3] In `modules/mango/quickshell/PassPopup.qml` add the sign-in:
  when `Pass.snapshot.can_login`, show a "Sign in" `Pill` button, and both
  it and `Enter` send `{t:"login"}`; while `session` is `logging_in`, list
  `Pass.snapshot.login.lines`. In `modules/mango/quickshell/Pass.qml`, when
  `snapshot.login.url` is set and differs from `openedUrl`, call
  `Qt.openUrlExternally` on it and store it; reset `openedUrl` to `""` when
  `snapshot.login` becomes `null` (data-model.md). A sign-in that fails or
  times out returns the backend to `error` or `signed_out` with `can_login`;
  confirm the failure text shows through T023's lines and the button is
  offered again (FR-020)
- [X] T025 [US3] Build gate as T015, `just qs-check`, deploy, then run
  quickstart V5, V6 and V12; screenshot the signed-out state with the
  `verify-quickshell` skill

---

## Phase 6: User Story 4 - Look at a secret without copying it (P3)

**Goal**: `Ctrl+R` shows a masked field in place.

**Independent Test**: quickstart V4.

- [X] T026 [US4] In `modules/mango/quickshell/PassPopup.qml`, in the field
  list: `Ctrl+R` sends `{t:"reveal"}`; a row whose `value` is not `null`
  shows it instead of dots; a row with `revealing` true shows a waiting
  mark; a row with `totp` shows `totp.code` and `totp.remaining` seconds.
  Bind straight to `Pass.snapshot`; copy the value into no other property
  (FR-017, data-model.md). Pointer: each secret row gets an eye `IconButton`
  that sends `{t:"select", index}` then `reveal`; first confirm in
  `~/projects/cosmic-pass/src/core/state.rs` that `Msg::Select` moves the
  selection in the field list, and if it does not, add a `reveal` index to
  the intent in T004 instead
- [X] T027 [US4] Build gate as T015, `just qs-check`, deploy, then run
  quickstart V4

---

## Phase 7: Polish & cross-cutting

- [X] T028 [P] In `modules/cosmic-de/default.nix` add
  `systemd.user.services.cosmic-pass.unitConfig.ConditionEnvironment = "!XDG_CURRENT_DESKTOP=mango";`
  with a one-line comment (research R6: the Mango session runs its own
  backend), then run quickstart V9 in both sessions; if the condition does
  not take effect in Mango, record that in `research.md` R6 and leave the
  line
- [X] T029 [P] Record the exception where the rule is: add to FR-009 in
  `specs/010-mango-wm-session/spec.md` "Exception: the Proton Pass quick
  access backend comes from the `cosmic-pass` flake input
  (specs/016-proton-pass-quick-access FR-025)", and to R5 in
  `specs/010-mango-wm-session/research.md` that the gap is closed by 016
- [X] T030 [P] (do right after T009) Replace the body of `contracts/serve-protocol.md` in this
  directory with a link to the authoritative copy in `cosmic-pass` (T002)
  and the list of snapshot fields the shell reads
- [X] T031 [P] If T016 to T026 added a reusable component or token, list it
  in `modules/mango/quickshell/README.md`; otherwise no change
- [X] T032 Final gate: `nix fmt`, `nix flake check`, the toplevel build of
  T015 for every machine in `machines/machines.nix`, `just qs-check`, then
  quickstart V7, V8, V10, V11 and V13

---

## Dependencies

```text
T001
T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T030
T009 → T010, T011, T014 (parallel) → T012 → T013 → T015
T015 → US1 (T016 → T017 → T018 → T019)
US1 → US2 (T020 → T021 → T022)
US1 → US3 (T023 → T024 → T025)
US2 → US4 (T026 → T027)
all stories → T028, T029, T031 (parallel) → T032
```

- US2 and US3 are independent of each other; both edit `PassPopup.qml`, so
  do them one after the other.
- US4 needs the field list of US2.
- T016 to T018 can be written against a hand-fed snapshot before T008 is
  pushed, but nothing here builds before T009.

## Parallel examples

- Foundational, after T009: T010 (`default.nix`), T011 (`Config.qml`,
  `quickshell.nix`) and T014 (`compositor.nix`) touch different files.
- Polish: T028 (`modules/cosmic-de`), T029 (`specs/010-…`), T031
  (`README.md`).
- Within a story there is nothing to run in parallel: each story is one
  file.

## Implementation strategy

1. **MVP**: Phases 1 to 3. After T019 the popup copies passwords, which is
   most of its use; stop and use it for a day.
2. Phase 4 (other fields), then Phase 5 (status and sign-in). Until Phase 5
   a signed-out popup shows only "Loading items…", so do not leave a long
   gap.
3. Phase 6 (reveal), then Phase 7.

Each phase ends with a build gate and its quickstart steps, so each can be
committed on its own.
