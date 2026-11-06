---

description: "Task list for Project Tours and Project Audits"
---

# Tasks: Project Tours and Project Audits

**Input**: Design documents from `specs/009-project-tour-audit/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included. ERT (`packages.test-walkthrough`) is the verifier for
`walkthrough.el`, as in 006. Each story's tests are written before its
implementation and must fail first. Skills are checked by the manual steps in
[quickstart.md](./quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US5)

## Path Conventions

- `workstation/emacs/packages/walkthrough.el` (WT): the package
- `workstation/emacs/packages/walkthrough-test.el` (WTT): its ERT suite
- `workstation/emacs/config.org` (CO): adapters, `@` transient, prose
- `workstation/agents/skills/project-tour/SKILL.md`,
  `workstation/agents/skills/project-audit/SKILL.md`: the skills
- Run the suite with `nix build .#test-walkthrough -L`

Tasks in the same file are sequential. `[P]` marks only tasks in a file no
other open task touches.

**Beads issues** (epic `dot-emacs-ofg`):

| Issue             | Covers                                        |
|-------------------|-----------------------------------------------|
| `dot-emacs-ofg.1` | Phase 1–2: spike, kinds, excerpts, label      |
| `dot-emacs-ofg.2` | Phase 3 (US1): tour rules, `project-tour`     |
| `dot-emacs-ofg.3` | Phase 4 (US2): audit rules, `project-audit`   |
| `dot-emacs-ofg.4` | Phase 5 (US3): audit findings in hand-off     |
| `dot-emacs-ofg.5` | Phase 6 (US4): comments on excerpts, diagrams |
| `dot-emacs-ofg.6` | Phase 7 (US5): open/request, `@` column       |
| `dot-emacs-ofg.7` | Phase 8: ADR, glossary, docs, gates           |

---

## Phase 1: Setup

**Purpose**: green baseline and the one risky assumption checked.

- [X] T001 Run `nix build .#test-walkthrough -L` and confirm it passes unchanged, so later failures belong to this feature
- [X] T002 (Done as part of `walkthrough-test-code-render`, which asserts `RET` on an excerpt line visits `<commit>:a.el` at line 41: R2 holds.) Spike research R2 in a throwaway ERT test in `workstation/emacs/packages/walkthrough-test.el`: in the existing `walkthrough-test--with-repo` fixture, open a `walkthrough-mode` buffer with `magit-buffer-diff-range` `"<head>..<head>"`, insert the text `diff --git f f\n--- f\n+++ f\n@@ -10,3 +10,3 @@\n` plus three lines each prefixed by one space, wash it with `magit-diff-wash-diffs` (args `("--no-prefix")`), then assert (a) point on the second line gives `magit-diff-hunk-line` 11 for the new side; (b) `magit-diff-visit-file-noselect` (or what `RET` calls) returns a buffer of `<head>:f` (or the work-tree `f`) with point on line 11. If (b) fails, record it in `specs/009-project-tour-audit/research.md` R2 and add T013's fallback visit command; keep the test as a regression case either way

**Checkpoint**: R2 holds, or its fallback is chosen.

---

## Phase 2: Foundational (blocks every story)

**Purpose**: `kind` `tour`/`audit` validate, install and render, with code
excerpts shown as synthetic context-only hunks.

### Tests (write first, must fail)

- [X] T003 Add a fixture helper `walkthrough-test--draft (kind &rest steps)` in `workstation/emacs/packages/walkthrough-test.el` that writes a draft JSON with `"version": 1`, `"kind"`, `"title"`, `"commit"` = fixture head and STEPS to a temp file; add tests that `walkthrough-validate` reports, each with the exact message of `specs/009-project-tour-audit/contracts/walkthrough-file.md`: `commit: <x> is not a commit`; `steps[i].files[j]: <file> does not exist at <abbrev>`; `steps[i].files[j].ranges[k]: [s, e] ends after line <n> of <file>`; `steps[i].files[j].ranges[k]: [s, e] spans <n> lines, at most 80`; a `files` entry that is a bare path (tour/audit entries must be `{file, ranges}`); `steps[i].explanation line <n>: diagram is <w> columns wide, at most 90` for a fenced-block line wider than 90 (`string-width`), while a 120-column prose line is accepted; that `files` may be absent; and that several errors come back together
- [X] T004 Add tests in `workstation/emacs/packages/walkthrough-test.el` that `walkthrough-install` of a valid tour draft writes `<git-common-dir>/walkthroughs/:tour.json` and of an area `"area": "dir/sub"` writes `:tour:dir%2Fsub.json`; that the installed file has `base` = `head` = the full commit id and `repo`, and no `branch`; that an invalid draft leaves an existing `:tour.json` byte-identical; and that a draft without `kind` still goes through the hunk-coverage validator (existing behaviour)
- [X] T005 Add rendering tests in `workstation/emacs/packages/walkthrough-test.el`: a tour step with `files` `[{"file": F, "ranges": [[5, 9], [8, 12], [40, 41]]}]` renders one `file` section for F with two `hunk` sections whose `to-range` are `(5 8)` and `(40 2)` (overlapping/adjacent ranges merge, R8) and whose lines are F's lines at the commit, not the work tree (modify F uncommitted in the fixture first); a step without `files` renders heading and explanation only; `walkthrough-diff-label` in that buffer returns `code at <full oid>`; the intro says the repository has moved when `HEAD` is not the commit and says nothing when it is

