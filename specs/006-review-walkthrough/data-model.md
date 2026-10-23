# Data Model: Review Walkthroughs

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

The file format is in [contracts/walkthrough-file.md](./contracts/walkthrough-file.md).
This page describes the entities, their rules and their states.

## Walkthrough

| Field | Meaning | Rule |
|---|---|---|
| `version` | Format version | `1` |
| `title` | One-line summary of the change | non-empty |
| `repo` | Toplevel of the repository it was made in | set by Emacs at install |
| `branch` | Branch it belongs to | non-empty; names the installed file |
| `base`, `head` | Full commit ids | both resolve to commits; `base` is an ancestor of `head` |
| `steps` | Steps in reading order | at least one; covers every hunk once (FR-005) |

**Identity**: `(git-common-dir, branch)`. Installing a walkthrough for a branch
replaces the earlier one; marks are not carried over.

**Derived, never stored**:

- *Moved*: the branch tip is no longer `head`.
- *Gone*: `base` or `head` no longer exists.

## Step

| Field | Meaning | Rule |
|---|---|---|
| `title` | The concept | non-empty |
| `explanation` | Markdown, usually 50–150 words | non-empty |
| `files` | What it owns | non-empty; each entry is a path (whole file) or `{file, ranges}` |
| `findings` | Findings assigned to it | may be empty |

A `ranges` entry is a list of `[start, end]` pairs on the new side, with
`1 <= start <= end`. The same path may appear in several steps only as range
entries whose hunks do not overlap (coverage rule, research R4).

## Finding

| Field | Meaning | Rule |
|---|---|---|
| `id` | Stable id | assigned by Emacs at install: `s<step>-f<n>` |
| `severity` | `high`, `medium` or `low` | required |
| `title` | One line | required |
| `body` | Markdown explanation | required |
| `failure_scenario` | Inputs or state, then the wrong result | optional |
| `verdict`, `category` | As reported by the review | optional, shown as text |
| `anchor` | `{file, line, end_line?, side?}`; `side` is `new` (default) or `old` | optional; `file` must be owned by this step |
| `state` | See below | absent means unmarked |
| *other keys* | Unknown fields from the review | kept, shown as text |

**Placement**: anchored and shown in a hunk of its step: below `end_line` (or
`line`). Anchored but no hunk of the step shows that line: at the top of the
step, marked "not placed". No anchor: below the step's explanation.

### Finding states

```text
            a                 hand-off
unmarked ─────▶ accepted ──────────────▶ sent
   ▲  │  ▲         │
   │  │x │u        │x
   │  ▼  │         ▼
   └─ dismissed ◀──┘
      (u back to unmarked)
```

- `a` on unmarked or dismissed → `accepted`; `x` on unmarked or accepted →
  `dismissed`; `u` → unmarked.
- The hand-off moves `accepted` → `sent`. A `sent` finding cannot be marked
  again; it is shown dimmed, as sent review comments are.
- Only `accepted` findings travel in a hand-off (FR-014).

## Review comment (existing, changed)

Unchanged except `:where` (research R6): for a committed range it is
`diff of <base-oid>..<head-oid>`, so a comment made in a walkthrough and one made in
an ordinary diff of the same commits are the same comment.

## Hand-off item

What `walkthrough-accepted-findings` returns per finding, shaped like a review
comment so the existing formatter prints both:

`:repo :file :new :old :where :patch :text` plus `:kind finding`, `:severity`,
`:title`, `:id` and `:walkthrough` (the file it came from).
