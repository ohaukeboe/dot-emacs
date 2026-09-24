# Phase 1 Data Model: Beads Issue Relations in Magit

**Date**: 2026-09-23 · **Feature**: `specs/002-beads-issue-relations/`

Nothing here is stored. Every structure below is built from `bd` output during a
refresh and discarded on the next one; the tracker remains the only durable
record. Field names are the ones `bd --json` actually emits, verified in R1–R3
of [research.md](./research.md).

## Entities

### Issue (existing, unchanged)

Already consumed by `beads-insert-issues`. Fields this feature adds a use for:

| Field | Type | From | Use |
|-------|------|------|-----|
| `id` | string | `bd list`, `bd ready` | identity; the section value |
| `title` | string | both | mark text |
| `status` | string | both | distinguishes a closed relation target |
| `priority` | integer or absent | both | existing display |
| `parent` | string or absent | both | the parent relation (FR-001) |
| `dependency_count` | integer | both | gates the `bd blocked` call (R4) |
| `dependent_count` | integer | both | the dependents mark (FR-004) |

`dependencies` is also present on `bd list` output but carries only
`issue_id` / `depends_on_id` / `type`, with no title or status. It is **not**
used: blocker identity comes from `bd blocked` instead (R2).

### Relation target

One issue named by a relation, resolved far enough to be displayed and jumped
to. Built from `bd list --id=… --all --json`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | always present, even when resolution failed |
| `title` | string or nil | nil when the id did not resolve |
| `status` | string or nil | nil when the id did not resolve |
| `resolved` | boolean | false ⇒ render as unresolved (FR-015) |

**Validation**: an id in `blocked_by` or in `parent` that `bd list --id=…` does
not return is not an error. It yields an unresolved target, which marks as
`<id> (unknown)` and, on navigation, reports that the issue could not be read
and changes nothing else.

### Relation set

What is known about one listed issue's relations. One per listed issue, held in
the buffer-local table described below.

| Field | Type | Source | Requirement |
|-------|------|--------|-------------|
| `parent` | relation target or nil | `parent` field, resolved via R3 | FR-001 |
| `blockers` | list of relation targets | `bd blocked` → `blocked_by`, resolved via R3 | FR-002, FR-003 |
| `dependent-count` | integer | `dependent_count` | FR-004 |

**Invariants**:

- A relation set with a nil `parent`, an empty `blockers` and a zero
  `dependent-count` is never stored, and its issue renders exactly as today
  (FR-005).
- `blockers` never contains a closed issue: the list comes from `bd blocked`,
  which excludes them (R2). Emacs does not filter by status itself.
- An issue in the "Ready" group never has a non-empty `blockers`, because ready
  means unblocked. This is a consequence, not a check.
- `dependent-count` counts both children and dependents, because bd counts both
  as dependents of the issue.

### Relation table

Buffer-local, keyed by issue id, holding one relation set per listed issue that
has relations. Rebuilt from scratch by `beads-insert-issues` on every refresh;
never merged with the previous one, so an issue whose last blocker closed loses
its mark on the next refresh rather than keeping a stale one.

**Why a table and not the section object**: the issue id must remain the
`magit-section` value. `beads--issue-at-point`, `beads--issues-at-point`,
`beads--targets` and every command built on them read `(oref section value)` as
a string id; putting a record there would break all of them (R8).

**Lookup outside the status buffer**: a `beads-show-mode` buffer has no table.
The relation set for the issue it displays is fetched on demand with
`bd show <id> --json`, whose `parent` and fat `dependencies` give everything in
one call — acceptable at 0.21 s for an interactive command, unacceptable on a
refresh (R2).

### Dependents listing (lazily fetched)

Not part of the relation set. Fetched only when the developer asks to navigate
to a dependent, with `bd show <id> --json --include-dependents`, whose
`dependents` array carries `id`, `title`, `status` and `dependency_type` per
entry. Kept off the refresh path deliberately (R4).

### Jump history

A stack of return locations, global to the Emacs session rather than to any one
buffer, because a jump can cross from the status buffer into a `bd show` buffer.

| Field | Type | Notes |
|-------|------|-------|
| `buffer` | buffer | may be dead by the time it is popped |
| `marker` | marker | survives a Magit refresh, unlike a raw position |

**Transitions**:

- *Before* a successful jump, the current location is pushed. A jump that fails
  its precondition (no such relation, unresolved target) pushes nothing, so
  FR-012's "nothing changes" holds for the history too.
- `beads-go-back` pops entries until one names a live buffer with a live marker,
  restores it, and stops. An empty stack reports that there is nowhere to go
  back to (FR-013).
- Not persisted; a new Emacs session starts with an empty stack.

## Relationship diagram

```text
                    bd list --status=in_progress ──┐
                    bd ready ──────────────────────┤
                                                   ├─→ listed Issues
  (only if some listed issue has dependencies)     │      │
                    bd blocked ────────────────────┘      │ parent, blocked_by
                                                          ↓
  (only if there are ids to resolve)                   bare ids
                    bd list --id=… --all ─────────────────┤
                                                          ↓
                                                  Relation targets
                                                          ↓
                                       Relation set ──→ Relation table
                                                          ↓
                            heading marks (glyphs) + body lines (id, title)
                                                          ↓
                                    jump ──→ Jump history ──→ beads-go-back
```

## What this feature does not model

- Transitive ancestry or transitive blockers. Only immediate relations exist in
  the model; depth is walked one jump at a time (spec Assumptions).
- Creating, removing or editing a relation. Out of scope for this version.
- Any change to which issues the section lists (FR-019).
