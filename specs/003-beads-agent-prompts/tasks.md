---

description: "Task list for Prompt the Coding Agent from a Beads Issue"
---

# Tasks: Prompt the Coding Agent from a Beads Issue

**Input**: Design documents from `specs/003-beads-agent-prompts/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. Plan and research R8 make them required: ERT is the only
cheap verifier for Emacs Lisp behaviour here (constitution Principle I's spirit),
and the suite already runs as `packages.test-beads` (Principle III). Tests for
each story are written before its implementation and must fail first.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths in every description

## Path Conventions

Emacs Lisp package inside a Nix configuration repository:

- `workstation/emacs/packages/beads.el` — the package
- `workstation/emacs/packages/beads-test.el` — ERT suite, fake `bd` on `PATH`
- `workstation/emacs/config.org` — claude-code-ide adapters, `use-package beads`, prose
- `CONTEXT.md` — domain vocabulary

`beads.el` tasks are sequential with each other; so are `beads-test.el` tasks and
`config.org` tasks. `[P]` marks only tasks in a different file from every
concurrently open task.

---

## Phase 1: Setup

**Purpose**: track the work in `bd` and confirm the gate is green before anything
is added.

**Beads issues for this feature** (created by T001):

| Issue | Covers |
|-------|--------|
| `dot-emacs-3q7` | the feature (epic) |
| `dot-emacs-3q7.1` | Phase 2, the agent seam and shared paste helper |
| `dot-emacs-3q7.2` | Phase 3, US1 quick prompt |
| `dot-emacs-3q7.3` | Phase 4, US2 explore |
| `dot-emacs-3q7.4` | Phase 5, US3 transient |
| `dot-emacs-3q7.5` | Phase 6, polish |

- [X] T001 Create the beads issues for this feature with `bd create`: one epic ("Prompt the coding agent from a beads issue", type feature) and children via `--parent` for Phase 2, US1, US2, US3 and Polish; record their ids in a table at the top of `specs/003-beads-agent-prompts/tasks.md` exactly as `specs/002-beads-issue-relations/tasks.md` does — work is tracked in `bd`, never in a markdown list
- [X] T002 Run `nix build .#test-beads -L` and confirm the existing suite passes unchanged, so every later failure belongs to this feature

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: the agent seam (research R1, contracts/commands.md → "The agent
seam") and the recorder the tests drive it with.

- [X] T003 In `workstation/emacs/packages/beads.el`, add a new top-level section `;;; Prompting the agent` between `;;; Acting on issues` and `;;; The transient`, containing: `(defcustom beads-agent-available-function nil …)` and `(defcustom beads-agent-send-function nil …)`, both `:type '(choice (const nil) function)` `:group 'beads`, docstrings stating the contract verbatim from contracts/commands.md — available: "() -> non-nil iff a session exists for default-directory's project. Must be cheap and must not prompt"; send: "(TEXT SUBMIT) -> BUFFER … Deliver TEXT … as one paste; press return iff SUBMIT. May prompt to choose a session. Signal user-error when no session can be chosen"
- [X] T004 In the same section of `workstation/emacs/packages/beads.el`, add `beads--agent-available-p` (nil when either option is nil, else `(funcall beads-agent-available-function)` with `default-directory` bound to `(beads-toplevel)`) and `beads--agent-send (text submit)` which first signals `(user-error "No agent session for this repository")` unless `beads--agent-available-p`, then calls the send function with `default-directory` bound to `(beads-toplevel)` and returns its buffer. Every refusal must happen before the send function is called (FR-013)
- [X] T005 [P] In `workstation/emacs/packages/beads-test.el`, add a macro `beads-test--with-agent` that let-binds `beads-agent-available-function` to a lambda returning a let-bound flag (default t) and `beads-agent-send-function` to a recorder that pushes `(TEXT . SUBMIT)` onto a list, creates/returns a buffer named `*fake-agent*`, and kills that buffer on exit; expose the recorded calls (in call order) to BODY
- [X] T006 [P] In `workstation/emacs/config.org`, section `** Claude Code`: add a new `#+begin_src elisp` block before the `use-package claude-code-ide` block defining, at top level (not inside `:config`, so they exist before `claude-code-ide` loads), `my/claude-code-ide-paste (text submit)` — the body of `my/magit-review--paste` moved verbatim (it `require`s `claude-code-ide`, resolves with `(claude-code-ide--resolve-session 'auto "Send to Claude instance: ")`, pastes per `claude-code-ide-terminal-backend`, `sit-for 0.1` then `claude-code-ide--terminal-send-return` when SUBMIT, returns the buffer) — and `my/claude-code-ide-session-p ()` = `(and (featurep 'claude-code-ide) (claude-code-ide-mcp--sessions-for-project (claude-code-ide--get-working-directory)) t)`. Precede the block with a sentence of prose naming both callers (Magit review, beads)
- [X] T007 In `workstation/emacs/config.org`, Magit review block (around line 1099): delete `my/magit-review--paste` and make `my/magit-review-send` call `my/claude-code-ide-paste` instead; then extend the comment ending "re-check them when bumping the flake input." (around line 4451) or the new block's prose to list `claude-code-ide--resolve-session`, `claude-code-ide-mcp--sessions-for-project`, `claude-code-ide--terminal-send-return` as internals the shared helpers rely on (depends on T006)
- [X] T008 In `workstation/emacs/config.org`, `use-package beads` block (around line 1440): add `:custom (beads-agent-available-function #'my/claude-code-ide-session-p) (beads-agent-send-function #'my/claude-code-ide-paste)` (depends on T006)

**Checkpoint**: seam exists, tests can record sends, config wired. No command yet.

---

## Phase 3: User Story 1 — Quick prompt (Priority: P1) 🎯 MVP

**Goal**: from an issue, the agent's input holds `Beads issue <id>: `, unsent, and the agent is focused.

**Independent Test**: with `beads-test--with-agent`, invoke `beads-agent-prompt` on an issue and assert exactly one recorded call `("Beads issue <id>: " . nil)` and that `*fake-agent*` is the selected window's buffer.

### Tests for User Story 1

- [X] T009 [US1] In `workstation/emacs/packages/beads-test.el`, add ERT tests (fail before T010): `beads-test-agent-prompt-names-the-issue` — in `beads-test--with-status`, `beads-test--goto` an issue, call `beads-agent-prompt`, expect calls `(("Beads issue <id>: " . nil))` and `(window-buffer (selected-window))` is `*fake-agent*`; `beads-test-agent-prompt-takes-the-region` — region over two issues, expect one call with both ids joined by `", "` in listing order; `beads-test-agent-prompt-from-a-show-buffer` — in a `beads-show-mode` buffer (as `beads-test-goto-opens-an-unlisted-issue` builds one via `beads-test--set-show` + `beads-show`), expect the shown id; `beads-test-agent-prompt-refuses-without-issue` — point on a non-issue section, expect `user-error` and zero calls; `beads-test-agent-prompt-refuses-without-agent` — flag nil, expect `user-error "No agent session for this repository"` and zero calls; `beads-test-agent-quick-prompt-default-is-plain-text` — `(string-match-p "\\`[/!#]" (default-value 'beads-agent-quick-prompt-format))` is nil

### Implementation for User Story 1

- [X] T010 [US1] In `workstation/emacs/packages/beads.el`, `;;; Prompting the agent`: add `(defcustom beads-agent-quick-prompt-format "Beads issue %s: " … :type 'string)` and `;;;###autoload (defun beads-agent-prompt () (interactive) …)`: ids from `beads--issues-at-point`; nil ⇒ `(user-error "No beads issue at point")` (no fallback to `beads--read-issue`, research R6); `buffer` = `(beads--agent-send (format beads-agent-quick-prompt-format (string-join ids ", ")) nil)`; then `(if-let* ((window (get-buffer-window buffer t))) (select-window window) (pop-to-buffer buffer))`. Docstring notes the paste lands at the terminal cursor (contracts/commands.md limitation)
- [X] T011 [US1] Run `nix build .#test-beads -L` (after `git add` of changed files); all US1 tests pass

**Checkpoint**: `M-x beads-agent-prompt` works from section, region and show buffer.

---

## Phase 4: User Story 2 — Explore (Priority: P1)

**Goal**: one command submits the prepared explore instruction for one issue and leaves windows alone.

**Independent Test**: with `beads-test--with-agent`, invoke `beads-agent-explore` on an issue; assert one call `(TEXT . t)` where TEXT is the default prompt with `%i` expanded, that `(current-window-configuration)` compared with `compare-window-configurations` is unchanged, and the echo message names `*fake-agent*`.

### Tests for User Story 2

- [X] T012 [US2] In `workstation/emacs/packages/beads-test.el`, add ERT tests (fail before T013–T015): `beads-test-agent-explore-submits-the-prompt` — expect one call with SUBMIT `t`, TEXT containing the id twice (`Explore beads issue <id>` and `bd show <id>`) and no literal `%i`; `beads-test-agent-explore-leaves-windows-alone` — `compare-window-configurations` before/after is non-nil and `current-message` (bind `inhibit-message` nil, or capture via `set-message-function`) matches `"Sent explore prompt for <id> to \\*fake-agent\\*"`; `beads-test-agent-explore-from-a-show-buffer`; `beads-test-agent-explore-refuses-a-region` — region over two issues ⇒ `user-error` matching `"Explore works on one issue; the region covers 2"`, zero calls; `beads-test-agent-explore-refuses-without-issue` and `…-without-agent` — zero calls; `beads-test-agent-explore-adds-a-missing-id` — let-bind `beads-agent-explore-prompt` to `"Look at this 100% carefully"`, expect TEXT = `"Beads issue <id>:\n\nLook at this 100% carefully"` (also proves a stray `%` does not signal); `beads-test-agent-explore-default-keeps-its-clauses` — the default value contains each asserted phrase from contracts/explore-prompt.md's table: `"bd show %i"`, `"comments"`, `"parts of this repository"`, `"each as a"`, `"question"`, `"say so plainly"`, `"Do not implement anything"`, `"Do not commit"`, `"stop and wait"`, and does not start with `/`, `!` or `#`

### Implementation for User Story 2

- [X] T013 [US2] In `workstation/emacs/packages/beads.el`, `;;; Prompting the agent`: add `(defcustom beads-agent-explore-prompt "…" :type 'string)` whose default is the text block of `specs/003-beads-agent-prompts/contracts/explore-prompt.md` copied verbatim (keep its line breaks); docstring says `%i` is the issue id and that the id is prepended when absent
- [X] T014 [US2] In `workstation/emacs/packages/beads.el`, add `beads--agent-explore-text (id)`: `(require 'format-spec)`, `(format-spec beads-agent-explore-prompt `((?i . ,id)) 'ignore)`; when the result does not contain ID (`string-search`), return `(concat "Beads issue " id ":\n\n" result)` (FR-010)
- [X] T015 [US2] In `workstation/emacs/packages/beads.el`, add `;;;###autoload (defun beads-agent-explore () (interactive) …)`: ids from `beads--issues-at-point`; nil ⇒ `(user-error "No beads issue at point")`; more than one ⇒ `(user-error "Explore works on one issue; the region covers %d" (length ids))`; else `buffer` = `(beads--agent-send (beads--agent-explore-text id) t)`, no window change, then `(message "Sent explore prompt for %s to %s" id (buffer-name buffer))`
- [X] T016 [US2] Run `nix build .#test-beads -L`; all US1 and US2 tests pass

**Checkpoint**: both commands work via `M-x`; US1 unaffected.

---

## Phase 5: User Story 3 — Menu entries (Priority: P2)

**Goal**: `#` shows an `Agent` column with `i` Prompt and `e` Explore, greyed out without a session.

**Independent Test**: `transient-get-suffix 'beads-dispatch "i"` / `"e"` name the two commands, and `beads--agent-available-p` is nil with the flag off or either option nil, t with the flag on.

- [X] T017 [US3] In `workstation/emacs/packages/beads-test.el`, add `beads-test-transient-offers-the-agent` modelled on `beads-test-transient-greys-out-what-does-not-apply`: assert `beads-agent-prompt` ∈ `(flatten-tree (transient-get-suffix 'beads-dispatch "i"))` and `beads-agent-explore` for `"e"`; inside `beads-test--with-agent` assert `beads--agent-available-p` is t with the flag on and nil with it off; outside the macro (both options nil) assert it is nil and that the available function is never called (fails before T018)
- [X] T018 [US3] In `workstation/emacs/packages/beads.el`, `beads-dispatch`: add after the `"Relations"` column `["Agent" ("i" "Prompt" beads-agent-prompt :inapt-if-not beads--agent-available-p) ("e" "Explore" beads-agent-explore :inapt-if-not beads--agent-available-p)]`, with a one-line comment that `:inapt-if-not` keeps the menu's shape, as the Relations column already explains
- [X] T019 [US3] Run `nix build .#test-beads -L`; whole suite passes

**Checkpoint**: all three stories done and tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 [P] Update the `;;; Commentary:` of `workstation/emacs/packages/beads.el` with two sentences: the transient can hand the issue at point to a coding agent (`i` quick prompt, `e` explore), and the agent itself is plugged in through `beads-agent-available-function` / `beads-agent-send-function`, so this file names no agent package
- [X] T021 [P] In `CONTEXT.md` under `### Emacs / beads`, add entries in the existing format (bold term, definition, `_Avoid_` where useful): **Agent session** (the Claude Code instance of this repository that prompts go to; 0, 1 or many), **Quick prompt** (an unsent reference to one or more beads in the agent's input, finished by the developer), **Explore prompt** (the configurable instruction asking the agent to study one bead and return decision questions without implementing; _Avoid_: plan, which suggests an implementation plan)
- [X] T022 In `workstation/emacs/config.org`, `** Beads` prose paragraph before the `use-package beads` block: add a paragraph describing `i` (paste `Beads issue <id>: ` into the project's Claude Code session and focus it) and `e` (submit `beads-agent-explore-prompt`: explore, ask, don't implement — the choice of skill stays yours), that both are grey without a session, and that `C-u` asks which session
- [X] T023 `git add` all changed files; run `nix fmt` and revert unrelated churn; `nix flake check`; `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`; `nix build .#test-beads -L` — all must pass (constitution Development Workflow steps 1–4)
- [x] T024 Walk `specs/003-beads-agent-prompts/quickstart.md` §3 by hand against a live Claude Code session in this repository; fix and add a regression test to `workstation/emacs/packages/beads-test.el` for anything that fails on the beads side (constitution Principle III)
- [x] T025 Run the SC-003 measurement in `specs/003-beads-agent-prompts/quickstart.md` §4 on 10 open issues; record the result (runs ending with questions / runs that changed anything) as a `bd comment` on the epic; if any run changed something, reword `beads-agent-explore-prompt` in `workstation/emacs/packages/beads.el` and `contracts/explore-prompt.md` together and re-run
- [x] T026 Close the feature's beads issues with `bd close` (reasons naming what was delivered)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T002)**: none.
- **Foundational (T003–T008)**: after Setup. Blocks every story.
- **US1 (T009–T011)**, **US2 (T012–T016)**: after Foundational; independent of each other in behaviour, but both edit `beads.el` and `beads-test.el`, so run one after the other (US1 first, as MVP).
- **US3 (T017–T019)**: after Foundational; the transient entries reference both commands, so do it after US1 and US2.
- **Polish (T020–T026)**: after the stories it documents.

### Within phases

- T003 → T004 (same file). T005 ∥ T003/T004 (different file). T006 ∥ T003–T005; T007, T008 after T006 (same file).
- Each story: test task first (must fail), then implementation, then the build.
- T020 ∥ T021 (different files); T022 after T007/T008 (same file).

## Parallel Example

```text
# Foundational, three files at once:
T003–T004  workstation/emacs/packages/beads.el      (seam + beads--agent-send)
T005       workstation/emacs/packages/beads-test.el (beads-test--with-agent)
T006–T008  workstation/emacs/config.org             (shared helper, callers, :custom)

# Polish:
T020  workstation/emacs/packages/beads.el  (Commentary)
T021  CONTEXT.md                           (terms)
```

Within US1/US2/US3, no `[P]`: each story touches the same two files.

## Implementation Strategy

### MVP (User Story 1 only)

1. Phase 1 → Phase 2 → Phase 3.
2. Stop and validate: `nix build .#test-beads -L`, then quickstart §3 steps 2–4 with `M-x beads-agent-prompt`.
3. Usable immediately: no menu entry yet, but the command works.

### Incremental delivery

1. + US2 → explore via `M-x beads-agent-explore`; validate quickstart §3 step 5.
2. + US3 → both on `#`; validate quickstart §3 step 1.
3. Polish → docs, full gate, SC-003 measurement.