### Implementation

- [X] T006 In `workstation/emacs/packages/walkthrough.el` add `walkthrough--kind (data)` returning `"changes"` when `kind` is absent, and `walkthrough--code-lines (commit file)` returning FILE's lines at COMMIT via `magit-git-insert "show" "<commit>:<file>"` (nil when the blob is missing or binary, i.e. contains a NUL), memoised per refresh with a hash table bound around validation and rendering
- [X] T007 In `workstation/emacs/packages/walkthrough.el` add `walkthrough--validate-code (data)` implementing research R5's shared rules for tour/audit: `commit` resolves to a commit; `branch`, `base`, `head` not required; `area` optional non-empty string; `skipped` optional array of non-empty strings; `files` optional, each entry `{file, ranges}` with `1 <= start <= end <=` the file's line count at `commit` and `end - start + 1 <= 80`; fenced-block lines (between lines starting with three backticks) in every explanation at most 90 columns by `string-width`. Make `walkthrough-validate` dispatch on `walkthrough--kind`: `"changes"` runs today's schema, commits and coverage checks unchanged; `"tour"`/`"audit"` run the step/finding parts of `walkthrough--validate-schema` that apply (title, explanation, finding severity/title/body) plus `walkthrough--validate-code`. Messages as in `contracts/walkthrough-file.md`
- [X] T008 In `workstation/emacs/packages/walkthrough.el` make `walkthrough-install` for tour/audit set `base` and `head` to `(magit-rev-parse commit)` and drop `commit`, and install to `walkthrough--file-for-code (kind area)` returning `:<kind>.json` or `:<kind>:<area with / as %2F>.json` in `walkthrough-directory` (research R6)
- [X] T009 In `workstation/emacs/packages/walkthrough.el` add `walkthrough--code-hunk (commit file start end)` returning the text `@@ -S,N +S,N @@\n` followed by each line of FILE START..END at COMMIT prefixed with one space, and `walkthrough--code-ranges (step)` returning an alist file → merged ranges (sort, then merge when `next-start <= end + 1`). Add `walkthrough--insert-code-diff (step commit)` that inserts, per file in first-mention order, `diff --git F F\n--- F\n+++ F\n` plus its hunks, then washes the region with `magit-diff-wash-diffs` under the same narrowing as the ranged path of `walkthrough--insert-step-diff`; cancels the section when there is nothing
- [X] T010 In `workstation/emacs/packages/walkthrough.el` make `walkthrough--insert-step` call `walkthrough--insert-code-diff` instead of `walkthrough--insert-step-diff` for tour/audit (passing the step and the data's `head`), and make `walkthrough-refresh-buffer` skip `walkthrough--parse-diff` for them; `walkthrough-open` keeps `magit-buffer-diff-range` `"<base>..<head>"`, which is `C..C`
- [X] T011 In `workstation/emacs/packages/walkthrough.el` make `walkthrough-diff-label` return `code at <oid>` when both ends of the range are the same oid (research R9), and make `walkthrough--insert-intro` for tour/audit print `Code at <abbrev>[ in <area>], in N steps.`, the `skipped` entries as a list headed `Not covered:`, and, when `(magit-rev-parse "HEAD")` differs from `head`, `The repository has moved since (HEAD is now <abbrev>).` in `warning`; the header line says `Tour:`/`Audit:` instead of `Walkthrough:`
- [X] T012 Run `nix build .#test-walkthrough -L`; T003–T005 and every existing test pass
- [X] T013 (Not needed: T002(b) passed.) Only if T002(b) failed: add `walkthrough-visit-code` in `workstation/emacs/packages/walkthrough.el` that opens `magit-find-file-noselect head file` at the hunk line at point, and bind it to `RET` in tour/audit buffers through a buffer-local keymap parent; add its test to `workstation/emacs/packages/walkthrough-test.el`

**Checkpoint**: a hand-written tour or audit draft installs and renders.

---

## Phase 3: User Story 1 — Get to know a project through a guided tour (P1) 🎯 MVP

**Goal**: `/project-tour [AREA]` produces a tour that opens in Emacs.

**Independent Test**: spec US1; quickstart Manual 1–2.

### Tests (write first, must fail)

- [X] T014 [US1] Add tests in `workstation/emacs/packages/walkthrough-test.el` that a tour draft is rejected with `steps[0].explanation: a tour's first step needs a diagram (a fenced block)` when step 1 has no fenced block, and with `steps[i].findings: a tour has no findings` when any step has a non-empty `findings`

### Implementation

- [X] T015 [US1] Add the two tour rules to `walkthrough--validate-code` in `workstation/emacs/packages/walkthrough.el` (FR-020, FR-025); run the suite
- [X] T016 [P] [US1] Write `workstation/agents/skills/project-tour/SKILL.md` with frontmatter `name: project-tour`, a description that says it produces a guided tour of a project's structure and how its parts work together and opens it in the user's Emacs, used when the user runs `/project-tour` or asks for a tour of the project, and `disable-model-invocation: true`. Body, following the style of `workstation/agents/skills/walkthrough/SKILL.md` and `specs/009-project-tour-audit/contracts/interfaces.md` § Skill `project-tour`: read-only rule; argument `[AREA]`; 1. pin `git rev-parse HEAD`, name uncommitted changes left out; 2. explore (docs, `AGENTS.md`, ADRs, entry points, build files; `codebase-memory` `get_architecture`/`trace_path` when the tools exist; `Explore` subagents per area for a large tree; skip generated, vendored and lock files); 3. shape 6–15 steps: overview with a diagram first, foundations, parts, cross-cutting flows, each saying what it uses and what uses it; diagrams as fenced ```text blocks at most 90 columns wherever 3+ parts interact; excerpts as `{file, ranges}` of at most 40 lines (80 is rejected), only where the point depends on the code; no findings; 4. `skipped`; 5. the draft format (copy the tour example from `contracts/walkthrough-file.md`, saying Emacs adds `repo`, `base`, `head`), written to `$TMPDIR/tour.json` (`tour-<area with / as ->.json` for an area), then `open_walkthrough` with its absolute path, fixing and retrying on errors, and saying so if the tool is missing; 6. report steps, area, skipped, and that `@ c`/`@ d` ask questions in place
- [X] T017 [P] [US1] In `workstation/emacs/config.org` widen the `open_walkthrough` tool's `:description` to "Validate a draft walkthrough, project tour or project audit JSON file and, when it is valid, install it for the current project and open it in the user's Emacs. …" (rest unchanged)
- [X] T018 [US1] `git add workstation/agents/skills/project-tour/SKILL.md`, build the home configuration (`nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`) and confirm the skill is in the merged skills directory of the result

**Checkpoint**: US1 is usable after activation.

---

## Phase 4: User Story 2 — Audit a whole project for bugs and code smells (P1)

**Goal**: `/project-audit [AREA]` produces an audit whose findings show their
code.

**Independent Test**: spec US2; quickstart Manual 3.

### Tests (write first, must fail)

- [X] T019 [US2] Add tests in `workstation/emacs/packages/walkthrough-test.el` that an audit draft is rejected with `steps[i].findings[k].type: must be defect or smell`; `…verdict: a defect needs CONFIRMED or PLAUSIBLE`; `…failure_scenario: a defect needs one`; `…anchor.side: not allowed in an audit`; and an anchor whose line is past the file's end at the commit; and accepted when a smell has no verdict or failure scenario and when an anchor's file is not among the step's `files` (research R8)
- [X] T020 [US2] Add rendering tests in `workstation/emacs/packages/walkthrough-test.el`: an audit step with no `files` and one finding anchored at F lines 20–21 renders one hunk with `to-range` `(17 8)` (± `walkthrough-excerpt-context` 3) and the finding drawn below line 21 by `walkthrough--draw-anchored`; a finding with no anchor is drawn below the explanation; the finding heading shows `DEFECT` or `SMELL` after the severity; an audit with no findings says `No findings.` and lists `Not covered:`

### Implementation

- [X] T021 [US2] Add the audit finding rules to `walkthrough--validate-code` in `workstation/emacs/packages/walkthrough.el` (`type` in `defect`/`smell`; defect needs `failure_scenario` and `verdict` in `CONFIRMED`/`PLAUSIBLE`; `anchor.side` absent; anchor `line`/`end_line` within the file at `commit`; anchor file not required in `files`)
- [X] T022 [US2] In `workstation/emacs/packages/walkthrough.el` make `walkthrough--code-ranges` add, for each anchored finding of an audit step, `[max 1 (line - walkthrough-excerpt-context), min count (end_line + walkthrough-excerpt-context)]` before merging; add `type` to `walkthrough--known-keys` and show it upcased after the severity in `walkthrough--finding-block`; make `walkthrough--placed-p`/`walkthrough--shown-hunks` work for code hunks (anchors are new-side lines of the code hunks)
- [X] T023 [P] [US2] Write `workstation/agents/skills/project-audit/SKILL.md` with frontmatter `name: project-audit`, a description that says it audits the whole project (or an area) for bugs and code smells and opens the findings in the user's Emacs, used for `/project-audit` or "audit this project", and `disable-model-invocation: true`. Body following `contracts/interfaces.md` § Skill `project-audit`: read-only rule; never run the project's tests or install dependencies; 1. pin the commit, name uncommitted changes left out; 2. `git ls-files` in AREA, drop generated, vendored and lock files, split into at most 6 areas; 3. one `general-purpose` subagent per area, all in one message, each given the commit, its file list, the defect/smell definitions of spec FR-030, and asked to return a JSON array of findings (severity, type, title, body, failure_scenario for defects, anchor `{file, line, end_line}`) and nothing else; 4. in the main session, read the code of every defect and set `verdict` `CONFIRMED` or `PLAUSIBLE`, drop findings that are wrong, merge a smell found in several places into one finding whose body lists them and whose anchor is the first; severity rules (a confirmed defect reachable in normal use is `high`); 5. one step per area, explanation giving enough context to judge its findings, `skipped` listing what was not read and why; 6. the audit draft format (copy the example from `contracts/walkthrough-file.md`), written to `$TMPDIR/audit.json` (`audit-<area>.json`), then `open_walkthrough`, fixing and retrying; 7. report counts by severity and type, and that `a`/`x`/`u` mark, `@ c` replies and `@ s` hands accepted ones off; don't fix anything until then
- [X] T024 [US2] Run the suite; `git add workstation/agents/skills/project-audit/SKILL.md`; build the home configuration as in T018

**Checkpoint**: US2 is usable; marks already work (shared code).

---

## Phase 5: User Story 3 — Mark audit findings and hand off the accepted ones (P1)

**Goal**: accepted audit findings travel in `@ s` with their code.

**Independent Test**: spec US3; quickstart Manual 4.

### Tests (write first, must fail)

- [X] T025 [US3] Add tests in `workstation/emacs/packages/walkthrough-test.el`: with an installed audit (one finding accepted, one dismissed, one replied) and an installed branch walkthrough with one accepted finding, `walkthrough-accepted-findings` returns exactly three items; each audit item has `:where` `code at <oid>`, `:new` the anchor range, `:old` nil, `:type`, and `:patch` equal to `(walkthrough--code-hunk oid file (- line 3) (+ end 3))`; `walkthrough-mark-sent` on them sets `state` `"sent"` in `:audit.json`; `a`/`x`/`u` in an audit buffer persist to the file (re-read it)

### Implementation

- [X] T026 [US3] In `workstation/emacs/packages/walkthrough.el` make `walkthrough--hand-off-item` for tour/audit build `:where` with the `code at` label, `:patch` with `walkthrough--code-hunk` over the anchor ± `walkthrough-excerpt-context`, and add `:type`; make `walkthrough-accepted-findings` skip `walkthrough--parse-diff` for them; run the suite
- [X] T027 [P] [US3] In `workstation/emacs/config.org` make `my/magit-review--format` print a finding's `:type` after its severity (`Finding [high, defect] Title: …`), keeping today's text when `:type` is nil

**Checkpoint**: US3 complete.

---

## Phase 6: User Story 4 — Comment on a tour or audit (P2)

**Goal**: `@ c`/`@ d` on excerpts, explanations and diagrams.

**Independent Test**: spec US4; quickstart Manual 5.

### Tests (write first, must fail)

- [X] T028 [US4] Add tests in `workstation/emacs/packages/walkthrough-test.el` that in a tour buffer `walkthrough-comment-target` on a selected region of a fenced diagram inside the explanation returns the step and the quoted lines, and that on an excerpt hunk it returns nil (so the configuration records a hunk comment), with `magit-diff-hunk-line` of a region's start and end giving the file's line numbers

### Implementation

- [X] T029 [US4] In `workstation/emacs/config.org` change the opening sentence chosen by `my/magit-review--format` to say "the file, the new/old line range and the diff or commit it refers to", and the step-comment intro in `my/magit-review-comment-send` to "Here is a comment on a walkthrough step: a question or a request.  It names "; fix anything T028 shows is missing in `workstation/emacs/packages/walkthrough.el`

**Checkpoint**: US4 complete.

---

## Phase 7: User Story 5 — Start and reopen tours and audits from the editor (P3)

**Goal**: `@ t`/`@ T`/`@ a`/`@ A`.

**Independent Test**: spec US5; quickstart Manual 6.

### Tests (write first, must fail)

- [X] T030 [US5] Add tests in `workstation/emacs/packages/walkthrough-test.el` that `walkthrough-request-tour` calls `walkthrough-request-function` with `("/project-tour" t)` and, given AREA, `("/project-tour AREA" t)`, likewise `walkthrough-request-audit` with `/project-audit`; that `walkthrough-open-tour` opens `:tour.json`; that with no tour it asks (stub `y-or-n-p`) and requests one; that `walkthrough--read-installed` labels entries `branch <name>`, `tour`, `tour: <area>`, `audit`, `audit: <area>`

### Implementation

- [X] T031 [US5] In `workstation/emacs/packages/walkthrough.el` add `walkthrough-request-tour (&optional area)` and `walkthrough-request-audit (&optional area)` (prefix reads AREA with `read-directory-name` relative to the toplevel), `walkthrough-open-tour (&optional pick)` and `walkthrough-open-audit (&optional pick)` modelled on `walkthrough-open-current`, and the labels in `walkthrough--read-installed`; run the suite
- [X] T032 [P] [US5] In `workstation/emacs/config.org` add to `my/magit-review` a column `["Project" ("t" "Tour (C-u: pick)" walkthrough-open-tour) ("T" "Ask for a tour (C-u: area)" walkthrough-request-tour) ("a" "Audit (C-u: pick)" walkthrough-open-audit) ("A" "Ask for an audit (C-u: area)" walkthrough-request-audit)]`

**Checkpoint**: all stories complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T033 [P] Write `docs/adr/0011-tours-show-code-as-context-diffs.md` (0008 was already taken; renumbered) in the style of `docs/adr/0007-walkthrough-diffs-from-shas.md`: tours and audits store one commit and excerpt references, and the buffer rebuilds each excerpt as a synthetic context-only hunk from `git show`, so Magit's visiting, folding, highlighting and comments apply; consequences: needs the commit to exist, diagrams capped at 90 columns, comments labelled `code at <oid>`
- [X] T034 [P] In `GLOSSARY.md` add **Project tour**, **Project audit** and **Code excerpt** (definitions from spec.md), widen **Walkthrough** ("or, as a project tour or project audit, of the code at one commit") and **Finding** (audit findings are a defect or a smell)
- [X] T035 In `workstation/emacs/config.org` extend the walkthrough prose next to `open_walkthrough` with a paragraph on tours and audits: the two skills, `@ t`/`@ T`/`@ a`/`@ A`, excerpts behaving like hunks, diagrams as passages
- [X] T036 Run `nix fmt` and revert churn in unrelated files; `nix flake check`; `nix build .#test-walkthrough -L`; build the home configuration
- [X] T037 Walk through every step of `specs/009-project-tour-audit/quickstart.md` § Manual after activation and record results in the beads issues

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → stories. T013 only if T002(b) fails.
- US1 (Phase 3), US2 (Phase 4), US4 (Phase 6), US5 (Phase 7) each depend only
  on Phase 2. US3 (Phase 5) depends on US2 (it needs audit findings).
- All `walkthrough.el`/`walkthrough-test.el` tasks are sequential (same files),
  so stories run one after another in that file; the skill and `config.org`
  tasks marked [P] can run beside them.
- Phase 8 after the stories it documents.

## Parallel Examples

- US1: T016 (tour skill) and T017 (`config.org`) beside T014–T015.
- US2: T023 (audit skill) beside T019–T022.
- US3: T027 (`config.org`) beside T025–T026.
- US5: T032 (`config.org`) beside T030–T031.
- Phase 8: T033 and T034 together.

## Implementation Strategy

1. **MVP**: Phases 1–3: a tour opens in Emacs. Stop and run quickstart
   Manual 1–2.
2. Phases 4–5: audits with the hand-off.
3. Phases 6–7: comments wording and menu.
4. Phase 8.
