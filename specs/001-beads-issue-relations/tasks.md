---

description: "Task list for Beads Issue Relations in Magit"
---

# Tasks: Beads Issue Relations in Magit

**Input**: Design documents from `specs/001-beads-issue-relations/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. The plan makes them required, not optional: Constitution
Principle I's spirit (make the mistake fail where it is cheap) and Principle III
(heavy tests as `packages.*`) both apply, and `quickstart.md` §1 already lists
the ERT cases each requirement needs.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Exact file paths in every description

## Path Conventions

This is an Emacs Lisp package inside a Nix configuration repository, not a
`src/` + `tests/` project. Paths are as given in plan.md → Project Structure:

- `workstation/emacs/packages/beads.el` — the package; almost all behaviour
- `workstation/emacs/packages/beads-test.el` — the ERT suite and its fake `bd`
- `tests/beads.nix`, `flake.nix` — the build that runs the suite
- `workstation/emacs/config.org`, `CONTEXT.md` — prose and domain vocabulary

**Note on parallelism**: this feature is concentrated in two files, so `[P]`
appears rarely and honestly. Tasks touching `beads.el` are sequential with each
other by construction — marking them parallel would invite conflicts, not speed.

---

## Phase 1: Setup

**Purpose**: track the work where the repository requires, and build the gate
that will verify it, before any behaviour exists.

**Beads issues for this feature** (created by T001):

| Issue | Covers |
|-------|--------|
| `dot-emacs-9ym` | the feature (epic) |
| `dot-emacs-9ym.1` | T002–T004, the ERT suite as a Nix package |
| `dot-emacs-9ym.2` | Phase 2, the relation data layer |
| `dot-emacs-9ym.3` | Phase 3, US1 marks |
| `dot-emacs-9ym.4` | Phase 4, US2 navigation |
| `dot-emacs-9ym.5` | Phase 5, US3 go back |
| `dot-emacs-9ym.6` | Phase 6, US4 transient |
| `dot-emacs-9ym.7` | Phase 7, polish |

- [X] T001 Create the beads issues for this feature with `bd create`, one per user story phase plus one for the test harness, and record their ids at the top of `specs/001-beads-issue-relations/tasks.md` — the repository tracks work in `bd`, never in a markdown list (CLAUDE.md, constitution "Additional Constraints")
- [X] T002 [P] Create `tests/beads.nix` as a `runCommand` derivation that runs `emacs -batch -L . -l beads-test.el -f ert-run-tests-batch-and-exit` over `workstation/emacs/packages/`, modelled on `tests/emacs-sops-save.nix`; it needs `emacs` and `emacsPackages.magit`, `emacsPackages.transient`, `emacsPackages.compat` on the load path, plus `git` and a writable `HOME` because the fixture runs `git init`
- [X] T003 Add `test-beads = nixpkgsFor.${system}.callPackage ./tests/beads.nix { };` to the Linux-only `packages` attrset in `flake.nix` (beside `test-disk-layout` and `test-emacs-sops-save`, around line 282), with the comment stating `nix build .#test-beads -L` and why it is a package rather than a check — it builds an Emacs closure and `nix flake check` runs before every commit
- [X] T004 `git add tests/beads.nix` and run `nix build .#test-beads -L` to confirm the existing suite passes inside the build before anything is added to it — the flake sees only git-tracked files

