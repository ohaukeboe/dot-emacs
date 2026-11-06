# Spec-driven workflow skills

This is the configuration the mattpocock skills (`to-spec`, `to-tickets`,
`implement-spec`, `grill-with-docs`, `triage`, ...) say "should have been
provided to you". It replaces `/setup-matt-pocock-skills`; never suggest
running it, and never create `docs/agents/` files.

## Issue tracker

Pick the first that applies:

1. The repo documents its own tracker (`CLAUDE.md`, `AGENTS.md` or
   `docs/agents/issue-tracker.md`): use that.
2. `.beads/` exists: use `bd`.
3. The repo has a GitHub remote: use GitHub Issues through `gh`.
4. Otherwise ask the user. Never create a `.scratch/` local tracker.

A **ticket** is one item in that tracker. The tracker is always the task
graph, in Spec Kit repos too. Triage labels are the canonical five
(`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
`wontfix`) unless the repo documents a mapping.

## Domain docs

Before exploring, read `GLOSSARY.md` (or each relevant one listed in
`GLOSSARY-MAP.md`) and the ADRs in `docs/adr/` that touch the area. If they
are missing, proceed silently. Use the glossary's terms, and say so
explicitly when output contradicts an ADR. Before numbering a new ADR, list
`docs/adr/` on every local and remote branch (`git ls-tree`) and take the
highest number plus one.

## Spec Kit repos (`.specify/` exists)

- The active feature is the one in `.specify/feature.json`, but only when the
  request clearly concerns it; otherwise ask which `specs/NNN-*` to use. With
  no `feature.json`, work is outside any spec unless the user names one.
- `spec.md` is the only spec text. `to-spec` runs `speckit-specify` instead of
  writing its own spec, then creates one tracker epic titled
  `<Feature> (specs/NNN)` that links the spec directory without copying it.
- `to-tickets` files tickets under that epic from the items in `tasks.md`,
  keeping the `T0NN` ids in the titles. When a ticket with a `T0NN` id is
  closed, tick the matching `tasks.md` line `[X]` in the same change.
- `grill-with-docs` records resolved answers in the spec's `## Clarifications`
  section, in the format `speckit-clarify` uses.
- `.specify/memory/constitution.md` binds like an ADR. Promote a `research.md`
  decision to an ADR only if it is hard to reverse, surprising without
  context, and the result of a real trade-off; the ADR links back to it.
