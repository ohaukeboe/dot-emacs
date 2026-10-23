---

description: "Task list for Review Walkthroughs"
---

# Tasks: Review Walkthroughs

**Input**: Design documents from `specs/006-review-walkthrough/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. The plan makes ERT the verifier for this package
(`packages.test-walkthrough`, constitution Principle III), as for `beads.el`.
Each story's tests are written before its implementation and must fail first.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)
- Exact file paths in every description

## Path Conventions

- `workstation/emacs/packages/walkthrough.el`: the package (names no agent package)
- `workstation/emacs/packages/walkthrough-test.el`: ERT suite against a throwaway git repository
- `tests/walkthrough.nix`, `flake.nix`: the `packages.test-walkthrough` build
- `workstation/emacs/config.org`: adapters (MCP tools, hand-off, `@` transient, `use-package walkthrough`) and prose
- `workstation/agents/skills/walkthrough/SKILL.md`: the `/walkthrough` skill

Tasks in the same file are sequential. `[P]` marks only tasks in a different
file from every task open at the same time.

**Beads issues for this feature** (already created):

| Issue | Covers |
|-------|--------|
| `dot-emacs-6ni` | the feature (epic) |
| `dot-emacs-6ni.1` | Phase 2: file format, validator, install |
| `dot-emacs-6ni.3` | Phase 3 (US1) buffer, Phase 4 (US2) finding placement |
| `dot-emacs-6ni.4` | Phase 5 (US3) marks |
| `dot-emacs-6ni.5` | Phase 5 (US3) hand-off, Phase 6 (US4) `:where` fix |
| `dot-emacs-6ni.6` | Phase 3 (US1) `open_walkthrough`, Phase 7 (US5) `@` keys |
| `dot-emacs-6ni.2` | Phase 3 (US1) and Phase 4 (US2) skill |

---

## Phase 1: Setup

**Purpose**: an empty package that builds and is tested, and a green baseline.

- [X] T001 Run `nix build .#test-beads -L` and `nix flake check` and confirm both pass unchanged, so every later failure belongs to this feature (test-beads: 40/40; the baseline `nix flake check` hit the 1-hour foreground cap, so it is re-run once in T045)
- [X] T002 Create `workstation/emacs/packages/walkthrough.el` with the standard header (`lexical-binding: t`, `Package-Requires: ((emacs "30.1") (magit "4.0"))`, Commentary saying the package names no agent package and that `config.org` supplies the adapters), `(require 'magit)`, `(require 'json)`, a `walkthrough` `defgroup` and `(provide 'walkthrough)`
- [X] T003 [P] Create `workstation/emacs/packages/walkthrough-test.el` with `(require 'ert)`, `(require 'walkthrough)` and a fixture macro `walkthrough-test--with-repo` that creates a temporary git repository with `main` and a branch of three commits touching four files: one new file, one file with two hunks far apart (lines ~10 and ~200), one deleted file and one binary file. Bind `default-directory` to it and expose `base` and `head` full SHAs
- [X] T004 [P] Create `tests/walkthrough.nix` modelled on `tests/beads.nix`: `emacsWithPackages (epkgs: [ epkgs.magit epkgs.markdown-mode ])`, git and coreutils, a header comment with `nix build .#test-walkthrough -L` and why it is a package and not a check, copying `walkthrough.el` and `walkthrough-test.el` and running `emacs -batch -L . -l walkthrough-test.el -f ert-run-tests-batch-and-exit`
- [X] T005 Add `test-walkthrough = nixpkgsFor.${system}.callPackage ./tests/walkthrough.nix { };` under `onLinux` in `flake.nix` next to `test-beads`, with the same style of comment; `git add` the four new files and confirm `nix build .#test-walkthrough -L` passes with zero tests

**Checkpoint**: an empty suite builds.

---

## Phase 2: Foundational (blocks all user stories) — `dot-emacs-6ni.1`

**Purpose**: read, validate and install a walkthrough file as in [contracts/walkthrough-file.md](./contracts/walkthrough-file.md) and research R3–R4.

### Tests (write first, must fail)

