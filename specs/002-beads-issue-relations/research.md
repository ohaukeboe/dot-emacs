# Phase 0 Research: Beads Issue Relations in Magit

**Date**: 2026-09-23 · **Feature**: `specs/002-beads-issue-relations/`

All timings were measured in this worktree against the real tracker
(79 issues, 7 open, Dolt-backed) with `/usr/bin/env time -f %e`, three runs each;
the spread was under 20 ms. Relation shapes were established in a throwaway
tracker built for this purpose, not assumed from the documentation.

## R1 — How bd reports a parent

**Decision**: read the top-level `parent` field, present on both
`bd show --json` and `bd list --json`.

**Rationale**: verified empirically. `bd create --parent=<id>` produces a child
whose `bd show --json` carries `"parent": "lab-lyy"` at the top level *and* an
entry in `dependencies` with `"dependency_type": "parent-child"`. The top-level
field is the cheaper and less ambiguous of the two, and it also appears in
`bd list --json`, which the section already calls.

**Alternatives considered**:

- *Derive the parent from the id.* bd numbers children hierarchically
  (`lab-lyy` → `lab-lyy.1`), so the parent looks like an id prefix. Rejected:
  `bd dep add <a> <b> --type parent-child` can create a parent-child edge
  between two unrelated ids, and string surgery on ids would then be wrong.
- *Filter `dependencies` for `parent-child`.* Works, but requires the fat
  `bd show` record (see R3) where the `parent` field does not.

## R2 — How bd reports blockers, and what counts as one

**Decision**: take the set of blocked issues and their blockers from
`bd blocked --json`, which returns `blocked_by` (a list of ids) and
`blocked_by_count` per blocked issue. Never compute "is this blocked" in Emacs.

**Rationale**: this is the tracker's own resolution, which is what FR-017 and
the existing rule in `CONTEXT.md` ("Computed by `bd`, never derived in Emacs — a
second implementation of blocker resolution would drift from the first") both
demand. `bd blocked --json` costs 0.10 s on the real tracker — cheaper than
either call the section already makes.

Confirmed that a dependency on a *closed* issue is not reported as a blocker:
in the throwaway tracker, a child with one open and one closed `blocks`
dependency appeared in `bd blocked` with `blocked_by` naming only the open one.
FR-003 therefore needs no logic of its own; it falls out of using `bd blocked`.

**Alternatives considered**:

- *Join the thin `dependencies` edges from `bd list` against each target's
  status.* Free (no extra call) and agrees with bd on today's data, but it is
  exactly the second implementation the domain vocabulary forbids. Rejected.
- *`bd show <id> --json` per listed issue.* Gives fat dependency records
  including each blocker's `status`, but costs ~0.12 s **per id** (0.21 s for 1,
  0.45 s for 3, 1.05 s for 7 — linear). Rejected on cost; see R4.

## R3 — Resolving a related issue's title and status

**Decision**: one `bd list --id=<comma-separated ids> --all --json -n 0` call
resolves every relation target at once, and only when there is at least one.

**Rationale**: `bd blocked` and the `parent` field both yield bare ids; the
marks need a title, and blockers need a status. `bd list --id=...` returns full
records for exactly those ids in a single flat query at 0.17 s regardless of how
many ids are asked for — the same cost as the `bd list` the section already
makes. `--all` is required so that a relation pointing at a closed issue still
resolves (FR-015 distinguishes "closed" from "missing", and without `--all` the
two look alike).

**Alternatives considered**:

- *`bd show <ids...> --json`* accepts several ids and returns richer records,
  but its cost is linear in the number of ids (R2). Rejected.
- *`bd list --all --json -n 0`* (every issue, 0.21 s, 137 KB) as a lookup table.
  Flat cost, but it grows with the tracker and makes Emacs parse 137 KB of JSON
  on every refresh for a handful of ids. Rejected.

## R4 — Keeping the refresh cost proportional to the relations present

