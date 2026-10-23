# Contract: Commands, Options, Agent Seam

## `walkthrough.el` (names no agent package)

| Symbol | Kind | Contract |
|---|---|---|
| `walkthrough-install DRAFT-FILE` | function | Validate, install, open. Returns `(ok . FILE)` or `(error . MESSAGES)`. Never raises for a bad draft. |
| `walkthrough-open FILE` | command | Open an installed walkthrough. Says so if its commits are gone (FR-019). |
| `walkthrough-open-current &optional PICK` | command | Current branch's walkthrough; with `PICK`, choose among the repository's. Offers `walkthrough-request` when there is none. |
| `walkthrough-request &optional BASE` | command | Sends `/walkthrough[ BASE]` through `walkthrough-request-function`. |
| `walkthrough-request-function` | defcustom, `(choice (const nil) function)` | Called as `(TEXT SUBMIT)`. Nil: `walkthrough-request` says no agent is configured. |
| `walkthrough-accept` / `-dismiss` / `-unmark` | commands | Act on the finding at point; write the state to the file at once (FR-012, FR-013). |
| `walkthrough-next-finding` / `-previous-finding` | commands | Across step boundaries. |
| `walkthrough-next-step` / `-previous-step` | commands | Land on the step heading. |
| `walkthrough-accepted-findings REPO &optional INCLUDE-SENT` | function | Hand-off items (data-model "Hand-off item"), oldest walkthrough first. |
| `walkthrough-mark-sent ITEMS` | function | Moves those findings to `sent` in their files; refreshes open buffers. |
| `walkthrough-directory` | function | `<git-common-dir>/walkthroughs/` of the current repository. |
| `walkthrough-diff-label` | function | `diff of <base-oid>..<head-oid>` for the current buffer's committed range, else nil. Used for `:where` by both findings and `my/magit-review--where` (research R6). |

Keys, research R8: `walkthrough-mode-map` has `n` `p` `N` `P`;
`walkthrough-finding-map` (the `keymap` property of a finding's text, or of
the overlay drawing it on its anchored line) has `a` `x` `u`.

## `config.org` adapters

- **MCP tool `open_walkthrough`** (`claude-code-ide-make-tool`). Argument
  `path` (string, required): the draft file. Calls `walkthrough-install` in
  the session's project directory. Returns `Opened <file>` or the validation
  messages verbatim, so the agent can fix the draft and call it again.
- **`magit_review_comments`**: also returns accepted findings, and sent ones
  with `include_sent`.
- **`my/magit-review-send` / `-paste`**: hand off pending review comments plus
  `walkthrough-accepted-findings`, then mark both sent. Error only when both are
  empty (spec US3 scenario 6).
- **`my/magit-review--where`**: uses `walkthrough-diff-label`, which reads
  `magit-buffer-diff-range-oids`, else `magit-buffer-diff-range` (research R6).
- **`@` transient**: new column "Walkthrough" with `w`
  (`walkthrough-open-current`) and `W` (`walkthrough-request`).
- `(use-package walkthrough :after magit :demand t :custom
  (walkthrough-request-function #'my/claude-code-ide-paste))`.

## Skill `walkthrough` (`workstation/agents/skills/walkthrough/SKILL.md`)

Invoked as `/walkthrough [BASE]`. Steps, in order:

1. Base: `BASE`, else the merge-base with the remote's default branch. If that
   is ambiguous, ask. Head: `HEAD`. Name any uncommitted changes left out
   (FR-002).
2. Run the built-in review through the Skill tool as `code-review` on
   `<base>...<head>`. If it cannot be invoked, stop and say so.
3. Read the changed files and their surroundings; group them into steps
   (FR-006). Split a file by `ranges` only when it holds unrelated changes.
4. Map each reported finding into the step owning its file (research R5).
5. Write the draft to `$TMPDIR/walkthrough-<branch>.json` and call
   `open_walkthrough`. On validation errors, fix the draft and call it again.
6. Report the number of steps and findings, and that the buffer is open.

The skill never edits code, commits or posts anything.