- [X] T006 In `walkthrough-test.el`, add tests for `walkthrough--parse-diff`: on the fixture it returns one entry per file (new path, or old path for the deleted file), each with its hunks as `(header new-start new-length)`; the binary file has no hunks
- [X] T007 In `walkthrough-test.el`, add tests for `walkthrough--hunk-overlaps-p` covering research R3's rule "a hunk `+c,d` covers new-side lines `c` to `c+d-1`; a hunk with `d = 0` covers the single position `c`; it overlaps `[s, e]` when `c <= e` and `max(c, c+d-1) >= s`", including the `+12,0` against `[12, 20]` case
- [X] T008 In `walkthrough-test.el`, add tests for `walkthrough-validate` returning the error messages of contracts/walkthrough-file.md: hunk owned by no step, hunk owned by two steps, a path owned whole by one step and by range by another, a binary file not owned, an anchor file not owned by its step, `base` or `head` not a commit, missing `title`/`explanation`/`severity`, `severity` not in `high|medium|low`, a range with `start > end` or `start < 1`, `version` not `1`; and an empty list for a valid draft whose two-hunk file is split across two steps by ranges
- [X] T009 In `walkthrough-test.el`, add tests for `walkthrough-install`: a valid draft is written to `<git-common-dir>/walkthroughs/<branch>.json` with `repo` set and finding ids `s<step>-f<n>`, and `/` in the branch name becomes `%2F`; an invalid draft returns `(error . MESSAGES)` and leaves an existing installed file byte-identical; a second install for the same branch replaces the first and carries no `state` over

### Implementation

- [X] T010 In `walkthrough.el`, implement `walkthrough-directory` (`git rev-parse --git-common-dir` + `walkthroughs/`, created on demand), `walkthrough--file-for-branch`, `walkthrough--read FILE` (`json-parse-buffer` with `:object-type 'alist :array-type 'list :null-object nil`) and `walkthrough--write DATA FILE` (write to a temp file in the same directory, then `rename-file` over the target)
- [X] T011 In `walkthrough.el`, implement `walkthrough--parse-diff BASE HEAD` over `git diff -U3 --no-prefix BASE HEAD` and `walkthrough--hunk-overlaps-p` (research R3)
- [X] T012 In `walkthrough.el`, implement `walkthrough-validate DATA`: schema checks from data-model.md (Walkthrough, Step, Finding tables), commit checks with `git cat-file -e <sha>^{commit}` and `git merge-base --is-ancestor`, and the coverage rule of research R4; collect every error as `<where>: <problem>`
- [X] T013 In `walkthrough.el`, implement `walkthrough-install DRAFT-FILE`: validate, then add `repo` and finding ids, write with `walkthrough--write`, and return `(ok . FILE)`; never signal for a bad draft. Leave opening the buffer to Phase 3
- [X] T014 Run `nix build .#test-walkthrough -L` until T006–T009 pass

**Checkpoint**: drafts are validated and installed; nothing is shown yet.

---

## Phase 3: User Story 1 — Read a branch's changes as a guided walkthrough (P1) 🎯 MVP

**Goal**: after the agent's run, a walkthrough buffer opens with steps in order, each with its explanation and its diffs.

**Independent Test**: spec US1, "On a branch with at least three commits touching at least four files …".

### Tests (write first, must fail)

- [X] T015 [US1] In `walkthrough-test.el`, add buffer tests: `walkthrough-open` on an installed fixture walkthrough yields a buffer in `walkthrough-mode` (`derived-mode-p 'magit-diff-mode`), `magit-buffer-diff-type` is `committed`, `magit-buffer-diff-range` is `"<base>..<head>"`, `magit-buffer-revision` is nil; the step sections appear in file order of the JSON with headings and explanations; every hunk header of the base-to-head diff appears exactly once across the buffer; for the split file, step 1 shows only the line-10 hunk and step 2 only the line-200 hunk
- [X] T016 [US1] In `walkthrough-test.el`, add tests: a step whose files produce no diff output keeps its heading and explanation (research R2, `magit-cancel-section` pitfall); `walkthrough-next-step` and `walkthrough-previous-step` land on step headings; refresh (`g`) keeps the same steps and restores point within a step
- [X] T017 [US1] In `walkthrough-test.el`, add tests for FR-019: with the branch tip moved past `head`, the header says the branch head has moved; with a `head` that is not a commit, `walkthrough-open` signals a `user-error` naming the walkthrough and suggesting a re-run

### Implementation

