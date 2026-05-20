---
name: tdd-crew
description: >
  Ship a feature or bugfix using a role-based agent team that follows strict
  TDD (RED → GREEN → REFACTOR). Picks specialists — Frontend Developer,
  Backend Architect, Mobile App Builder, Security Engineer — based on the
  project type, then dispatches tester roles (Evidence Collector,
  Reality Checker, API Tester) to verify before declaring done. Use this skill
  whenever a task is non-trivial AND touches multiple layers OR would benefit
  from independent testing — even if the user does not say "agent team" or
  "TDD" explicitly. Examples: "build the checkout flow", "add auth with rate
  limiting", "ship the dashboard end to end", "refactor the API and the iOS
  client together", "add user profile editing with backend persistence". Skip
  only for single-file tweaks or tasks with a single, obvious implementation
  step.
---

# tdd-crew

Ship features with a role-based agent team. Every implementer follows TDD. Testers verify before done.

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your environment. Confirm with the user before creating the team.

## Reference files

Load these as needed — do not load all at once:

| File                                    | When to read                                     |
|-----------------------------------------|--------------------------------------------------|
| `references/role-selection.md`          | Step 1 — pick the roster                         |
| `references/tdd-contract.md`            | Include verbatim in every implementer prompt     |
| `references/coordination.md`            | Lead playbook for dispatch, gating, and shutdown |
| `references/role-frontend-developer.md` | Include in Frontend Developer's prompt           |
| `references/role-backend-architect.md`  | Include in Backend Architect's prompt            |
| `references/role-mobile-app-builder.md` | Include in Mobile App Builder's prompt           |
| `references/role-security-engineer.md`  | Include in Security Engineer's prompt            |
| `references/role-evidence-collector.md` | Include in Evidence Collector's prompt           |
| `references/role-reality-checker.md`    | Include in Reality Checker's prompt              |
| `references/role-api-tester.md`         | Include in API Tester's prompt                   |

---

## When to use this skill

**Use tdd-crew when:**
- The feature touches more than one layer (UI + API, API + DB, mobile + backend)
- The task would benefit from someone independently verifying the work
- The feature is non-trivial (more than a single file change)
- You want TDD discipline enforced across the whole change

**Skip when:**
- Single-file, obviously correct change (typo fix, rename, config tweak)
- The user explicitly wants to work solo and iterate manually

---

## Step 1: Scope and role selection

Read `references/role-selection.md`. Apply the heuristic to the user's request. Pick the minimum roster that covers the task.

Present to user:
```
Proposed team for "[task]":
  ✦ [Role] — [one-line reason]
  ...

Vertical slices:
  1. [user-visible behaviour]
  2. [user-visible behaviour]
  ...

Confirm roster and slices, or adjust?
```

Wait for confirmation before proceeding.

Slicing rules (from `references/coordination.md`):
- One slice = one observable user behaviour, end to end
- Small enough for one TDD cycle
- 2–5 slices per feature; split further if a slice feels like "all CRUD"

---

## Step 2: Create the team and spawn full roster

After user confirms, read `references/coordination.md` for the full spawn protocol. Then:

```
TeamCreate: { team_name: "tdd-crew-[short-kebab-task-name]" }
```

Spawn **all teammates in a single message** (parallel `Agent` calls). Each implementer gets:

- Full content of their `references/role-*.md`
- Full content of `references/tdd-contract.md`
- The complete slice list with owner labels (which slices belong to which role)
- The message vocabulary block (see `references/coordination.md`)
- If they consume an API: instruction to wait for `CONTRACT: <slice-name>` from Backend Architect before RED on dependent slices

Spawn testers alongside implementers (not at the end):
- Evidence Collector (if UI in roster): watches for `GREEN: <slice>` from Frontend/Mobile, verifies each slice as it lands
- API Tester (if Backend in roster): watches for `GREEN: <slice>` from Backend Architect, tests each slice as it lands

Reality Checker is **not** spawned yet — dispatched only when all per-slice PASS signals are in.

---

## Step 3: Contract-first launch (Backend + API consumers)

If the roster has Backend Architect **and** any API-consuming role (Frontend / Mobile):

Backend Architect's prompt instructs it to:
1. Draft endpoint contracts for all its owned slices first
2. `SendMessage CONTRACT: <slice-name>` with endpoint signatures and request/response shapes to the team **before** writing any tests
3. Then proceed with TDD on its own slices

API-consuming implementers:
- Start TDD immediately on slices that have no API dependency
- For API-dependent slices: wait for the matching `CONTRACT:` message, then proceed with RED

If no API layer in roster: all implementers begin TDD on their slices simultaneously.

---

## Step 4: Parallel TDD + shadow verification

Implementers run their own TDD loop (RED → GREEN → REFACTOR) concurrently. When a slice completes:

```
SendMessage: "GREEN: <slice-name>\nTests: [paths]\nDiff summary: [brief]"
```

Shadow testers respond to each `GREEN:` message immediately:
- Evidence Collector replies `EVIDENCE: <slice-name> PASS` or `EVIDENCE: <slice-name> FAIL — [notes]`
- API Tester replies `API: <slice-name> PASS` or `API: <slice-name> FAIL — [findings]`

**Lead watches** for abort tokens and tester FAIL reports:
- `too-big.` — re-slice and re-dispatch that implementer
- `regressed.` — read report; existing tests must be fixed before new work continues
- `ambiguous.` — clarify spec; re-dispatch
- `EVIDENCE: <slice> FAIL` or `API: <slice> FAIL` — re-dispatch the relevant implementer with the failure as a new slice spec; tester re-verifies after fix

When all owned slices are GREEN + PASS: **dispatch Reality Checker** with all DONE, EVIDENCE, and API reports collected.

Gate on `Verdict: PASS` before declaring done.

If Reality Checker issues `NEEDS WORK` or `BLOCKED`:
- Read the specific blockers
- Re-dispatch the relevant implementer with blockers as new slice specs
- Shadow testers re-verify the fixed slices; Reality Checker runs again after

---

## Step 5: Shutdown and summary

When Reality Checker issues PASS:

1. Send `shutdown_request` to each teammate via `SendMessage`
2. Wait for idle confirmations
3. Report to user:

```
Feature done.
Slices shipped: [list]
Tests added: [total]
Roles used: [list]
Deferred: [list or "none"]
```

---

## Abort triggers (first-token contract)

If any implementer role returns one of these as the very first token, stop and handle before proceeding:

- `too-big.` — slice is too large; re-slice before re-dispatching
- `regressed.` — existing tests broken; must fix before new work continues
- `ambiguous.` — slice spec unclear; clarify with user before re-dispatching

---

## Notes

- **You are the lead.** You do not write application code.
- **Spawn in parallel.** All implementers and shadow testers start in one message. Sequential dispatch wastes the team feature.
- **Teammates have no memory.** Every prompt must be self-contained: full persona, full TDD contract, full slice list, full message vocabulary.
- **The global `/tdd` skill** is available to all teammates for deeper TDD guidance. They can consult it on hard design decisions.
- **Token cost scales with team size.** Prefer the minimum roster; add roles only when genuinely needed.
