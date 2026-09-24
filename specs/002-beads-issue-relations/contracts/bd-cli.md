# Contract: what this feature asks of `bd`

**Feature**: `specs/002-beads-issue-relations/` · **Date**: 2026-09-23

Every invocation below was run against a real tracker while writing this plan
(see [research.md](../research.md)); the fields listed are fields observed, not
fields documented. `bd` is always run with `default-directory` at
`(beads-toplevel)`, as the existing code already does.

If a future `bd` stops emitting one of the fields marked **required**, the
corresponding mark must disappear rather than the section breaking: a missing
field is read as "no relation", never as an error.

## Existing calls — unchanged

```
bd list --status=in_progress --json -n 0
bd ready --json -n 0
```

Newly consumed fields, both calls:

| Field | Required | Meaning |
|-------|----------|---------|
| `parent` | no | id of the parent issue; absent when there is none |
| `dependency_count` | no | number of dependency edges; absent reads as 0 |
| `dependent_count` | no | number of issues depending on this one; absent reads as 0. **Counts `blocks` dependents only** — an issue's children are not in it, though `bd show`'s field of the same name counts them. Measured on a real tracker: an epic with seven children reports 0 here and 7 from `bd show`. |

The `dependencies` array on these records is deliberately **not** consumed: it
carries only `issue_id`, `depends_on_id` and `type`, with neither title nor
status, and using it to decide what blocks would duplicate bd's resolution.

## New call — blocked set

```
bd blocked --json
```

**Made only when** at least one in-progress issue has `dependency_count > 0`.
Ready issues are unblocked by construction, so they never trigger it.

Returns an array of the issues bd considers blocked:

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | the blocked issue |
| `blocked_by` | yes | array of blocker ids |
| `blocked_by_count` | no | length of `blocked_by`; not relied on |

This call is the single authority for *which issues are blocked and by what*.
A dependency on a closed issue does not appear here, which is how FR-003 is
satisfied without any status logic in Emacs.

Observed cost: 0.10 s.

## New call — resolving relation targets

```
bd list --id=<id1>,<id2>,… --all --json -n 0
```

**Made only when** there is at least one parent id or blocker id to resolve, and
made once for all of them together.

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | joins back to the requested id |
| `title` | yes | shown in the body line and in the choice prompt |
| `status` | yes | shown beside a blocker; distinguishes closed from missing |

`--all` is required: without it a relation pointing at a closed issue returns
nothing and is indistinguishable from a relation pointing at a deleted one.

An id that is requested and not returned yields an unresolved target
(FR-015). Requesting an id that does not exist is not an error.

Observed cost: 0.17 s, flat in the number of ids.

## New call — one issue's relations, outside the status buffer

```
bd show <id> --json
```

Used by the relation commands when invoked from a `beads-show-mode` buffer,
which has no relation table (FR-011). Interactive only, never on a refresh.

| Field | Required | Meaning |
|-------|----------|---------|
| `parent` | no | id of the parent |
| `dependencies[]` | no | fat records: `id`, `title`, `status`, `dependency_type` |
| `dependent_count` | no | for the dependents mark |

A `dependencies` entry with `dependency_type` of `blocks` and a `status` other
than `closed` is a blocker; one with `parent-child` names the parent. This is
the one place status is read directly, because `bd blocked` answers for the
whole tracker rather than for one issue and is the more expensive answer here.

Observed cost: 0.21 s for one id, and linear in the number of ids — which is why
it is not used on the refresh path.

## New call — dependents of one issue

```
bd show <id> --json --include-dependents
```

Made only when the developer asks to navigate to a dependent. `bd`'s own help
warns this "may be slow on hub beads", so it stays off the refresh path.

| Field | Required | Meaning |
|-------|----------|---------|
| `dependents[]` | yes | records with `id`, `title`, `status`, `dependency_type` |

## Failure handling

Unchanged from today: `beads--issues` returns a string describing the failure
when `bd` exits non-zero or prints unparsable JSON, and `beads--failure-line`
extracts the explanatory line from stderr.

New rule: a failure of a *relation* call never fails the section. The issues are
listed as they are today, without marks, and the failure is reported once in the
section rather than per issue (FR-015, edge case "Tracker unreachable").