- [X] T018 [US1] In `walkthrough.el`, define `walkthrough-mode` derived from `magit-diff-mode`, add it to `magit-xref-modes`, add a `magit-buffer-value` method on it returning the walkthrough file, and implement `walkthrough-open FILE` with `magit-setup-buffer` binding the locals listed in research R2 plus `walkthrough--file` and `walkthrough--data`
- [X] T019 [US1] In `walkthrough.el`, implement `walkthrough-refresh-buffer`: header line (title, `base`..`head` short SHAs, moved notice), `magit-buffer-diff-range-oids`, then `(magit-insert-section (diffbuf) …)` containing one `(walkthrough-step INDEX)` section per step with heading and explanation (plain text for now), then a `(walkthrough-diff INDEX)` child holding the step's diff
- [X] T020 [US1] In `walkthrough.el`, implement `walkthrough--insert-step-diff`: plain `magit-git-wash #'magit-diff-wash-diffs "diff" range "-p" "--no-prefix" args "--" files` when no file has ranges; otherwise `magit-git-insert`, drop non-overlapping `@@` blocks and files left with no hunks, narrow, and call `magit-diff-wash-diffs` (research R3)
- [X] T021 [US1] In `walkthrough.el`, implement `walkthrough-next-step` / `walkthrough-previous-step` and bind `N` / `P` in `walkthrough-mode-map`
- [X] T022 [US1] In `walkthrough.el`, make `walkthrough-install` open the installed file with `walkthrough-open` and return `(ok . FILE)`; run `nix build .#test-walkthrough -L` until T015–T017 pass
- [X] T023 [US1] In `workstation/emacs/config.org`, add a `use-package walkthrough :after magit :demand t` block with a prose paragraph in the Magit review section, and in the Claude Code section add the MCP tool `open_walkthrough` (`claude-code-ide-make-tool`, required string argument `path`) that calls `walkthrough-install` with `default-directory` from `claude-code-ide-mcp-server-get-session-context` `:project-dir`, returning `Opened <file>` or the messages joined by newlines (contracts/interfaces.md)
- [X] T024 [P] [US1] Create `workstation/agents/skills/walkthrough/SKILL.md` (frontmatter `name: walkthrough`, a description that triggers on "walkthrough", "walk me through the changes"; `disable-model-invocation: true`) with contracts/interfaces.md steps 1, 3, 5 and 6: base resolution and uncommitted-change notice, step grouping rules (FR-006, split by `ranges` only for unrelated changes in one file), the draft format copied from contracts/walkthrough-file.md with empty `findings`, writing to `$TMPDIR/walkthrough-<branch>.json`, calling `open_walkthrough`, and retrying on validation messages; it never edits code, commits or posts

**Checkpoint**: `/walkthrough` produces a buffer with steps and diffs (no findings yet). MVP.

---

## Phase 4: User Story 2 — See the agent's findings in place (P1)

**Goal**: the built-in review's findings appear below the lines they concern.

**Independent Test**: spec US2, "On a branch with a planted defect …".

### Tests (write first, must fail)

- [X] T025 [US2] In `walkthrough-test.el`, add placement tests per data-model.md "Placement": an anchored finding is a `walkthrough-finding` section directly after the line `end_line` (or `line`) of its hunk in its step; an anchored finding whose line no hunk of the step shows appears at the top of the step with "not placed"; an unanchored finding appears after the explanation; severity and title are on the finding's first line; a walkthrough with no findings shows a "No findings" line
- [X] T026 [US2] In `walkthrough-test.el`, add tests that `walkthrough-next-finding` / `walkthrough-previous-finding` move between findings across step boundaries, and that an unknown finding key (e.g. `"confidence": "x"`) is shown as text and survives a reload

### Implementation

- [X] T027 [US2] In `walkthrough.el`, implement `walkthrough--render-markdown TEXT`: insert into a temporary `markdown-mode` buffer with `markdown-hide-markup` t, `font-lock-ensure`, return the propertized string; fall back to plain filled text when `markdown-mode` is not available. Add `markdown-markup` to the buffer's invisibility spec in `walkthrough-mode`, and use it for explanations too
- [X] T028 [US2] In `walkthrough.el`, implement `walkthrough--insert-finding` (a `(walkthrough-finding ID)` section with faces per severity; body, failure scenario, verdict, category and unknown keys in its content) and place findings after washing by walking each hunk's lines with `magit-diff-hunk-line`, following data-model.md "Placement"
- [X] T029 [US2] In `walkthrough.el`, implement `walkthrough-next-finding` / `walkthrough-previous-finding` and bind `n` / `p` in `walkthrough-mode-map` (research R8); run `nix build .#test-walkthrough -L` until T025–T026 pass
- [X] T030 [P] [US2] In `workstation/agents/skills/walkthrough/SKILL.md`, add contracts/interfaces.md steps 2 and 4: run the built-in review through the Skill tool as `code-review` on `<base>...<head>` (stop and say so if it cannot be invoked), then map its findings with research R5's table, setting `severity` from rank and verdict and putting each finding in the step that owns its file