**Decision**: make every relation call conditional. The section's two existing
calls are unchanged. A third (`bd blocked`) happens only when some listed issue
has `dependency_count > 0`; a fourth (`bd list --id=...`) only when there is at
least one unresolved parent or blocker id.

**Rationale**: this is the only shape that satisfies FR-018 and SC-004a/SC-004b. Measured
costs:

| Call | Cost | When |
|------|------|------|
| `bd list --status=in_progress --json -n 0` | 0.17 s | always (today) |
| `bd ready --json -n 0` | 0.12 s | always (today) |
| `bd blocked --json` | 0.10 s | only if a listed issue has dependencies |
| `bd list --id=… --all --json -n 0` | 0.17 s | only if there are ids to resolve |

A tracker whose listed issues have no relations — this repository today: zero
issues with a parent, zero in-progress issues — makes **no** extra call and
refreshes at exactly today's 0.29 s. A tracker where relations exist pays at
most 0.56 s, +93%.

Two further economies fall out of the spec:

- Ready beads are unblocked by construction, so blocker resolution is only ever
  needed for the in-progress group. The `bd blocked` call is therefore gated on
  the in-progress issues alone.
- FR-004 asks only *how many* issues depend on an issue. `dependent_count` is
  already in the output of both existing calls, so the dependents mark costs
  nothing. The *identities* of dependents are fetched lazily, on navigation
  only, with `bd show <id> --json --include-dependents` — the call bd's own help
  warns "may be slow on hub beads", kept off the refresh path entirely.

