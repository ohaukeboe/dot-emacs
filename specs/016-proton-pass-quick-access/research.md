# Research: Proton Pass Quick Access

Sources read: `~/projects/cosmic-pass` at `7d1d411` (`src/core/state.rs`,
`src/runtime.rs`, `src/config.rs`, `src/cli.rs`, `src/main.rs`, `Cargo.toml`,
`README.md`), this repository's `modules/mango/` and `modules/cosmic-de/`, and
the nixpkgs `proton-pass` 1.42.0 package.

## R1. How the Rail popup and the backend talk

- **Decision**: `cosmic-pass` gains a subcommand, `cosmic-pass serve`, that
  opens no window. It reads one JSON intent per line on stdin and writes one
  JSON view snapshot per line on stdout. Quickshell runs it as a child
  `Process` of the shell for the whole session. Contract:
  [contracts/serve-protocol.md](contracts/serve-protocol.md).
- **Rationale**: `cosmic-pass` is already a reducer: `Model::update(Msg, now)`
  returns `Effect`s and `runtime::execute` turns each into a future, a stream
  or show/hide. Neither needs the COSMIC window; the test harness
  (`src/testing.rs`) drives them without one. `serve` is a third driver of the
  same loop, so search, ranking, the cache, copy, reveal, one-time codes and
  every status state come along unchanged and stay under the existing tests.
  The intents map one to one onto existing `Msg` variants. A child process
  needs no socket path, no service unit and no second lifecycle: it lives and
  dies with the shell.
- **Alternatives considered**:
  - A unix socket or D-Bus service: a path or name to agree on, a unit to
    order after the keyring, reconnect logic. Nothing here needs two clients.
  - A request/response command per action (`cosmic-pass query foo`): pays the
    cache decryption and process start on every keystroke, and has nowhere to
    keep a revealed value, a running sign-in or the clipboard timer.
  - Search in QML over a list sent once: duplicates `core/search.rs` and the
    usage ranking, untested, and puts every item's metadata in the shell.

## R2. What crosses the pipe

- **Decision**: The backend sends a view, not its model: the visible rows
  (already capped by its `max_results`), the selection, the field list of the
  one open item, and status. A copied value never crosses; the backend hands
  it to its own clipboard helper. A revealed value crosses, because the shell
  has to draw it, and only while it is revealed.
- **Rationale**: FR-017. The shell holds a secret only in the property bound
  to the latest snapshot, and the next snapshot replaces it. Nothing is logged
  on either side: the backend logs to stderr and never logs values; the shell
  does not log snapshots.
- **Alternatives considered**: drawing the reveal in a window of the backend's
  own, so no secret reaches the shell. That is the COSMIC window this feature
  exists to replace.

## R3. The search field and the snapshot

- **Decision**: The text field in the shell owns the query. The shell sends
  each change; snapshots echo the query they were computed for, and the shell
  never writes the echo back into the field.
- **Rationale**: A snapshot for "ab" arriving after the user typed "abc" would
  otherwise eat a letter. Rows for a stale query are shown for one frame at
  most, then replaced.

## R4. Preferences and the clearing time

- **Decision**: `serve` does not read or write cosmic-config. It takes
  `--clipboard-clear-secs <10..600>` and uses built-in defaults for the rest.
  The Mango module declares
  `modules.mango.pass.clipboardClearSeconds = types.ints.between 10 600`,
  default 90, and passes it on the command line.
- **Rationale**: FR-023 and constitution I: the value is typed in Nix with
  the same range the backend enforces (`CLIPBOARD_CLEAR_RANGE`), so a bad
  value fails evaluation. Keeping `serve` off cosmic-config means the two
  sessions cannot change each other's settings (FR-022), and the preferences
  and key-rebinding screens are simply not reachable (out of scope).
- **Alternatives considered**: sharing the COSMIC preferences. Then a setting
  changed in COSMIC silently changes Mango, and Nix no longer owns the value.

## R5. The COSMIC libraries

- **Decision**: `serve` lives in the existing binary, which still links
  libcosmic. Accepted for the first version (Clarifications, question 2).
  Follow-up ticket: put the window behind a Cargo feature so a `serve`-only
  build has no libcosmic.
- **Rationale**: Only `src/app/`, `src/config.rs` (the cosmic-config derive)
  and one arm of `runtime::execute` (`SavePreferences`) use libcosmic today.
  The split is mechanical but touches the preference types; it does not
  change the protocol, so it can follow without a change here.

