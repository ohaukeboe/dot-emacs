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

| File | When to read |
|---|---|
| `references/role-selection.md` | Step 1 — pick the roster |
| `references/tdd-contract.md` | Include verbatim in every implementer prompt |
| `references/coordination.md` | Lead playbook for dispatch, gating, and shutdown |
| `references/role-frontend-developer.md` | Include in Frontend Developer's prompt |
| `references/role-backend-architect.md` | Include in Backend Architect's prompt |
| `references/role-mobile-app-builder.md` | Include in Mobile App Builder's prompt |
| `references/role-security-engineer.md` | Include in Security Engineer's prompt |
| `references/role-evidence-collector.md` | Include in Evidence Collector's prompt |
| `references/role-reality-checker.md` | Include in Reality Checker's prompt |
| `references/role-api-tester.md` | Include in API Tester's prompt |

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

## Step 2: Create the team

After user confirms:

```
TeamCreate: { team_name: "tdd-crew-[short-kebab-task-name]" }
```

Do not spawn any teammates yet. The team exists; teammates are spawned per-dispatch in Step 4.

---

## Step 3: TDD loop — one slice at a time

For each slice, in order:

### Dispatch to implementer

Read the relevant `references/role-*.md` and `references/tdd-contract.md`. Build the dispatch prompt:

```
[Full content of role-*.md]

---

TDD CONTRACT (follow exactly):
[Full content of tdd-contract.md]

---

SLICE SPEC:
Name: [slice name]
Acceptance criteria:
  - [concrete, testable behaviour]
  - [concrete, testable behaviour]
Context:
  - Relevant files: [paths]
  - Existing tests to be aware of: [paths or "none"]
  - API contract: [relevant endpoints or "n/a"]

Start with RED phase. Write failing tests before any production code.
Report back using your role's output format when REFACTOR is done.
```

Spawn via:
```
Agent: {
  team_name: "tdd-crew-[name]",
  name: "[role-short-name]",
  subagent_type: "general-purpose",
  prompt: [dispatch prompt above]
}
```

### Gate on handoff

Do NOT dispatch the next slice until you receive a `[ROLE] DONE` report with:
- Test file paths showing RED → GREEN
- No failing tests
- Refactor complete

If you receive a refusal token:
- `too-big.` — re-slice and re-dispatch
- `regressed.` — read the report; fix regressions before proceeding
- `ambiguous.` — clarify the slice spec and re-dispatch

Repeat for each slice.

---

## Step 4: Verification

After all implementer slices are green:

### Evidence Collector (if UI is involved)

Dispatch to Evidence Collector (`references/role-evidence-collector.md`) with:
- All acceptance criteria from every slice
- Paths to the implementation files
- Request: capture screenshots and verify each criterion

Gate on `EVIDENCE COLLECTED — Overall: PASS` before continuing.

### API Tester (if new API endpoints were built)

Dispatch to API Tester (`references/role-api-tester.md`) with:
- New/changed endpoint signatures from Backend Architect's reports
- Request: security, performance, and contract testing

Gate on `API TESTED — Overall: PASS` before continuing.

### Reality Checker (for production-bound features)

Dispatch to Reality Checker (`references/role-reality-checker.md`) with:
- All `DONE` reports from implementer roles
- All `COLLECTED` / `TESTED` reports from tester roles
- Request: final end-to-end verification and Go / No-Go

Gate on `Verdict: PASS` before declaring the feature done.

If Reality Checker issues `NEEDS WORK` or `BLOCKED`:
- Read the specific blockers
- Re-dispatch the relevant implementer role with the blockers as new slice specs
- Repeat verification after fix

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
- **One slice at a time.** Parallel dispatching is tempting but breaks the TDD gate discipline.
- **Teammates have no memory.** Every dispatch prompt must be self-contained: include the full persona and full TDD contract.
- **The global `/tdd` skill** is available to all teammates for deeper TDD guidance. They can consult it on hard design decisions.
- **Token cost scales with team size.** Prefer the minimum roster; add roles only when genuinely needed.
