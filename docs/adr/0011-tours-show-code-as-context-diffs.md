# ADR 0011: Tours and audits show code as context-only diffs from one commit

**Status:** Accepted (2026-11-06). Extends ADR 0007.

A project tour or project audit is a walkthrough about the code at one commit
rather than a change. It stores that commit and, per step, references to line
ranges of files (its excerpts); never a copy of the code. The buffer rebuilds
each excerpt from `git show <commit>:<file>` as a unified diff whose lines are
all context, and has Magit wash it. The commit is kept as both ends of the
walkthrough's range, so the buffer is a diff of `<commit>..<commit>`.

We picked this over a custom excerpt section because the result is made of
Magit's own file and hunk sections, with the file's real line numbers. `RET`
visits the file at that commit and line, `TAB` folds, `magit-diff-fontify-hunk`
highlights the language, review comments get file and line ranges through the
same code as on any hunk, and findings are placed under their lines by the
walkthrough's existing code. We rejected a diff against the empty tree: every
line would be an addition, and a whole file would be one hunk that a step
could not cut down to 40 lines.

## Consequences

- Like a walkthrough, a tour or audit breaks if its commit is
  garbage-collected; re-running it is the fix.
- A comment on an excerpt is labelled `code at <commit>`, not `diff of …`, so
  the agent reads it as being about code, not a change.
- Diagrams are fenced text blocks of a step's explanation, at most 90 columns
  wide. The buffer wraps long lines, and a wider diagram would be scrambled;
  validation rejects it so the agent redraws it.
- Validation checks lines against the commit (they exist, an excerpt spans at
  most 80 lines) instead of hunk coverage.
