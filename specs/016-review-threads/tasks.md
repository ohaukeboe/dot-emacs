# Tasks: Review Threads

**Input**: Design documents from `/specs/016-review-threads/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/send-function.md, contracts/menu.md, quickstart.md

**Tests**: ERT tests are included and written first. This follows the repo's
practice for `workstation/emacs/packages/*.el` (see
`specs/006-review-walkthrough/tasks.md`). The glue in `config.org` has no ERT
suite and is verified with `quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 = hand off into a thread, US2 = toggle in `@`, US3 = grouping

## Path Conventions

- Review package: `workstation/emacs/packages/magit-review.el`
- Its ERT suite: `workstation/emacs/packages/magit-review-test.el`, run with
  `nix build .#test-magit-review -L`
- Claude glue and prose: `workstation/emacs/config.org`. Edit the `.org`, never
  generated `.el`.
- The flake sees only git-tracked files: `git add` before `nix build`.

---

## Phase 1: Setup

- [X] T001 Confirm that the Claude Code CLI supports what research R1/R3 rely on. `claude --help` must list `--fork-session` and `--resume`, and `claude --resume <id> --fork-session "prompt"` must start interactively with "prompt" submitted. Also confirm that `~/.claude/sessions/<pid>.json` of a running CLI has a `sessionId` key; read only `*.json`, never the `*.key` files beside them. If any check fails, stop and revisit `specs/016-review-threads/research.md` (R1–R3) before going on. No file change.

---

## Phase 2: Foundational (blocks all user stories)

The options and their reader, which every hand-off consults.

### Tests (write first, must fail)

- [X] T002 Add ERT tests in `workstation/emacs/packages/magit-review-test.el` for a new `magit-review--thread-mode`. With `transient-args` for `magit-review` stubbed to return `()`, `("--thread")` and `("--thread" "--new-thread")`, it returns `nil`, `item` and `hand-off`. `("--new-thread")` alone returns `nil`, because the option "only matters with --thread" (contracts/menu.md).

### Implementation

- [X] T003 In `workstation/emacs/packages/magit-review.el`, add an "Options" group to the `magit-review` transient (contracts/menu.md) with `("-t" "Separate thread" "--thread")` and `("-n" "New thread each time" "--new-thread")`. Give the prefix `:remember-value '(exit quit)`. Add `magit-review--thread-mode`, which reads `(transient-args 'magit-review)` and returns `nil`, `item` or `hand-off`. Update the `magit-review-send-function` docstring to the signature `(TEXT SUBMIT &optional THREAD)` ⇒ buffer, with THREAD `nil`, `new` or a buffer (contracts/send-function.md).
- [X] T004 Check that every existing test in `workstation/emacs/packages/magit-review-test.el` still uses a two-argument stub send function. Keep them that way: with `--thread` off, magit-review must call the send function with exactly two arguments (FR-012, SC-005), and a two-argument stub fails loudly if a third is passed. Run `nix build .#test-magit-review -L` and confirm that it passes.

**Checkpoint**: The menu shows `-t` and `-n`. Nothing behaves differently yet.

---

## Phase 3: User Story 1 — Hand a review off into a thread (P1) 🎯 MVP

**Goal**: With `-t` on, every hand-off goes to a new forked Claude instance,
and the main conversation gets nothing.

**Independent test**: Quickstart manual steps 1, 7, 8 and 9, plus the T005 ERT
tests.

### Tests (write first, must fail)

- [X] T005 [US1] Add ERT tests in `workstation/emacs/packages/magit-review-test.el` with a three-argument stub send function that records `(TEXT SUBMIT THREAD)` and returns a fresh buffer, and with `magit-review--thread-mode` stubbed to `hand-off`:
  - `magit-review-send` calls the stub once with THREAD `new` and SUBMIT `t`, and the TEXT equals what the same items produce with threads off (FR-007).
  - `magit-review-paste` and `magit-review-comment-send` with a prefix argument pass SUBMIT `nil`.
  - `magit-review-comment-send` on a hunk and on a walkthrough finding (the `@ d` reply path) passes THREAD `new`.
  - The items are marked sent after the call.
  - When the stub signals an error, nothing is marked sent and the comments stay pending (FR-011).

### Implementation

- [X] T006 [US1] In `workstation/emacs/packages/magit-review.el`, make `magit-review--hand-off` consult `magit-review--thread-mode`. When it is `nil`, call `magit-review-send-function` with two arguments, exactly as today. Otherwise call it with THREAD `new` for the whole hand-off. Mark the comments and findings sent only after the call returns. Keep the no-submit window selection on the returned buffer. Run `nix build .#test-magit-review -L`.
- [X] T007 [US1] In the "Claude Code" section of `workstation/emacs/config.org`, extend `my/claude-code-ide-paste` to `(text submit &optional thread)` per contracts/send-function.md, and add the glue it needs.
  - `my/claude-review-threads`: the list of claude-code-ide sessions it started as threads.
  - `my/claude-review--main-session`: resolves the project's main instance. Drop the live sessions in `my/claude-review-threads` from `claude-code-ide-mcp--sessions-for-project`, then take the only one, the only visible one, or the most recently used, and ask when there is a prefix argument (research R7). Use it for THREAD `nil` too.
  - `my/claude-review--conversation-id`: reads `sessionId` from `~/.claude/sessions/<claude-code-ide-mcp-session-cli-pid>.json` at call time. Signal `user-error` naming the instance when the file or the key is missing (research R2).
  - `my/claude-review--fork`: starts `claude-code-ide--start-session` with `claude-code-ide-cli-extra-flags` let-bound to the existing flags plus `--resume <id> --fork-session`. When SUBMIT is set, also pass the shell-quoted TEXT as the positional prompt (research R3). Override `claude-code-ide--read-instance-name` with `cl-letf` so it returns the first free `review-N`. Push the new session onto `my/claude-review-threads` and return its buffer.
  - When SUBMIT is nil, wait until the new session's MCP client is connected and the terminal has been quiet briefly, bounded by a new defcustom `my/claude-review-thread-timeout` (30 s), then paste without RET. On timeout, signal `user-error`.
  - THREAD as a buffer: paste into that buffer as today.
  - Add the new internals (`claude-code-ide--start-session`, `claude-code-ide--read-instance-name`, `claude-code-ide-mcp-session-cli-pid`, `~/.claude/sessions/*.json`) to the section's list of things to re-check when bumping the flake input.
  - Two-argument calls (beads) must behave exactly as before.
- [X] T008 [US1] In the magit-review prose of `workstation/emacs/config.org` (the paragraphs around the `use-package magit-review` block), document `-t`: hand-offs go to a forked `review-N` instance, the main conversation is untouched, and items are marked sent only once the prompt is delivered.

**Checkpoint**: The MVP. `@ -t` then `@ s` opens a forked thread. Every
hand-off opens a new one, even with `-n` off, until US3.

---

## Phase 4: User Story 2 — Toggle threads from the `@` menu (P1)

**Goal**: The toggle keeps its value for the Emacs session and can be saved.

**Independent test**: Quickstart manual step 2, plus the T009 ERT test.

### Tests (write first, must fail)

- [X] T009 [US2] Add an ERT test in `workstation/emacs/packages/magit-review-test.el` that asserts `(oref (get 'magit-review 'transient--prefix) remember-value)` equals `'(exit quit)`. Also assert that `magit-review-comment` (`@ c`) and `magit-review-list` never call `magit-review--thread-mode`, because the options do not apply to them (contracts/menu.md "Not read by").

### Implementation

- [X] T010 [US2] Make T009 pass in `workstation/emacs/packages/magit-review.el`; T003 should already cover most of it. Name the options and their persistence (`C-x C-s` to save) in the `magit-review` docstring and in the commentary at the top of the file.

**Checkpoint**: Reopening `@` shows `-t` still on.

---

## Phase 5: User Story 3 — Choose how hand-offs are grouped into threads (P2)

**Goal**: Per-item grouping, the default with `-t` on and `-n` off, sends
follow-ups back to their item's thread. `-n` always starts a new thread.

**Independent test**: Quickstart manual steps 3–6, plus the T011 ERT tests.

### Tests (write first, must fail)

- [X] T011 [US3] Add ERT tests in `workstation/emacs/packages/magit-review-test.el` with the three-argument stub (one fresh buffer per `new`) and `magit-review--thread-mode` stubbed to `item`, following data-model.md "Hand-off partition":
  - Two never-sent comments sent with `@ s` make one call with `new`, and both comments' `:thread` is set to the returned buffer.
  - A later `magit-review-comment-send` on the same target (equal plist minus `:text`, `:sent` and `:thread`) makes one call with that buffer, not `new`.
  - An accepted finding sent, then replied to (`walkthrough-reply`) and sent again, goes to the same buffer the second time. The link is keyed by `(walkthrough-file . finding-id)`.
  - A hand-off mixing items of two live threads and one unlinked item makes three calls in first-seen order: each thread's buffer with its own items, then `new` with the unlinked item. Each call's TEXT is `magit-review-format` of only its items, with the same intro.
  - After the thread's buffer is killed, the next hand-off of that item uses `new` and relinks it.
  - With mode `hand-off`, a linked item still gets `new`, and its link is updated to the new buffer.
  - When the second of two calls signals, the first group stays sent and the second stays pending.

### Implementation

- [X] T012 [US3] In `workstation/emacs/packages/magit-review.el`, implement the per-item partition and the links from data-model.md. Store a comment's link as `:thread` on its plist, and a finding's link in a new hash table `magit-review--finding-threads` keyed by `(walkthrough-file . finding-id)` (`:walkthrough` and `:id` of the hand-off item). A link to a dead buffer counts as none. `magit-review-comment-send` looks up the most recent comment with an equal target and a live link before handing off. `magit-review--hand-off` sends one call per group, then marks that group sent and sets its links. Run `nix build .#test-magit-review -L`.
- [X] T013 [US3] Extend the magit-review prose in `workstation/emacs/config.org` with `-n`. Without it, each comment or finding keeps its thread, and follow-ups and new direct comments on the same target go back there while it is open. With it, every hand-off forks a new thread.

**Checkpoint**: All stories are done. Run the whole quickstart.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T014 [P] Add a **Thread** entry to `GLOSSARY.md` under "Emacs / Claude Code": a Claude instance forked from the project's main conversation to receive review hand-offs, named `review-N`, never itself a fork source. _Avoid_: branch (git), session. Add a line under **Review hand-off** saying it may go to a thread.
- [X] T015 Run `nix fmt`, revert unrelated churn, then run `nix flake check`, `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'` and `nix build .#test-magit-review -L`.
- [X] T016 Hand over to the user for `sudo nixos-rebuild switch --flake .#<hostname>` and the manual steps 1–10 in `specs/016-review-threads/quickstart.md`. Record any failure as a new task in this file.
- [X] T017 Tick each finished task `[X]` in `specs/016-review-threads/tasks.md`, in the same change that closes its tracker ticket.

---

## Dependencies & Execution Order

```text
T001 ─► T002 ─► T003 ─► T004 ─┬─► US1: T005 ─► T006 ─► T007 ─► T008
                              ├─► US2: T009 ─► T010            (independent of US1)
                              └─► US3: T011 ─► T012 ─► T013    (needs T006)
T014 any time · T015 after T008, T010 and T013 · T016 after T015 · T017 last
```

- US1 and US2 both depend only on Phase 2.
- US3 builds on US1's `magit-review--hand-off` change (T006), and only on the
  magit-review side. The glue from T007 is not needed for its ERT tests.
- T007 and T008 (`config.org`) do not touch `magit-review.el`, so they can run
  alongside US2 and US3 once T006 has fixed the contract.

## Parallel Opportunities

- After T006: T007 (`config.org`) ∥ T009–T010 (`magit-review.el`, US2) ∥ T014
  (`GLOSSARY.md`).
- T011 and T009 both edit `magit-review-test.el`, so run them one after the
  other, not in parallel.

## Implementation Strategy

1. **MVP**: Phases 1–3 (T001–T008). `-t` sends every hand-off to a new forked
   thread. That is already useful, and the per-hand-off behaviour is what `-n`
   later makes explicit.
2. **+US2** (T009–T010): the toggle is remembered.
3. **+US3** (T011–T013): per-item threads become the default with `-t` on.
4. **Polish** (T014–T017), then the manual quickstart after switch.
