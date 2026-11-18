# Implementation Plan: Proton Pass Quick Access

**Branch**: `016-proton-pass-quick-access` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/016-proton-pass-quick-access/spec.md`

## Summary

`Super+Space` in the Mango session opens a Rail popup that finds a Proton
Pass item and copies its password, another field or a one-time code.

`cosmic-pass` already holds everything but the drawing, as a reducer with an
effect runner. It gains a windowless subcommand, `cosmic-pass serve`, that
speaks JSON lines on stdin and stdout
([contracts/serve-protocol.md](contracts/serve-protocol.md)). The Quickshell
config runs it as a child process and draws its snapshots in a new Rail
popup ([contracts/shell.md](contracts/shell.md)). This repository adds two
QML files, wiring, one option and one key binding; no logic.

## Technical Context

**Language/Version**: QML (Quickshell, Qt 6) and Nix here; Rust 1.93,
edition 2024, in `cosmic-pass`

**Primary Dependencies**: Quickshell (`Quickshell.Io` `Process`), the
`cosmic-pass` flake input, `pass-cli` 2.3 or newer (bundled by that package),
a Secret Service keyring

**Storage**: none here. The backend keeps its encrypted cache file and its
key in the keyring, as today

**Testing**: here, evaluation-time only: `nix flake check`, `qmlCheck`
(qmllint, fails the build), `just qs-check`, then
[quickstart.md](quickstart.md) by hand. In `cosmic-pass`: `just check`, with
new tests that drive `serve` against the fake backend

**Target Platform**: NixOS, Mango session (Wayland, wlroots)

**Project Type**: desktop shell configuration plus a change to a companion
application in another repository

**Performance Goals**: popup accepts typing within 0.5 s of the key
(SC-002); rows update within 0.1 s of a keystroke at 2,000 items (SC-003)

**Constraints**: no secret on disk, in logs or kept by the shell (FR-017);
the Mango module contributes nothing when off (FR-021); works with COSMIC
off and does not change COSMIC's popup (FR-022)

**Scale/Scope**: one user, up to a few thousand items; about 300 lines of
QML and 30 of Nix here; one subcommand of about 300 lines plus tests in
`cosmic-pass`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                        | Status | How                                          |
|----------------------------------|--------|----------------------------------------------|
| I. Evaluation-time verification  | Pass   | See below                                    |
| II. Determinism                  | Pass   | Backend pinned by `flake.lock`; no new input |
| III. Fast default gate           | Pass   | No new check; qmllint is already in the build|
| IV. Single source of truth       | Pass   | See below                                    |
| V. Toggleable modules            | Pass   | See below                                    |

- **I**: the clearing time is `types.ints.between 10 600`, the backend's own
  range. The backend is referenced by store path through a `Config.qml`
  placeholder (`replaceVars` fails the build on a missing one). qmllint fails the build on any warning in the new files.
- **IV**: search, ranking, parsing and state live only in `cosmic-pass`. The
  protocol is written once ([contracts/serve-protocol.md](contracts/serve-protocol.md))
  and moves to `cosmic-pass` when it ships. The 010 FR-009 exception is
  recorded at FR-009 itself.
- **V**: everything is inside `mkIf cfg.enable` of the Mango module. The
  Mango module reads no COSMIC option. The one line in `modules/cosmic-de`
  (research R6) is that module changing its own unit.

No violations. Re-checked after Phase 1: unchanged.

**Other governance**: `specs/010-mango-wm-session` FR-009 (nixpkgs-only
packages) is contradicted on purpose, as one exception confirmed in the
spec's Clarifications (FR-025). No ADR: the choice is cheap to reverse and
recorded where the rule is stated.

## Project Structure

### Documentation (this feature)

```text
specs/016-proton-pass-quick-access/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── serve-protocol.md    # backend <-> shell
│   └── shell.md             # option, IPC, keys, status lines
└── tasks.md                 # /speckit-tasks
```

### Source Code

This repository:

```text
modules/mango/
├── default.nix              # + options.modules.mango.pass.clipboardClearSeconds
├── quickshell.nix           # + passBackend, passClearSecs for Config.qml
├── compositor.nix           # Super+Space -> ipc call pass toggle; protonPass removed
└── quickshell/
    ├── Config.qml           # + the two placeholders
    ├── Pass.qml             # new: singleton; Process, last snapshot, send()
    ├── PassPopup.qml        # new: the view (item list, field list, status)
    ├── Rail.qml             # "pass" added to the openTarget comment
    ├── shell.qml            # + IpcHandler "pass", + RailPopup target "pass"
    └── README.md            # + the popup under the component list, if it adds a component
modules/cosmic-de/default.nix  # + ConditionEnvironment on its cosmic-pass unit
specs/010-mango-wm-session/
├── spec.md                  # FR-009: note the FR-025 exception
└── research.md              # R5: gap closed by 016
flake.lock                   # cosmic-pass bumped to the commit with `serve`
```

`cosmic-pass` (separate repository, its own spec `004`):

```text
src/cli.rs                   # + Command::Serve { clipboard_clear_secs }
src/main.rs                  # dispatch to serve before app::run
src/serve.rs                 # new: the loop, intent and snapshot types
tests/serve_protocol.rs      # new: the tests listed in the contract
README.md                    # + the subcommand
```

**Structure Decision**: Two new QML files beside the picker's, following its
split of a state singleton and a view. No new Nix file: three lines each in
existing ones. The backend change is a new module next to `runtime.rs`,
which it drives.

## Order of work

1. `cosmic-pass`: `serve` and its tests, merged and pushed.
2. Here: `nix flake update cosmic-pass`.
3. Here: option, `Config.qml` placeholders, `Pass.qml`, `PassPopup.qml`,
   IPC target and popup, key binding. Story 1 first (list, copy), then the
   field list (story 2), status lines (story 3), reveal (story 4).
4. Here: the `modules/cosmic-de` condition, the notes in spec 010.
5. Build gates, `just qs-check`, deploy, quickstart V1 to V13.

Step 3 can start against a hand-fed snapshot before step 1 is merged, but
nothing here builds until step 2.

## Follow-up (not part of this feature)

- Build `cosmic-pass serve` without libcosmic (research R5). Ticket
  `dot-emacs-90n`.
- A key that opens the selected item in the application, if Proton
  documents a deep link (research R7).

## Complexity Tracking

No constitution violations to justify.