**Against the success criteria**: this is what SC-004a and SC-004b were amended
to describe, after the measurements above showed a single relative bound could
not cover both cases. SC-004a is the no-relations case — no extra call, today's
0.29 s. SC-004b is the bound on the other case — two extra calls, neither of them
per-issue, 0.56 s measured. The earlier wording ("within 10% of the time it takes
today") held only for the first case and was amended rather than designed
around.

## R5 — Where the marks go, given that issue sections start collapsed

**Decision**: compact glyph marks in the heading line, full `Parent:` and
`Blocked by:` lines in the body.

**Rationale**: `beads--insert-issue` creates its section with the hide flag set,
so the body — where `Assignee:` and the description live — is not visible until
TAB. A mark that is only in the body fails FR-001's "without invoking a
command". A heading that carries `dot-emacs-k6c  P2  Some fairly long blocker
title` for each of two blockers destroys the one-line-per-issue listing.

Splitting it satisfies both: the heading answers *is there a relation* at a
glance, the body answers *which issue* on the TAB the developer already uses to
read the description. The body lines follow the shape of the existing
`Assignee:` line, so they need no new layout idea.

**Alternatives considered**:

- *Expand issues with relations by default.* Rejected: it changes the listing's
  density for reasons the developer did not ask for, and FR-005 forbids
  relation-free issues from moving.
- *A separate relations subsection.* Rejected: it separates a relation from the
  issue it belongs to, which is the thing being marked.

## R6 — Reaching the commands without taking a Magit key

**Decision**: expose the four commands through the existing `#` transient only;
bind no new keys in `beads-issue-section-map` or `magit-mode-map`.

**Rationale**: `p`, `b` and `n` are all live Magit keys (`magit-section-backward`,
`magit-branch`, `magit-section-forward`), and a section keymap entry would
shadow them wherever point sits on an issue — a surprising loss of navigation in
exchange for one keystroke. `#` then a letter is two keystrokes, which is what
SC-002 asks for, and it puts the commands where FR-014 wants them anyway.

**Alternatives considered**: a `beads-relations` sub-transient under `#`.
Rejected as a third keystroke for four commands.

## R7 — Marking a command unavailable rather than letting it fail

**Decision**: `transient-define-prefix` entries use `:inapt-if-not`, not `:if`.

**Rationale**: FR-014 requires the entry be *shown as unavailable*. `:if` removes
the entry, so the menu's shape would change per issue and the developer could
not learn it; `:inapt-if-not` keeps it in place and greys it out. The predicate
reads the relation table for the issue at point, which is already computed.

## R8 — Landing on an issue that is already listed

**Decision**: search the current buffer's `beads-issue-section`s for one whose
value is the target id; on a hit, `magit-section-show` it and move point to its
start; on a miss, call `beads-show`.

**Rationale**: FR-009/FR-010. The section's value is already the issue id, and
`beads--issue-at-point` reads it that way, so no new identity scheme is needed.
Opening a `bd show` buffer for an issue three lines up would be a worse answer
to "move to it" than moving.

**Note for the implementation**: the issue id must stay the section *value*.
Attaching a relation record there instead would break `beads--issues-at-point`,
`beads--targets` and every command built on them. Relations are therefore held
in a buffer-local table keyed by id, rebuilt on each insertion, and looked up
from point — not stored in the section object.

## R9 — Going back

**Decision**: a session-scoped list of `(buffer . marker)` pairs, pushed before
a jump and popped by `beads-go-back`; dead buffers and dead markers are dropped
on the way.

**Rationale**: FR-013 asks for repeated returns in reverse order, which is a
stack. A marker survives the buffer being refreshed, which a raw position does
not — Magit rewrites the status buffer on every `g`. Buffers do not survive
being killed, so entries are validated as they are popped rather than when they
are pushed.

**Alternatives considered**: reusing Emacs' `mark-ring` or `xref` history.
Rejected: both are shared with unrelated commands, so popping one would take the
developer somewhere that has nothing to do with the tracker.

## R11 — `dependent_count` means two different things

**Found during implementation**, running the finished section against a real
tracker rather than the fake `bd` of the suite.

`bd list --json` and `bd ready --json` report `dependent_count` counting only
the issues joined by a `blocks` edge. `bd show --json` reports a field of the
same name that also counts the issue's children. Measured on this repository's
tracker, on the epic created for this very feature:

```
bd ready --json     → dot-emacs-9ym  dependent_count 0
bd show  --json     → dot-emacs-9ym  dependent_count 7   (its seven tasks)
```

There is no `children` field and no child count anywhere in the listing output,
and `bd list --parent=<id>` asks per parent, which is a call per issue.

**Decision**: the mark reports the listing's number and `beads-goto-dependent`
asks `bd show --include-dependents`, which knows about children. A parent whose
only inbound relations are its children therefore carries no `↳` mark, and its
children are still reachable by the command; the transient entry is grey there,
since greyness reflects what is cheaply known.

**Rationale**: the alternative that would make the mark exact is one
`bd list --all --json -n 0` per refresh (0.21 s) to tally `parent` fields. It
cannot be conditional — whether any listed issue has children is exactly what it
would be asking — so it would be paid on every refresh of every repository,
which is what SC-004a forbids. FR-004 was narrowed to what the listing can
truthfully report instead, rather than leaving a mark that is quietly wrong.

**Alternatives considered**: counting children among the issues the section
already lists. Free and exact for listed children only, which makes the number
depend on what happens to be on screen — a worse answer than a smaller honest
one.

## R10 — Verifying the feature

**Decision**: extend `workstation/emacs/packages/beads-test.el`, whose fake `bd`
on `PATH` already stands in for the tracker, and add a `packages.test-beads`
attribute so the suite is runnable as `nix build .#test-beads -L`.

**Rationale**: the existing fake `bd` is a shell script that dispatches on `$1`
and cats a fixture file; adding `blocked)` and an `--id` case to it is the whole
fixture change. Constitution Principle III puts anything that builds an Emacs
closure in `packages.*` rather than `checks.*`, and `tests/emacs-sops-save.nix`
is the pattern to copy. Without it, this feature's only verification is a
command in a file header that nothing runs.

**Alternatives considered**: leaving the suite manual, as today. Rejected: the
feature roughly doubles the size of `beads.el`, and Principle I's spirit — make
the mistake fail where it is cheap — applies even though Nix evaluation itself
cannot see Emacs Lisp behaviour.
