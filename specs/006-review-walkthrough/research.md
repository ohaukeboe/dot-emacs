# Research: Review Walkthroughs

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Each entry records one decision the plan depends on, why it was made, and what
was rejected. Magit facts were read from the loaded `magit-20261005.508`
(`magit-diff.el`, `magit-mode.el`, `magit-git.el`) and `magit-section-20260926.1436`.
Facts about trailofbits' skill come from `plugins/review-walkthrough/` in
`github.com/trailofbits/skills`. Facts about the built-in review come from
`code.claude.com/docs/en/code-review-local.md` and the `ReportFindings` tool
schema visible to the agent.

## R1 — Where the code lives

**Decision**: a new self-contained package `workstation/emacs/packages/walkthrough.el`
(prefix `walkthrough-`) with its ERT suite `walkthrough-test.el`, run by
`nix build .#test-walkthrough -L` (`tests/walkthrough.nix`, same shape as
`tests/beads.nix`). `walkthrough.el` names neither `claude-code-ide` nor the
`my/magit-review-*` code. `config.org` holds the adapters: the MCP tool, the
hand-off extension, the transient keys and the `use-package` form.

**Rationale**: the same seam as `beads.el` (specs/003 R1). The package gets a
cheap test build (Emacs + Magit + markdown-mode), and the private
`claude-code-ide` coupling stays in the one section of `config.org` that already
says it leans on internals.

**Alternatives considered**:

- *Inline in `config.org` next to the review comments.* Rejected: about 500
  lines with a validator and a hunk parser need tests, and `config.org` code has
  none.
- *A `magit-` prefix.* Rejected: reserved for Magit itself by convention.

## R2 — The buffer: a mode derived from `magit-diff-mode`

**Decision**: `walkthrough-mode` derives from `magit-diff-mode` and is set up
with `magit-setup-buffer`, binding `magit-buffer-diff-range` to
`"<base>..<head>"`, `magit-buffer-diff-type` to `committed`,
`magit-buffer-diff-typearg` and `magit-buffer-diff-files` to nil,
`magit-buffer-diff-args` to the user's diff args, and a buffer-local
`walkthrough--data`. `magit-buffer-revision` stays nil. Magit refreshes it by
calling `walkthrough-refresh-buffer` (the name is derived from the mode name).

That function sets the header line and `magit-buffer-diff-range-oids`, then
inserts `(magit-insert-section (diffbuf) ...)` containing one `walkthrough-step`
section per step (value: the step index). Each step holds a heading, its
explanation, its findings without an anchor, and one `walkthrough-diff`
section that wraps the washed diff.

**Rationale**:

