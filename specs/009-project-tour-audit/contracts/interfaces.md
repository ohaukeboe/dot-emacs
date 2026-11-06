# Contract: Commands, Adapters, Skills

Only additions and changes to
[006's interfaces](../../006-review-walkthrough/contracts/interfaces.md).

## `walkthrough.el`

- `walkthrough-install DRAFT-FILE` (function): unchanged signature.
  Dispatches validation on `kind`; for tour/audit sets `base` = `head` =
  `commit`.
- `walkthrough-validate DATA` (function): hunk coverage for `changes`, the
  research R5 rules for `tour` and `audit`.
- `walkthrough-open FILE` (command): any kind. Range `C..C` for tour/audit;
  the intro says when `HEAD` has moved.
- `walkthrough-open-tour &optional PICK` (command): the whole-project tour;
  with `PICK`, choose among tours. Offers a request when there is none.
- `walkthrough-open-audit &optional PICK` (command): the same for audits.
- `walkthrough-request-tour &optional AREA` (command): sends
  `/project-tour[ AREA]` through `walkthrough-request-function`; a prefix
  reads AREA.
- `walkthrough-request-audit &optional AREA` (command): sends
  `/project-audit[ AREA]`.
- `walkthrough-diff-label` (function): `code at <oid>` when the range's ends
  are equal, else unchanged.
- `walkthrough-accepted-findings` (function): unchanged signature; audit
  items carry `:type` and a synthetic `:patch`.

Keys and finding commands are unchanged and apply to every kind.

## `config.org` adapters

- **MCP tool `open_walkthrough`**: description names tours and audits; code
  unchanged.
- **`my/magit-review--format`**: prints a finding's `:type` after its
  severity; says "the diff or commit it refers to".
- **`my/magit-review-comment-send`**: step-comment intro drops "of this diff".
- **`@` transient**: column "Project" with `t` `walkthrough-open-tour`, `T`
  `walkthrough-request-tour`, `a` `walkthrough-open-audit`, `A`
  `walkthrough-request-audit`.

## Skill `project-tour` (`workstation/agents/skills/project-tour/SKILL.md`)

`/project-tour [AREA]`. Read-only.

1. Commit: `git rev-parse HEAD`. Name uncommitted changes left out (FR-002).
2. Explore: docs (README, AGENTS.md, ADRs), entry points, build files; the
   `codebase-memory` graph when available; `Explore` subagents for areas of a
   large tree. Skip generated, vendored and lock files.
3. Shape 6–15 steps: overview with a diagram first, foundations, parts,
   cross-cutting flows (FR-020, FR-021). Each step says what it uses and what
   uses it (FR-022). Diagram where 3+ parts interact; excerpts ≤ 40 lines,
   only where the point depends on the code (FR-023, FR-024). No findings.
4. List areas not covered in `skipped`.
5. Write `$TMPDIR/tour.json`; call `open_walkthrough`; fix and retry on errors.
6. Report steps, area, skipped.

## Skill `project-audit` (`workstation/agents/skills/project-audit/SKILL.md`)

`/project-audit [AREA]`. Read-only.

1. Commit as above.
2. `git ls-files` in AREA; drop generated, vendored, lock files; split into at
   most 6 areas.
3. One subagent per area, in parallel, each returning findings as JSON:
   severity, type, title, body, failure scenario (defects), anchor. Defects
   and smells (FR-030).
4. In the main session: verify each defect against the code and set
   `verdict`; drop what is wrong; merge a smell found in many places into one
   finding listing them.
5. One step per area with enough context to judge its findings (FR-032);
   `skipped` lists what was not read (FR-035).
6. Write `$TMPDIR/audit.json`; call `open_walkthrough`; fix and retry.
7. Report counts by severity and type, and the `a`/`x`/`u`, `@ s` keys.
