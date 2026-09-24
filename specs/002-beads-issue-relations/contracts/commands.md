# Contract: what this feature exposes to the user

**Feature**: `specs/002-beads-issue-relations/` · **Date**: 2026-09-23

The public surface of `beads.el`: interactive commands, the transient, faces and
customization. Everything else in the file is internal (`beads--` prefix) and
carries no promise.

## Commands

All four act on the issue at point in a Magit buffer, or on the issue a
`beads-show-mode` buffer displays (FR-011). All four are autoloaded through the
package as the existing commands are.

### `beads-goto-parent`

Move to the parent of the issue at point.

- No parent → message naming the issue and that it has no parent; point,
  buffer and window configuration unchanged (FR-012).
- Parent unresolved → message that the parent could not be read; nothing else
  changes (FR-015).
- Otherwise → push the current location, then land (see *Landing* below).

### `beads-goto-blocker`

Move to one of the issues blocking the issue at point.

- No blockers → message; nothing changes.
- Exactly one blocker → go there without a prompt.
- Several → `completing-read` over them, each candidate annotated with status
  and title, as `beads--read-issue` already annotates. Aborting the prompt
  changes nothing and pushes no history.

### `beads-goto-dependent`

Move to one of the issues that depend on, or are children of, the issue at
point. Fetches the dependents on demand (see the CLI contract).

- Not gated on the mark's count: the listing undercounts (children are not in
  it), so the command asks `bd show --include-dependents`, which does not.
- Nothing returned → message; nothing changes.
- Exactly one → go there without a prompt.
- Several → `completing-read`, annotated as above.

### `beads-go-back`

Return to the location the previous relation jump started from, repeatedly, in
reverse order (FR-013).

- Empty history → message that there is nowhere to go back to.
- Entries whose buffer or marker has died are skipped, not reported.

## Landing behaviour (FR-009, FR-010)

Shared by the three `beads-goto-*` commands:

1. If the current buffer holds a `beads-issue-section` whose value is the target
   id, reveal that section (`magit-section-show`) and move point to its start.
2. Otherwise open the target with `beads-show`, which is the existing full view.
3. If the target has vanished between display and navigation, report it and
   leave the buffer as it was (edge case "Refresh during navigation").

## Transient additions

A `Relations` column in the existing `beads-dispatch` prefix, reachable as
before with `#`:

| Key | Command | Shown as unavailable when |
|-----|---------|---------------------------|
| `p` | `beads-goto-parent` | the issue has no parent |
| `b` | `beads-goto-blocker` | the issue has no blockers |
| `d` | `beads-goto-dependent` | the listing's `dependent_count` is zero — grey on a parent whose only dependents are its children, though the command still works there |
| `B` | `beads-go-back` | the history is empty |

Unavailability uses `:inapt-if-not`, which greys the entry out and keeps it in
place; `:if`, which removes it, would make the menu change shape per issue
(R7). No key is bound outside the transient: `p`, `b` and `n` are live Magit
keys and shadowing them inside issue sections would cost more than it gives
(R6).

## Display

### Heading marks

Appended after the priority column of an issue's heading line, before the title,
and counted in the truncation width so long titles still fit:

| Mark | Meaning | Face |
|------|---------|------|
| `↑` | has a parent | `beads-relation` |
| `⊘N` | blocked by N issues | `beads-blocked` |
| `↳N` | N issues depend on this one, as the listing counts them (children excluded — see the CLI contract) | `beads-relation` |

An issue with no relations gets no mark and no separator — its heading is
byte-identical to today's (FR-005).

### Body lines

Inserted in the issue's body, above the description, in the shape of the
existing `Assignee:` line:

```
    Parent:     dot-emacs-lyy  Epic one
    Blocked by: dot-emacs-k6c  (in_progress)  Cap runaway agent-spawned processes
                dot-emacs-nh4  (open)         Another blocker
```

Present only for the relations the issue actually has. Beyond
`beads-relation-limit` (below) the list is summarised as `…and N more` in the
shape the ready listing already uses (FR-016).

## Faces

| Face | Default | Purpose |
|------|---------|---------|
| `beads-relation` | inherits `magit-dimmed` | parent and dependent marks |
| `beads-blocked` | inherits `warning` | the blocked mark and its body line |

## Customization

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `beads-relation-limit` | `natnum` | 5 | blockers listed in a body before the rest are summarised; the heading mark always reports the full count (FR-016) |

`beads-ready-limit` and every existing option keep their current meaning.

## Compatibility promises

- The `magit-section` value of a `beads-issue-section` stays the issue id
  string. Anything reading it — `beads--issue-at-point`,
  `beads--issues-at-point`, `beads--targets`, the region commands — keeps
  working (R8).
- `beads-insert-issues` keeps its signature and its place in
  `magit-status-sections-hook`.
- The set of issues listed does not change (FR-019).