**Checkpoint**: the ERT suite runs as a build and is green on today's code.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the relation data layer. Every user story reads from it, so nothing
below Phase 2 can start until it is done.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T005 Extend the fake `bd` in the `beads-test--with-repo` macro in `workstation/emacs/packages/beads-test.el` with a `blocked)` case and a `list)` case that distinguishes `--id=`, each catting a fixture file, and add `beads-test--set-relations` beside `beads-test--set-issues` to write those fixtures; keep the existing stderr warning line so the parsing path stays the real one
- [X] T006 Add `beads--relation-limit`-independent plumbing to the `;;; Talking to bd` section of `workstation/emacs/packages/beads.el`: `beads--blocked-map`, calling `bd blocked --json` and returning a hash of issue id → list of blocker ids read from the `blocked_by` field (`blocked_by` is required; `blocked_by_count` is present but not relied on), returning nil rather than signalling when the call fails
- [X] T007 Add `beads--resolve-targets` to `;;; Talking to bd` in `workstation/emacs/packages/beads.el`: take a list of ids, call `bd list --id=<comma-separated> --all --json -n 0` **once** for all of them, and return a hash of id → alist with `id`, `title`, `status` and a `resolved` flag. `--all` is mandatory so a relation pointing at a closed issue resolves instead of looking deleted. An id requested and not returned is not an error: it yields `resolved` nil, `title` nil, `status` nil (data-model.md → Relation target validation)
- [X] T008 Add `beads--relations` to `workstation/emacs/packages/beads.el`, assembling one relation set per listed issue from the in-progress and ready lists: `parent` (a relation target or nil, from the issue's top-level `parent` field), `blockers` (a list of relation targets, from T006) and `dependent-count` (integer, from `dependent_count`, absent reads as 0). Gate the calls as research.md R4 requires — `beads--blocked-map` only when some **in-progress** issue has `dependency_count > 0`, `beads--resolve-targets` only when there is at least one parent or blocker id to resolve. Never store a set whose parent is nil, blockers empty and dependent-count zero
- [X] T009 Add the buffer-local relation table `beads--relation-table` to `workstation/emacs/packages/beads.el` with `beads--relations-at` reading a set out of it by issue id. Rebuild it from scratch in `beads-insert-issues`, never merging with the previous table, so a closed blocker's mark disappears on the next refresh. The `magit-section` value of a `beads-issue-section` MUST stay the bare id string — `beads--issue-at-point`, `beads--issues-at-point` and `beads--targets` all read it that way (research.md R8)
- [X] T010 Add `beads--relations-of-issue` to `workstation/emacs/packages/beads.el` for the no-table case: given an id, call `bd show <id> --json` once and build the same relation set from its top-level `parent` and its fat `dependencies` entries — `dependency_type` of `blocks` with a `status` other than `"closed"` is a blocker, `parent-child` names the parent. This is the only place status is read directly, and it is interactive-only; it must never be called from `beads-insert-issues`
- [X] T011 Make every relation call failure inert in `workstation/emacs/packages/beads.el`: when `beads--blocked-map` or `beads--resolve-targets` fails, the issues list exactly as they do today with no marks, and the failure is reported once in the section rather than per issue. A relation failure must never turn a working section into the error section (FR-015, contracts/bd-cli.md → Failure handling)
- [X] T012 Add an ERT test to `workstation/emacs/packages/beads-test.el` asserting that a fake `bd` whose `blocked` and `list --id=` cases fail still produces the full issue listing with no marks and no error section

**Checkpoint**: relations can be read and are held per buffer; nothing is drawn
yet, and a tracker with no relations makes no extra `bd` call.

---

## Phase 3: User Story 1 — See an issue's relations without leaving the status buffer (P1) 🎯 MVP

**Goal**: every listed issue that has a parent, a live blocker, or dependents is
marked as such, visible before any command is invoked; an issue with no
relations renders byte-identically to today.

**Independent test**: with a tracker holding one claimed issue that has a
parent, one claimed issue blocked by an open issue, one blocked only by a closed
issue and one with no relations, open `magit-status` and confirm each entry
states exactly its own relations and nothing more, and that the section lists
the same issues it listed before the feature.

- [X] T013 [US1] Add the faces `beads-relation` (inherits `magit-dimmed`; parent and dependent marks) and `beads-blocked` (inherits `warning`; the blocked mark and body line) to the face block near the top of `workstation/emacs/packages/beads.el`, each with a docstring in the shape of the existing `beads-critical` / `beads-high` / `beads-low` entries
- [X] T014 [US1] Add the `beads-relation-limit` defcustom to `workstation/emacs/packages/beads.el`, type `natnum`, default `5`, documenting that it caps how many blockers or dependents a body lists before the rest are summarised, and that the heading count is always the full one — the same contract `beads-ready-limit` states
- [X] T015 [US1] Extend `beads--format-issue` in `workstation/emacs/packages/beads.el` to append the heading marks after the priority column and before the title: `↑` when the issue has a parent (face `beads-relation`), `⊘N` when it has N blockers (face `beads-blocked`), `↳N` when N issues depend on it (face `beads-relation`). Add the marks' width to the `prefix` the truncation budget is computed from, so a long title still fits. An issue with no relations gets no mark **and no separator** — its heading must be byte-identical to today's (FR-005, SC-005)
- [X] T016 [US1] Add the body lines to `beads--insert-issue` in `workstation/emacs/packages/beads.el`, above the description and in the shape of the existing `Assignee:` line: `Parent:` with the parent's id and title, `Blocked by:` with each blocker's id, status in parentheses and title. Emit only the lines the issue actually has. Reuse `beads--fill`'s indent of 4
- [X] T017 [US1] Cap the body listings at `beads-relation-limit` in `workstation/emacs/packages/beads.el`, summarising the remainder as `…and N more` in the same shape and face the ready listing already uses (FR-016)
- [X] T018 [US1] Render an unresolved relation target as `<id> (unknown)` in both the heading count and the body line in `workstation/emacs/packages/beads.el`, without dropping it and without failing the section (FR-015)
- [X] T019 [US1] Wire `beads--relations` and the relation table into `beads-insert-issues` in `workstation/emacs/packages/beads.el`, between fetching the two lists and inserting the groups, so both groups draw from one table built once per refresh
- [X] T020 [P] [US1] Add ERT tests to `workstation/emacs/packages/beads-test.el` for the marks: parent mark and `Parent:` body line present (FR-001); two blockers both shown with status (FR-002); an issue whose only dependency is closed carries no `⊘` (FR-003); `dependent_count` shown as `↳N` (FR-004)
- [X] T021 [P] [US1] Add an ERT test to `workstation/emacs/packages/beads-test.el` asserting a relation-free issue's heading line is unchanged from the pre-feature format, character for character (FR-005, SC-005)
- [X] T022 [P] [US1] Add ERT tests to `workstation/emacs/packages/beads-test.el` for an unresolved blocker id rendering as unknown (FR-015) and for more blockers than `beads-relation-limit` being summarised as `…and N more` (FR-016)
- [X] T023 [US1] Add an ERT test to `workstation/emacs/packages/beads-test.el` that runs `beads-test--section-problems` with marks present across several refreshes — the marks add text to exactly the headings `dot-emacs-l3y` mangled, so the structural invariant must be re-asserted with them in place
- [X] T024 [US1] Add an ERT test to `workstation/emacs/packages/beads-test.el` that logs the fake `bd`'s argv and asserts a tracker whose listed issues have no relations invokes only `list --status=in_progress` and `ready` — no `blocked`, no `list --id=` (SC-004a, FR-018)

**Checkpoint**: US1 is independently shippable. Marks are visible and correct,
and cost nothing when there are no relations.

---

## Phase 4: User Story 2 — Move to a related issue in one step (P1)

**Goal**: from an issue, reach its parent, a chosen blocker, or a chosen
dependent without typing an identifier, landing in place when the target is
listed and in its own view when it is not.

**Independent test**: with point on a blocked issue, invoke the navigation
command and confirm the blocker becomes current — both when the blocker is
listed elsewhere in the same buffer and when it is not listed at all.

- [X] T025 [US2] Add `beads--relations-at-point` to `workstation/emacs/packages/beads.el`: in a `magit-section-mode` buffer read the relation set from the buffer-local table by the id at point; in a `beads-show-mode` buffer call `beads--relations-of-issue` for `beads--issue` (FR-011)
- [X] T026 [US2] Add `beads--goto` to `workstation/emacs/packages/beads.el` implementing the landing rule: if the current buffer holds a `beads-issue-section` whose value is the target id, `magit-section-show` it and move point to its start; otherwise call `beads-show` on the target. If the target has vanished since the display was built, report it and leave buffer, point and window configuration unchanged
- [X] T027 [US2] Add `beads--read-relation` to `workstation/emacs/packages/beads.el`: `completing-read` over a list of relation targets, each candidate annotated with status and title through `completion-extra-properties`, in the shape `beads--read-issue` already uses. One candidate returns it without prompting; aborting the prompt changes nothing
- [X] T028 [US2] Add the command `beads-goto-parent` to `;;; Acting on issues` in `workstation/emacs/packages/beads.el`: no parent → a message naming the issue, with point, buffer and window configuration unchanged; unresolved parent → a message that it could not be read; otherwise land via `beads--goto`
- [X] T029 [US2] Add the command `beads-goto-blocker` to `workstation/emacs/packages/beads.el`, reading the blockers from the relation set, one blocker going straight there and several going through `beads--read-relation`
- [X] T030 [US2] Add the command `beads-goto-dependent` to `workstation/emacs/packages/beads.el`, fetching the dependents **on demand** with `bd show <id> --json --include-dependents` and reading `id`, `title` and `status` from its `dependents` array. This call must never appear on the refresh path — `bd`'s own help warns it may be slow on hub beads (research.md R4, contracts/bd-cli.md)
- [X] T031 [US2] Autoload the three `beads-goto-*` commands in `workstation/emacs/packages/beads.el` with `;;;###autoload`, as the existing user-facing commands are
- [X] T032 [P] [US2] Add ERT tests to `workstation/emacs/packages/beads-test.el` for landing in place on a listed target (FR-009) and for opening `beads-show` on an unlisted one (FR-010)
- [X] T033 [P] [US2] Add an ERT test to `workstation/emacs/packages/beads-test.el` asserting that invoking a `beads-goto-*` command on an issue without that relation leaves point, the buffer contents and the window configuration unchanged and produces a message (FR-012)
- [X] T034 [P] [US2] Add an ERT test to `workstation/emacs/packages/beads-test.el` for a cycle — A blocks B and B blocks A — asserting each issue shows its own relations once and that jumping between them terminates

**Checkpoint**: US1 + US2 together are the feature as the request stated it —
relations marked, and easy to move to.

---

## Phase 5: User Story 3 — Come back from where you jumped (P2)

**Goal**: return to the issue a jump started from, repeatedly, in reverse order.

**Independent test**: from an issue, follow two relations in a row, then invoke
the return command twice and confirm each invocation lands on the previous issue
in reverse order.

- [X] T035 [US3] Add the session-scoped jump history to `workstation/emacs/packages/beads.el`: a global list of `(buffer . marker)` pairs, with `beads--push-location` recording the current buffer and a marker at point. A marker is required rather than a position because Magit rewrites the status buffer on every refresh. Not persisted across Emacs sessions
- [X] T036 [US3] Call `beads--push-location` from the three `beads-goto-*` commands in `workstation/emacs/packages/beads.el` **only on a successful jump** — a command that reports no such relation, an unresolved target, or an aborted prompt must push nothing, so FR-012's "nothing changes" holds for the history too
- [X] T037 [US3] Add the command `beads-go-back` to `workstation/emacs/packages/beads.el`, popping entries until one names a live buffer with a live marker, restoring it and stopping; dead entries are skipped silently, and an empty stack reports that there is nowhere to go back to. Autoload it
- [X] T038 [P] [US3] Add ERT tests to `workstation/emacs/packages/beads-test.el`: two jumps then two returns land in reverse order (FR-013); `beads-go-back` on an empty history messages and changes nothing; an entry whose buffer was killed is skipped rather than reported

**Checkpoint**: chains of relations are explorable without losing your place.

---

## Phase 6: User Story 4 — Act on relations from the issue menu (P3)

**Goal**: the four commands are discoverable in the `#` transient, each labelled
with what it acts on and greyed out when it does not apply.

**Independent test**: open the issue menu on an issue with a parent and a
blocker and confirm the relation entries are present, labelled, and visibly
unavailable when the issue at point has no such relation.

- [X] T039 [US4] Add a `Relations` column to the `beads-dispatch` prefix in `;;; The transient` of `workstation/emacs/packages/beads.el`: `p` → `beads-goto-parent`, `b` → `beads-goto-blocker`, `d` → `beads-goto-dependent`, `B` → `beads-go-back`
- [X] T040 [US4] Give each entry an `:inapt-if-not` predicate reading the relation set at point in `workstation/emacs/packages/beads.el` — no parent, no blockers, `dependent_count` of zero, empty history. Use `:inapt-if-not`, never `:if`: FR-014 requires the entry be *shown as unavailable*, and `:if` removes it, changing the menu's shape per issue (research.md R7)
- [X] T041 [US4] Confirm no key is bound outside the transient in `workstation/emacs/packages/beads.el` — `p`, `b` and `n` are live Magit keys, and a `beads-issue-section-map` entry would shadow them wherever point sits on an issue (research.md R6). `#` plus a letter is the two keystrokes SC-002 asks for

**Checkpoint**: the feature is discoverable without documentation.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T042 [P] Add the new domain terms to the `### Emacs / beads` section of `CONTEXT.md`, beside the existing `Ready` / `In progress` / `Beads section` entries: **Parent**, **Blocker** (with the existing rule that blocker resolution is bd's, never Emacs', as its rationale), **Dependent**, **Relation mark**, **Jump history**. Constitution Principle IV requires domain terms be defined once, there
- [X] T043 [P] Update the `** Beads` prose in `workstation/emacs/config.org` (around line 1396) to describe what `#` now offers and what the heading marks mean. The `use-package` block itself needs no change — no new key is bound outside the transient. Edit the `.org`, never a generated `.el`
- [X] T044 Run the full ERT suite with `nix build .#test-beads -L` and confirm every case in `quickstart.md` §1's table is covered by a test that exists
- [X] T045 Walk `quickstart.md` §2 manually in a scratch tracker — all eleven checks, including the cycle case and the two-keystroke and under-15-seconds measurements (SC-002, SC-003). **Done**: the behavioural checks (1–3, 7, 11) were run headlessly against the *real* `bd` and this repository's own tracker rather than the fake one — marks, body lines, `beads-goto-parent`, `beads-go-back` and the call counts all confirmed, and R11 was found that way. The keystroke count (SC-002) and the under-15-seconds chain (SC-003) were confirmed by the user at an interactive Emacs on 2026-09-24
- [X] T050 File the follow-up issues for what is out of scope by decision — editing relations, transitive ancestry, and surfacing blocked issues in the listing — so none of them looks like an omission
- [X] T046 Run the `quickstart.md` §3 cost check with the logging `bd` wrapper: this repository's tracker must show `list --status=in_progress` and `ready` only (SC-004a); the scratch tracker must show `blocked` and one `list --id=` once each per refresh, and adding ten more issues must not move that count (SC-004b)
- [X] T047 Run the constitution's required loop from `quickstart.md` §4: `git add -A`, `nix fmt` with unrelated churn reverted, `nix flake check`, `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`, `nix build .#test-beads -L`
- [~] T048 Deploy with `sudo nixos-rebuild switch --flake .#<hostname>`. **The user's step**: they confirmed the behaviour interactively on 2026-09-24 and rebuild after merging `magit-beads` into `main`
- [X] T049 Close the beads issues from T001 with `bd close`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies; T002 and T003 can run together, T004 needs both
- **Foundational (Phase 2)**: needs Phase 1 — the suite must be runnable before behaviour is added to it. **Blocks every user story**
- **US1 (Phase 3)**: needs Phase 2. No dependency on any other story
- **US2 (Phase 4)**: needs Phase 2. Independent of US1 in principle — the commands read the relation table, which Phase 2 builds — but far easier to verify once US1 makes relations visible
- **US3 (Phase 5)**: needs Phase 4. The history is pushed *by* the jump commands, so it cannot be tested without them. This is a genuine dependency, not a sequencing preference
- **US4 (Phase 6)**: needs Phase 4 for the three `goto` commands, and Phase 5 for the `B` entry. Can be built against US2 alone with the `B` entry added afterwards
- **Polish (Phase 7)**: T042 and T043 can be written any time after Phase 2 settles the vocabulary; T044–T049 need every desired story complete

### Within Each User Story

- Data before display: Phase 2 before any mark
- Faces and options before the code that uses them (T013, T014 before T015–T018)
- Landing helper before the commands that land (T026, T027 before T028–T030)
- History before the commands push to it (T035 before T036)
- Tests alongside, not after: each story's test tasks assert that story's
  requirements and should be written as its implementation lands

### Parallel Opportunities

Fewer than a template suggests, and deliberately so: T006–T041 nearly all edit
`workstation/emacs/packages/beads.el`, and marking them `[P]` would invite
conflicts rather than speed. The genuine ones:

- **T002 and T003** — `tests/beads.nix` and `flake.nix`, different files
- **T020, T021, T022** — separate ERT tests, appended to `beads-test.el`
- **T032, T033, T034** — likewise
- **T042 and T043** — `CONTEXT.md` and `config.org`, different files, neither
  touching `beads.el`

T023 and T024 are not marked `[P]` despite also being tests: T023 re-asserts the
structural invariant and T024 counts `bd` invocations, so both depend on the
mark rendering being finished.

---

## Parallel Example: User Story 1

```text
# After T019 wires the table into the section, the mark tests are independent:
Task: "T020 ERT tests for parent, blocker, closed-dependency and dependent marks in workstation/emacs/packages/beads-test.el"
Task: "T021 ERT test for an unchanged relation-free heading in workstation/emacs/packages/beads-test.el"
Task: "T022 ERT tests for an unresolved target and for the relation limit in workstation/emacs/packages/beads-test.el"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup — the suite runs as a build
2. Phase 2: Foundational — relations can be read (**blocks everything**)
3. Phase 3: User Story 1 — relations are marked
4. **STOP and VALIDATE**: `nix build .#test-beads -L`, then `quickstart.md` §2
   checks 1–3 in a scratch tracker
5. This alone answers "why is this not moving?" at a glance and is worth
   deploying

### Incremental Delivery

1. Setup + Foundational → relations readable, nothing drawn, no cost when absent
2. + US1 → marks visible → **MVP, deployable**
3. + US2 → relations are reachable → this is the request as stated
4. + US3 → chains are explorable without losing your place
5. + US4 → discoverable from `#` without documentation
6. Polish → vocabulary, prose, the full quickstart pass, deploy

Each step leaves the section working; none of them changes which issues are
listed.

### Parallel Team Strategy

Not applicable in the usual sense — one file holds the work. Two people could
split Phase 2 (data layer) from Phase 3's tests, or take Phase 7's `CONTEXT.md`
and `config.org` tasks while the rest proceeds, but `beads.el` wants one editor
at a time.

---

## Notes

- `[P]` tasks touch different files and have no incomplete dependency
- `[Story]` maps a task to a user story for traceability
- The `magit-section` value of a `beads-issue-section` stays the bare issue id;
  every existing command reads it that way
- Blocker resolution is `bd`'s, never Emacs' — `CONTEXT.md` says so and FR-017
  restates it; T006 is the only place the blocked set is obtained
- Commit after each task or logical group, Conventional Commits, `nix fmt` clean
- `git add` every new file before building — the flake sees only tracked files
