# Issue tracker: beads (bd)

Issues for this repo live in **beads**, a local issue tracker backed by Dolt
(`.beads/`), synced to a Dolt remote. GitHub Issues are **not** used, even
though the repo has a GitHub remote. Do not use TodoWrite, TaskCreate, or
markdown TODO lists.

Run `bd prime` at session start for the full command reference.

## When a skill says "publish to the issue tracker"

```bash
bd create --title="Summary" --description="Why this exists and what to do" \
  --type=task|bug|feature --priority=2
```

- Priority is `0`–`4` (0 = critical, 2 = medium, 4 = backlog), not high/medium/low.
- Use `--parent=<id>` for hierarchical children (subtask under task, task under epic).
- Optional structured fields: `--acceptance=`, `--design=`, `--notes=`; `--validate` checks required sections.
- Dependencies: `bd dep add <issue> <depends-on>`.
- Issue bodies are written for humans: normal prose, not compressed shorthand.

## When a skill says "fetch the relevant ticket"

```bash
bd show <id>          # full issue with dependencies
bd search <query>     # keyword search
bd ready              # issues with no blockers
bd list --status=open
```

## Claiming, updating, closing

```bash
bd update <id> --claim
bd update <id> --title/--description/--notes/--design
bd close <id> [--reason="..."]
```

Never run `bd edit` — it opens `$EDITOR` and blocks agents.

## Triage state

Triage roles are bd **labels** (`bd label`), see `triage-labels.md`.

## Syncing

`bd dolt push` / `bd dolt pull`. Only with explicit user authority — the
default posture in this repo is conservative: report, don't push.

## PRs as a request surface

**Off.** External PRs are not part of the triage queue. Flip this to on if
that changes.