## R6. One backend per session

- **Decision**: In `modules/cosmic-de`, the `cosmic-pass` user service gets
  `ConditionEnvironment=!XDG_CURRENT_DESKTOP=mango`.
- **Rationale**: That unit is wanted by `graphical-session.target`, so with
  both modules on it also starts in the Mango session, where nothing can open
  its window. Two backends would then write the same encrypted cache file and
  the same usage records, last writer winning. The negated form fails safe:
  if the variable is missing the unit starts exactly as today, so the COSMIC
  session cannot be broken by this line (FR-022).
- **Unverified**: that the variable is in the systemd user manager's
  environment when the unit is evaluated. `specs/010-mango-wm-session`
  research R6 says mango imports it. Quickstart step V9 checks it on a real
  session. If it does not hold, the line has no effect and the duplicate
  backend remains; that is a degraded ranking, not a failure.
- **Alternatives considered**: setting the condition from the Mango module.
  Rejected: a module must not reach into another module's unit
  (constitution V).

## R7. Opening the full application

- **Decision**: The popup has no key for the full application. It is started
  from the launcher. FR-026 is withdrawn.
- **Rationale**: `proton-pass` 1.42.0 registers the `protonpass://` scheme,
  but its `app.asar` holds no item URL form (only the bare scheme and a test
  URL), and Proton documents none. A key that only starts the application
  does nothing the launcher does not, so the user dropped it.
- **Revisit when**: Proton documents an item deep link.

## R8. Sign-in from the popup (FR-020)

- **Decision**: The `login` intent maps to `Msg::StartLogin`. The backend
  already runs `pass-cli login`, forwards each output line, and keeps the URL
  it prints. The shell opens that URL once with `Qt.openUrlExternally` when it
  first appears in a snapshot, and lists the lines. The sign-in continues if
  the popup closes; the next snapshot after it finishes carries the items.
- **Rationale**: `pass-cli login` prints a URL and waits. Nothing in the
  backend opens a browser, and FR-020 requires it.

## R9. Where the popup is drawn

- **Decision**: A new Rail target `pass`, hosted like the picker: one
  `RailPopup` per screen with the clock island, opened through a new IPC
  target `pass`. State lives in a singleton `Pass.qml` (the process, the last
  snapshot, `send`); the view is `PassPopup.qml`. `Super+Space` runs
  `quickshell -c mango ipc call pass toggle`.
- **Rationale**: This is exactly how the launcher and the picker are wired
  (`shell.qml`, `Picker.qml`, `compositor.nix`), so opening on the focused
  monitor, replacing another open popup, Esc and click-outside all come from
  `Rail` unchanged. The view uses `QueryInput`, `ListRow`, `SectionLabel`,
  `Hint`, `Detail` and `RailText` from the design system.
- **Alternatives considered**: reusing the picker through `mango-pick`. Its
  contract is lines in, one choice out; it has no second screen, no reveal
  and no live status.

## R10. Clipboard and history

- **Decision**: No change. The backend's own helper serves the clipboard with
  the `x-kde-passwordManagerHint=secret` hint and clears it after the timeout
  if it is still the content.
- **Rationale**: `modules/mango/session.nix` already makes `cliphist` skip
  entries marked sensitive, and the helper uses the data-control protocol
  that `cliphist` and `wl-copy` already use under Mango.

## R11. Where the backend comes from (FR-025)

- **Decision**: `inputs.cosmic-pass.packages.<system>.default`, the input
  `flake.nix` already declares. The Mango module reads it as `modules/cosmic-de`
  does. `specs/010-mango-wm-session/spec.md` FR-009 and its research R5 get a
  note naming this exception.
- **Rationale**: Confirmed in Clarifications, question 1. Pinned by
  `flake.lock`, so constitution II holds. No COSMIC module option is read, so
  010 FR-014 holds.

## R12. How this is verified

- **Decision**: In `cosmic-pass`: tests that drive `serve` with the fake
  backend and compare snapshots (`insta`, already a dev dependency). Here:
  the existing `qmlCheck` (qmllint at build, fails on any warning),
  `just qs-check`, the `verify-quickshell` skill for the screens, and the
  manual steps in [quickstart.md](quickstart.md).
- **Rationale**: Constitution I and III: this repository has no runtime test
  suite; logic that needs one stays in the repository that has one.