- Every mode test that matters (`magit-diff-type`, the hunk helpers, the
  review-comment decoration's `derived-mode-p` check) accepts a derived mode.
- `magit-diff--dwim` errors on a nil `magit-buffer-diff-type`, and treats a set
  `magit-buffer-revision` as a single commit. So the type must be `committed`
  and the revision must be nil.
- RET visits blob `<head>` (or `<base>` on a removed line) via
  `magit-split-range`. `C-<return>` (`magit-diff-visit-worktree-file`) visits the
  live file with the line corrected by `magit-diff-visit--offset`. Both work
  unchanged.
- `magit-get-mode-buffer` compares modes with `eq`, so walkthrough buffers never
  replace an ordinary diff buffer. A `magit-buffer-value` method on
  `walkthrough-mode` returns the walkthrough file, so two walkthroughs of the
  same range stay separate buffers.

**Pitfalls carried into the design**:

- `magit--git-wash` calls `magit-cancel-section` on empty output, which deletes
  the innermost enclosing section. That is why the diff sits in its own
  `walkthrough-diff` child: an empty diff must not delete the step's heading.
- Section identity is the `(type . value)` chain, so step values must be unique
  (the index) for visibility and point to be restored after a refresh. The same
  file appearing in two steps is fine, because the parent idents differ.
- `magit-xref-modes` is checked with `memq`, so add `walkthrough-mode` to it.
  `magit-section-cycle-diffs` only sees top-level file sections and will not
  cycle nested ones. Accepted; `TAB` on each file still works.
- Never call `magit-refresh` from inside the refresh function.

**Alternatives considered**: overlays on an ordinary `magit-diff` buffer. Rejected
in the design session: file order would lose the step order.

## R3 — Inserting one step's diff, including partial files

**Decision**: per step, insert the raw output of
`git diff -p --no-prefix <diff-args> <base> <head> -- <files>` with
`magit-git-insert`. For each file owned by line ranges, delete the
`@@ -a,b +c,d @@` blocks whose new-side span does not overlap a range, and
delete files left with no hunks. Then narrow to the inserted text and call
`magit-diff-wash-diffs` with the same argument list, as `magit--git-wash` does
internally. When no file owns line ranges, use the plain
`(magit-git-wash #'magit-diff-wash-diffs "diff" ...)` call.

**Rationale**: filtering text before washing keeps Magit's section tree correct
by construction. Deleting hunk sections after washing would mean fixing markers
and the parent's `children` list by hand, and could leave empty file sections
behind. Keep `--no-prefix`, because the washer expects it.

**Hunk span**: a hunk `+c,d` covers new-side lines `c` to `c+d-1`. A hunk with
`d = 0` (a pure deletion) covers the single position `c`, so a range around the
deletion point owns it. A hunk overlaps a range `[s, e]` when `c <= e` and
`max(c, c+d-1) >= s`.

## R4 — Validation lives in Emacs, the only writer is Emacs

**Decision**: the agent writes a *draft* to `$TMPDIR` and calls the MCP tool
`open_walkthrough` with its path. The tool:

1. parses and validates the draft (schema, commits exist, hunk coverage);
2. on failure, returns the errors as the tool result and changes nothing;
3. on success, assigns finding ids and installs the file atomically at
   `<git-common-dir>/walkthroughs/<branch>.json`, then opens the buffer.

Marks are written by Emacs too: re-read the file, update the one finding by
id, write to a temporary file in the same directory, then rename over the old
one.

**Rationale**:

- One validator, in the tested package. A second validator in the skill would
  drift from the first (Principle IV).
- In an agent worktree, `git-common-dir` is the main checkout's `.git`, outside
  the sandbox's writable directories. Emacs is not sandboxed, so it writes
  there; the agent writes only to `$TMPDIR`.
- FR-005's "MUST NOT replace an existing one" falls out: install happens only
  after validation succeeds.
- With a single writer that re-reads before every write, "last write wins for
  that finding, others kept" holds without locking.

**Coverage rule** (FR-005): parse `git diff -U3 --no-prefix <base> <head>` into
files and hunks. A step's whole-file entry owns every hunk of that file. A
line-range entry owns the hunks that overlap a range (R3). Every hunk must have
exactly one owner. A file with no hunks (a binary file, a pure rename or a mode
change) must be owned by exactly one whole-file entry. The file's path is the
new path, or the old one for a deleted file. Errors name the file and the
`@@` header.

**Alternatives considered**:

- *The skill validates with a script.* Rejected: two implementations of one rule.
- *The agent writes the final file.* Rejected: blocked in worktrees by the
  sandbox, and an invalid file could replace a valid one.

## R5 — Getting findings from the built-in review

**Decision**: the `walkthrough` skill first runs the built-in review through the
Skill tool as `code-review`, with `<base>...<head>` (see the outcome below for
why not `review`). It
then transcribes the findings it reported into the draft, mapping them by
meaning:

| `ReportFindings` field | Walkthrough field |
|---|---|
| `short_summary` | `title` |
| `summary` | `body` |
| `failure_scenario` | `failure_scenario` |
| `verdict` | `verdict` (optional) |
| `category` | `category` (optional) |
| `file`, `line` | `anchor.file`, `anchor.line` (new side) |
| rank order | `severity`, chosen by the skill |

**Rationale**:

- A personal skill named `code-review` shadows the built-in; the `/review`
  alias cannot be shadowed.
- `ReportFindings` renders in the UI and returns nothing to the model as data.
  But the model wrote the call's arguments, so it can transcribe them.
- The tool has no severity field; its findings are ranked most severe first. So
  the skill sets severity from the rank and the verdict: a confirmed
  correctness finding near the top is `high`.
- Field names are undocumented, so the skill describes them by meaning, and the
  schema accepts unknown fields on a finding and shows them as text.

**Risk**: if the Skill tool cannot invoke the built-in review from inside
another skill, the skill stops and says so rather than inventing findings. The
quickstart checks this first.

**Outcome of the first live run (2026-10-23)**: `Skill(review)` failed with
`Unknown skill: review`. The `/review` alias exists for typing, not for the
Skill tool. Other built-in skills (`simplify`, `security-review`) are callable,
so the built-in review was missing only because the personal `code-review`
shadowed it. Decision: install mattpocock's two-axis review as
`code-review-axes` (`mattpocockRenames` in `workstation/agents/skills.nix`,
which also rewrites the `implement` and `implement-spec` calls to it) and have
the walkthrough skill call `code-review`.

**Alternatives considered**: copying the bug-hunt-and-verify process into our
skill. Rejected in the design session: it would drift from upstream.

## R6 — Comment identity across buffers (and an existing bug)

**Finding**: `magit-buffer-range` was renamed to `magit-buffer-diff-range` with no
obsolete alias. `my/magit-review--where` (config.org) reads
`(bound-and-true-p magit-buffer-range)`, which is now always nil. So every review
comment in a range diff is labelled plain `"diff"`, and comments on different
ranges are mixed together.

**Decision**: `my/magit-review--where` reads `magit-buffer-diff-range-oids` when
it is set, else `magit-buffer-diff-range`, and labels the comment
`diff of <base-oid>..<head-oid>`. A comment made in a walkthrough over `A..B` and
one made in `magit-diff main..HEAD` then match whenever they resolve to the same
commits, as User Story 4 scenario 2 requires.

**Rationale**: comparing resolved commits instead of the spelling of the range
is the only way two buffers that name the same range differently can agree.
Comments live in memory only, so there is nothing to migrate.

## R7 — Markdown text in the buffer

**Decision**: render explanations and finding bodies by inserting the text into a
temporary `markdown-mode` buffer with `markdown-hide-markup` on, running
`font-lock-ensure`, and copying the propertized string. The walkthrough buffer
adds `markdown-markup` to its `buffer-invisibility-spec`. Without
`markdown-mode`, the text is inserted plain and filled.

**Rationale**: `markdown-mode` is already configured (`config.org`, with
`markdown-hide-markup t`). Magit buffers do not run font-lock, so `face`
properties copied in display as they are.

## R8 — Keys in the walkthrough buffer

**Decision**:

- `a` accept, `x` dismiss, `u` unmark: bound in `walkthrough-finding-map`,
  which is the `keymap` property of a finding's text, so they act only with
  point on a finding. Elsewhere `a` (apply), `x` (reset) and `u` (unstage) keep
  their Magit meaning.
- A finding drawn inside a hunk cannot be a section or buffer text: extra lines
  in a hunk would break `magit-diff-hunk-line` and applying the hunk. So it is
  an overlay `after-string` below its line, as review comments are, and the
  overlay spans the anchored line and carries the same keymap. On that one
  line, `a`/`x`/`u` mark the finding instead of acting on the hunk.
- `n`/`p` next or previous finding, `N`/`P` next or previous step: bound in
  `walkthrough-mode-map`.

**Rationale**: the user chose these keys. Section maps keep the mark keys from
shadowing Magit's hunk commands on diff lines. `n`/`p` shadow
`magit-section-forward`/`backward` in this one mode only, which the user
accepted. `M-n`/`M-p` still move between sibling sections. `P` (push) has no
use in a fixed range.

## R9 — Hand-off

**Decision**: `walkthrough.el` exposes `walkthrough-accepted-findings REPO`
(the accepted and unsent findings of every walkthrough in the repository, as
plists shaped like review comments: `:file :new :old :where :patch :text`, plus
`:severity :title`), and `walkthrough-mark-sent FINDINGS`. In `config.org`,
`my/magit-review-send` collects pending comments plus accepted findings,
`my/magit-review--format` prints a finding's severity and title as its heading
and its body plus failure scenario as text, and `my/magit-review--hand-off`
marks both sent. The `magit_review_comments` MCP tool includes accepted findings
(and sent ones with `include_sent`).

A finding's `:patch` is the hunk it is anchored to, cut from the raw diff when
the finding is marked accepted. Its `:where` is the same label as R6, so a
review comment and a finding on the same hunk print alike.

**Rationale**: one hand-off, one prompt (FR-014). The package returns data; the
config decides how it is sent.

## R10 — Starting and reopening from `@`

**Decision**: the `@` transient gains a "Walkthrough" column:

- `w` opens the current branch's walkthrough; with a prefix argument it picks
  any walkthrough of the repository.
- `W` asks the agent session to run the skill: it sends `/walkthrough` (plus
  the base ref, when given with a prefix argument) through
  `walkthrough-request-function`, which `config.org` sets to
  `my/claude-code-ide-paste`.

**Rationale**: the same function-valued seam as `beads-agent-send-function`.