**Checkpoint**: US1 and US2 together match the original request's reading experience.

---

## Phase 5: User Story 3 — Mark findings and hand the accepted ones off (P2)

**Goal**: `a`/`x`/`u` mark findings, marks persist, `@ s` sends accepted findings with pending comments.

**Independent Test**: spec US3, "In a walkthrough with three findings, accept one, dismiss one …".

### Tests (write first, must fail)

- [X] T031 [US3] In `walkthrough-test.el`, add tests for the state machine in data-model.md "Finding states": `a` on unmarked or dismissed → `accepted`; `x` on unmarked or accepted → `dismissed`; `u` → unmarked; a `sent` finding refuses every mark with a `user-error`; each mark is in the file right after the command and survives killing the buffer and reopening; marking one finding while another's state was changed in the file on disk keeps both (re-read before write)
- [X] T032 [US3] In `walkthrough-test.el`, add tests for `walkthrough-accepted-findings`: returns only accepted, unsent findings as plists with `:repo :file :new :old :where :patch :text :kind :severity :title :id :walkthrough`, where `:patch` is the anchored hunk and `:where` equals `walkthrough-diff-label` of the walkthrough's range; with `INCLUDE-SENT` also sent ones; `walkthrough-mark-sent` moves exactly those to `sent` and refreshes open walkthrough buffers

### Implementation

- [X] T033 [US3] In `walkthrough.el`, implement `walkthrough-accept`, `walkthrough-dismiss`, `walkthrough-unmark` (re-read, update the one finding by `id`, `walkthrough--write`, refresh), show the state on the finding's first line, dim `sent` findings, and bind `a` `x` `u` in `walkthrough-finding-map`, the keymap property of findings only (research R8)
- [X] T034 [US3] In `walkthrough.el`, implement `walkthrough-accepted-findings REPO &optional INCLUDE-SENT` over every file in `walkthrough-directory`, oldest first, and `walkthrough-mark-sent ITEMS`; run `nix build .#test-walkthrough -L` until T031–T032 pass
- [X] T035 [US3] In `workstation/emacs/config.org`, make `my/magit-review-send` and `my/magit-review-paste` hand off pending review comments plus `(walkthrough-accepted-findings repo)`, erroring only when both are empty (spec US3 scenario 6); make `my/magit-review--format` head a finding item with its severity and title and print its body plus failure scenario as text; make `my/magit-review--hand-off` call `walkthrough-mark-sent` on the finding items and keep `plist-put :sent` for comments
- [X] T036 [US3] In `workstation/emacs/config.org`, make the `magit_review_comments` MCP tool include accepted findings, and sent ones when `include_sent`; update its `:description` to say so

**Checkpoint**: the full loop from the request works: read, mark, hand off.

---

## Phase 6: User Story 4 — Comment on the walkthrough's lines (P2)

**Goal**: review comments work in the walkthrough and match comments on an ordinary diff of the same commits.

**Independent Test**: spec US4, "In a walkthrough, select two changed lines and add a review comment …".

### Tests (write first, must fail)

- [X] T037 [US4] In `walkthrough-test.el`, add tests for `walkthrough-diff-label`: in a walkthrough buffer it returns `diff of <base-oid>..<head-oid>`; in a `magit-diff` buffer of `main..<branch>` resolving to the same commits it returns the identical string; with no committed range it returns nil. This is the regression case for the `magit-buffer-range` rename (research R6)

### Implementation

