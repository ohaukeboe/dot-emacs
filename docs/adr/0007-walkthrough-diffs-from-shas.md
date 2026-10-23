# ADR 0007: Walkthrough diffs are rebuilt from the base and head SHAs

**Status:** Accepted (2026-10-23).

A walkthrough stores only its base and head commits, and the Emacs buffer
rebuilds each step's diff with Magit from `git diff <base> <head>`. It does not
store a copy of the patch. trailofbits' `review-walkthrough`, which inspired it,
stores the patch verbatim and renders HTML. We picked the other route because
the buffer derives from `magit-diff-mode`. The diff sections are then Magit's
own, so review comments, their decorations, visiting files and folding work
unchanged. Commits are immutable, so the rebuilt diff matches what the agent
reviewed.

## Consequences

- Steps can split a file by hunk (new-side line ranges) instead of owning whole
  files. A copied patch would have to be cut and re-checked.
- A walkthrough breaks if its commits are garbage-collected, for example after
  rebasing the branch and pruning. Re-running the walkthrough is the fix.
- Hunk boundaries depend on the diff context. Widening the context in the
  buffer can merge hunks, so a merged hunk then shows in more than one step.
