# Research: Project Tours and Project Audits

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Each entry: decision, rationale, alternatives considered. Code references are
to `workstation/emacs/packages/walkthrough.el` (WT) and
`workstation/emacs/config.org` (CO) as of `9885e73`.

## R1. Extend `walkthrough.el` instead of writing a sibling package

**Decision**: A tour and an audit are walkthroughs of a new `kind`
(`"tour"`, `"audit"`; absent means `"changes"`, today's walkthrough). They
use the same file format version, directory, install path, MCP tool, buffer
mode, marks, replies, step comments and hand-off.

**Rationale**: The spec asks for "the same Emacs integration". Almost all of
WT is already kind-neutral: marks and replies (`walkthrough--mark`,
`walkthrough-reply`), navigation (`walkthrough-next` …), step and passage
comments (`walkthrough-comment-target`, `walkthrough-redraw-comments`), the
hand-off (`walkthrough-accepted-findings`, `walkthrough-mark-sent`) and the
finding renderer. Only three things are diff-specific: validation (hunk
coverage), what a step's body shows (a diff of base..head), and the patch a
finding is handed off with. Those three get a kind branch; nothing else is
duplicated. Audit findings then join the hand-off for free, because
`walkthrough-accepted-findings` reads every installed file (US3 scenario 2).

**Alternatives considered**:
- *A `project-tour.el` package beside WT*: duplicates marks, replies,
  comments and hand-off, or forces WT to export its internals. Rejected:
  two copies of one behaviour (Constitution IV).
- *HTML report*: the user explicitly wants the Emacs view.

## R2. Code excerpts are synthetic context-only diffs washed by Magit

**Decision**: For a tour or audit, a step's body is built from the text of
its excerpts at the recorded commit, written as a unified diff whose lines are
all context:

```text
diff --git lib/x.el lib/x.el
--- lib/x.el
+++ lib/x.el
@@ -120,8 +120,8 @@
 (defun x--parse (s)
 …
```

It is inserted and washed with `magit-diff-wash-diffs`, exactly like the
ranged path of `walkthrough--insert-step-diff`. The buffer's
`magit-buffer-diff-range` is `<commit>..<commit>`. The text comes from one
`git show <commit>:<file>` per file, not from the work tree.

**Rationale**: The result is real Magit `file` and `hunk` sections, so:
- `TAB` folds and `RET` visits (Magit visits the range end, `<commit>`,
  at the line; with `magit-diff-visit-prefer-worktree` the work-tree file);
- `@ c` on a hunk or region records `:file`, `:new`/`:old` line ranges through
  the existing `my/magit-review--range` (CO), because hunk ranges are the
  file's real line numbers (FR-009, US4 scenario 1);
- `walkthrough--draw-anchored` places findings under their lines unchanged;
- `magit-diff-fontify-hunk` (CO, already `t`) gives language highlighting
  (FR-006).

**Verified** (`walkthrough-test-code-render`): `RET` on a context line visits
`<commit>:<file>` at that line, so no fallback is needed. The risk was that `RET` on a
context line of a synthetic hunk in a `C..C` range visits `C:<file>` at that
line. If Magit refuses, bind `RET` on excerpt hunks to a small visit command
using `magit-find-file-noselect` and the hunk's `to-range`; nothing else
changes.

**Alternatives considered**:
- *A custom excerpt section*: re-implements visiting, folding, line ranges
  for comments, and finding placement. Rejected: the point of R1.
- *Diff against the empty tree* (`4b825dc…..<commit>`): every line is an
  addition in green, whole files are one hunk so a step cannot show 40 lines
  of a 2000-line file, and the hunk-coverage rule is meaningless. Rejected.

## R3. Diagrams are fenced text blocks in the explanation, at most 90 columns

**Decision**: A diagram is a fenced block (```` ```text ````) inside a step's
explanation. Validation rejects any line inside a fenced block wider than
90 columns (`string-width`), naming the step and line.

**Rationale**: The explanation is already rendered with `markdown-mode` and
already supports passage comments, so commenting on a diagram (US4 scenario 2)
needs no new code: select its lines, `@ c`. The buffer runs
`visual-line-mode`, which would wrap a wide diagram into nonsense; a width
limit is the cheapest guarantee that it does not (spec edge case), and 90 is
the width the user reads at (`olivetti-body-width`). The limit is enforced
where the agent gets the error back and can redraw.

**Alternatives considered**:
- *A `diagrams` field rendered with truncation*: Emacs has no per-region
  "don't wrap" under `visual-line-mode`; it would need overlays with
  horizontal scrolling and a new comment target. Rejected.
- *Mermaid/PlantUML rendered to images*: out of scope (spec Assumptions),
  needs an external renderer.

## R4. File format: `kind`, `commit`, `area`, `skipped`; excerpts reuse `files`

**Decision**: For `kind` `tour` or `audit`, the draft carries `commit`
instead of `base`/`head` and no `branch`; optional `area` (a path, absent
for the whole project) and `skipped` (strings naming what was not covered).
A step's `files` is optional, and each entry must be `{file, ranges}`: these
are its excerpts. At install Emacs sets `base` and `head` both to the
resolved `commit`, so every function that reads `base`/`head`
(`walkthrough--check-commits`, `walkthrough-open`, hand-off) works unchanged.
Audit findings gain `type` (`defect` | `smell`). Full format:
[contracts/walkthrough-file.md](./contracts/walkthrough-file.md).

**Rationale**: Reusing `files`/`ranges` keeps one parser
(`walkthrough--entry`). `type` rather than `kind` on findings, because hand-off
items already use `:kind 'finding`. Version stays 1: an absent `kind` reads as
today's walkthrough, so installed files keep working.

**Alternatives considered**: a separate `excerpts` field (second parser, same
shape); `version: 2` (breaks nothing it would fix).

## R5. Validation for tours and audits

**Decision**: Instead of hunk coverage (`walkthrough--validate-coverage`),
a tour or audit is checked for:

- `commit` resolves to a commit;
- every excerpt and anchor file exists at `commit` and is text;
- every range and anchor line lies within the file's line count at `commit`
  (FR-005);
- an excerpt range spans at most 80 lines (hard cap; the skill aims for 40,
  FR-024);
- fenced-block lines at most 90 columns (R3);
- tour: no step has findings (FR-025); step 1's explanation has a fenced
  block (FR-020, SC-003);
- audit: each finding has `type`; a `defect` has `failure_scenario` and a
  `verdict` of `CONFIRMED` or `PLAUSIBLE` (FR-031, FR-036); an anchor's file
  need not be owned by the step (R8).

Errors keep today's shape, `<where>: <problem>`, all collected at once, and a
bad draft replaces nothing.

**Rationale**: Each rule is one the agent can fix from the message, and each
maps to a requirement that would otherwise rely on the skill's prose.

## R6. Storage and identity

**Decision**: Same directory, `<git-common-dir>/walkthroughs/`. File names
start with `:`, which `git check-ref-format` forbids in branch names, so they
never collide with a branch's walkthrough: `:tour.json`, `:audit.json`, and
for an area `:tour:<area>.json`, `/` written `%2F`. Re-running for the same
kind and area replaces the file (FR-011).

**Rationale**: `walkthrough--installed` lists the directory, so audits are
found by the hand-off and by `magit_review_comments` with no change. The
picker labels entries by kind and area instead of decoding a branch name.

## R7. "Moved" for a tour or audit

**Decision**: The intro says the repository has moved when
`git rev-parse HEAD` differs from `commit`. "Gone" is today's check on
`base`/`head` (both the commit).

## R8. Audit findings always show their code

**Decision**: An audit step's excerpts are its `files` ranges plus, for each
anchored finding, its anchored lines widened by `walkthrough-excerpt-context`
(3) lines; overlapping or adjacent ranges of a file merge into one hunk.
The hand-off item's `:patch` is the same synthetic hunk for the anchor alone.

**Rationale**: FR-034 (judge without leaving the view) and US3 (excerpt in the
prompt), with one helper building the hunk text for both.

## R9. Comment labels

**Decision**: `walkthrough-diff-label` returns `code at <commit>` when the
buffer's range has equal ends, else today's `diff of <base>..<head>`. The
hand-off wording in `my/magit-review--format` (CO) says "the diff or commit
it refers to", and the direct-comment intro says "the walkthrough" without
"of this diff".

**Rationale**: A comment on a tour's excerpt names the commit whose code it
is about; labelling it as a diff of `C..C` would mislead the agent. Hunk
comments are drawn by matching `:where`, so the label must come from the same
function in both places, as it already does.

## R10. Two skills, one MCP tool

**Decision**: Skills `project-tour` and `project-audit` in
`workstation/agents/skills/`, both `disable-model-invocation: true` like
`walkthrough`. Both write a draft to `$TMPDIR` and call the existing
`open_walkthrough` tool, whose description is widened to name tours and
audits. Arguments: an optional area path.

- **Tour**: read the project's docs and entry points; use the
  `codebase-memory` graph (`get_architecture`, `trace_path`) when present;
  for a large tree, delegate area summaries to `Explore` subagents. Order:
  overview with diagram, foundations, parts, cross-cutting flows. 6–15 steps.
- **Audit**: list `git ls-files` at the commit, drop generated, vendored and
  lock files, split into at most 6 areas, review each in a parallel subagent
  that returns findings as JSON, then verify every defect against the code
  in the main session and set `verdict`. Merge a smell found in many places
  into one finding. Record what was skipped.

**Rationale**: The built-in `code-review` reviews a diff, PR or path target
and reports through `ReportFindings`; whether a path target reviews whole
files rather than their diff is undocumented, so the audit cannot rest on it
the way `walkthrough` does. Subagents per area keep the main context small
and give each area a fresh read.

**Alternatives considered**: `ponytail:ponytail-audit` (a report, not
findings with anchors; ranks what to delete rather than defects); the
`claude-security` scan (security only, out of scope).

## R11. Starting and reopening from the review menu

**Decision**: `walkthrough-request` gains a sibling per kind:
`walkthrough-request-tour` and `walkthrough-request-audit` send
`/project-tour[ AREA]` and `/project-audit[ AREA]` through
`walkthrough-request-function`. `walkthrough-open-tour` and
`walkthrough-open-audit` open the whole-project one, or with a prefix pick
among that kind's files. The `@` transient gets a "Project" column: `t` / `T`
(open / ask for a tour), `a` / `A` (open / ask for an audit).

**Rationale**: Same shape as `w` / `W`; no new configuration seam.