- [X] T038 [US4] In `walkthrough.el`, implement `walkthrough-diff-label` from `magit-buffer-diff-range-oids`, else `magit-buffer-diff-range` resolved with `magit-rev-parse`; run `nix build .#test-walkthrough -L` until T037 passes
- [X] T039 [US4] In `workstation/emacs/config.org`, change `my/magit-review--where`'s fallback branch to use `walkthrough-diff-label` (then `magit-buffer-revision`) instead of the unbound `magit-buffer-range`, and note the rename in the surrounding prose
- [X] T040 [US4] Manually confirm quickstart step 3: a comment made with `@ c` in a walkthrough is decorated there and in `magit-diff main..HEAD`, and the reverse (checked in batch Emacs against the fixture, with config.org's review blocks loaded; recheck live in T046)

**Checkpoint**: comments and findings share one hand-off and one identity.

---

## Phase 7: User Story 5 — Start and reopen walkthroughs from the editor (P3)

**Goal**: `@ w` reopens, `@ W` asks the agent session for a walkthrough.

**Independent Test**: spec US5, "From the review menu, start a walkthrough …".

### Tests (write first, must fail)

- [X] T041 [US5] In `walkthrough-test.el`, add tests with a recorder bound to `walkthrough-request-function`: `walkthrough-request` sends `/walkthrough` with submit t, and `/walkthrough <base>` when given a base; with the function nil it signals a `user-error` saying no agent is configured and calls nothing; `walkthrough-open-current` opens the current branch's file, and with none offers `walkthrough-request` (stub `y-or-n-p`)

### Implementation

- [X] T042 [US5] In `walkthrough.el`, add `defcustom walkthrough-request-function` with `:type '(choice (const nil) function)`, and implement `walkthrough-request &optional BASE` (prefix argument reads a ref with `magit-read-branch-or-commit`) and `walkthrough-open-current &optional PICK` (`completing-read` over `walkthrough-directory` with a prefix argument); run `nix build .#test-walkthrough -L` until T041 passes
- [X] T043 [US5] In `workstation/emacs/config.org`, set `(walkthrough-request-function #'my/claude-code-ide-paste)` in the `use-package walkthrough` `:custom`, and add a "Walkthrough" column to `my/magit-review` with `w` → `walkthrough-open-current` and `W` → `walkthrough-request`; mention both keys in the section's prose

**Checkpoint**: all five stories work.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T044 Re-read `GLOSSARY.md` (Walkthrough, Step, Finding, Review hand-off) against the implementation and fix any term that drifted; confirm `docs/adr/0007-walkthrough-diffs-from-shas.md` still describes what was built
- [X] T045 Run `nix fmt`, revert unrelated churn, then `nix flake check`, `nix build .#test-walkthrough -L`, `nix build .#test-beads -L` and `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'` (test-walkthrough 17/17, test-beads, home build, checks formatting/agent-commit-gate/check-fixes/expiring-override built one by one; formatting fails only on nvfetcher.toml, unchanged from HEAD, filed as dot-emacs-k54; `nix fmt` itself is blocked by the sandbox (read-only ~/.cache/treefmt); the whole `nix flake check` hung the session twice, so checks.installer and the full run were skipped; laptop and dig-laptop toplevels evaluate)
- [ ] T046 After the user's `nixos-rebuild switch`, walk through `specs/006-review-walkthrough/quickstart.md` manual steps 1–6, starting with step 1 (the research R5 risk), and record the outcome in the bead notes of `dot-emacs-6ni`
- [ ] T047 Close the finished beads with `bd close dot-emacs-6ni.1 dot-emacs-6ni.3 dot-emacs-6ni.4 dot-emacs-6ni.5 dot-emacs-6ni.6 dot-emacs-6ni.2` and file new beads for anything left over

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** → **Phase 2** → **Phase 3 (US1)**, which every later story needs because it creates the buffer.
- **US2** needs US1. **US3** needs US2 (findings must exist to be marked).
- **US4** needs only US1. It can run beside US2/US3, except that T039 and T035 both edit `config.org`, so they are sequential.
- **US5** needs only US1.
- **Polish** needs all stories.

### Within Each Story

Tests first, must fail → `walkthrough.el` → `config.org` / `SKILL.md`. All
`walkthrough.el` tasks are sequential with each other, and so are all
`walkthrough-test.el` and all `config.org` tasks.

### Parallel Opportunities

- T003 and T004 (different new files), then T005.
- T024 (`SKILL.md`) beside T018–T023.
- T030 (`SKILL.md`) beside T027–T029.
- After US1: US4's tests and implementation (T037–T038) beside US2's, as long as the two do not edit `walkthrough.el` at the same moment. In practice, interleave rather than truly parallelise.

## Parallel Example: User Story 1

```text
Task: "T018–T022 walkthrough-mode, refresh and step diffs in workstation/emacs/packages/walkthrough.el"
Task: "T024 Create workstation/agents/skills/walkthrough/SKILL.md"
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phases 1–2: the package builds and validates drafts.
2. Phase 3: `/walkthrough` opens a navigable step-by-step diff.
3. **Stop and validate**: quickstart step 2 without findings.

### Incremental Delivery

1. US1 → a guided read of a branch.
2. US2 → findings in place (the review quality the user asked for).
3. US3 → mark and hand off (closes the loop).
4. US4 → comment identity fixed (also fixes today's mislabelled range comments).
5. US5 → `@ w` / `@ W` convenience.
