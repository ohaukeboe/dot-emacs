# Lead Coordination Playbook

You (the main thread) are the lead. You do not write application code. You orchestrate, dispatch, and gate.

## Your responsibilities

1. Scope the task into 2–5 vertical slices (user-visible behaviours)
2. Select and confirm roles with user (see `role-selection.md`)
3. Create the team and spawn **all** implementers + shadow testers in parallel (single message)
4. Watch the team channel for `GREEN:`, `EVIDENCE:`, `API:`, and abort tokens
5. Handle abort tokens and tester FAIL reports immediately (re-slice / re-dispatch)
6. Dispatch Reality Checker once every implementer's slices are GREEN and every shadow tester's per-slice report is PASS
7. Gate on Reality Checker PASS before declaring the feature done
8. Shut the team down and report to the user

## Slicing rules

A good slice:
- Delivers one observable user behaviour end to end
- Can be tested with a single failing test in the RED phase
- Is small enough to fit in one TDD cycle (one agent turn)
- Does not depend on another slice being complete first (where possible)

Bad slices: "implement all CRUD", "build the entire auth system". Break those into individual behaviours.

Example — "add user profile editing":
1. User can see their current profile data on the edit page
2. User can submit valid changes and see them saved
3. User sees validation errors for invalid input
4. Unauthenticated users are redirected to login

## Spawning teammates

Use `TeamCreate` once, then spawn **all** implementers and shadow testers **in a single message** (parallel `Agent` calls):

```
TeamCreate: { team_name: "tdd-crew-[short-task-name]" }

// All in one message:
Agent: { team_name: "...", name: "backend", subagent_type: "general-purpose", prompt: [...] }
Agent: { team_name: "...", name: "frontend", subagent_type: "general-purpose", prompt: [...] }
Agent: { team_name: "...", name: "evidence-collector", subagent_type: "general-purpose", prompt: [...] }
// etc.
```

Each implementer prompt must include:
- Full content of their `role-*.md`
- Full content of `tdd-contract.md`
- Complete slice list with owner labels (which slices belong to this role)
- The message vocabulary block below
- If API-consuming: instruction to wait for `CONTRACT: <slice>` before RED on dependent slices

Each tester prompt must include:
- Full content of their `role-*.md`
- Which `GREEN:` messages to watch for and from whom
- The message vocabulary block below
- Instruction to send per-slice `EVIDENCE:` / `API:` reports immediately when triggered

Teammates have no memory of prior turns — every prompt must be self-contained.

## Dispatch message format

Implementer prompt:

```
You are the [Role Name] on this team.

[paste role-*.md content]

---

TDD CONTRACT (follow exactly):
[paste tdd-contract.md content]

---

TEAM MESSAGE VOCABULARY:
[paste message vocabulary section below]

---

SLICE ASSIGNMENTS (your slices are marked ★):
  ★ [slice N] — [acceptance criteria]
    [slice M] — owned by [other role]
  ...

[If API-consuming:]
Wait for `CONTRACT: <slice-name>` from Backend Architect before RED on any API-dependent slice.
For slices with no API dependency, begin TDD immediately.

[If Backend Architect:]
Before writing any tests: draft endpoint contracts for all your slices, then SendMessage each as `CONTRACT: <slice-name>` with endpoint signatures and request/response shapes. Then proceed with TDD.

When REFACTOR is done for a slice, send: `GREEN: <slice-name>` with test paths and a brief diff summary.
```

Tester prompt:

```
You are the [Role Name] on this team.

[paste role-*.md content]

---

TEAM MESSAGE VOCABULARY:
[paste message vocabulary section below]

---

Watch for `GREEN: <slice-name>` messages from [specific implementer role(s)].
For each GREEN message: verify that slice immediately and reply with your per-slice report:
  `EVIDENCE: <slice-name> PASS` or `EVIDENCE: <slice-name> FAIL — [notes]`
  (or `API:` prefix for API Tester)

Do not wait for all slices — verify each one as it arrives.
```

## Message vocabulary

All teammates use this vocabulary for `SendMessage`:

| Sender | Prefix | Payload |
|--------|--------|---------|
| Backend Architect | `CONTRACT: <slice>` | Endpoint signatures, request/response shapes — sent before writing tests |
| Any implementer | `GREEN: <slice>` | Test file paths, brief diff summary — sent when REFACTOR is done |
| Evidence Collector | `EVIDENCE: <slice> PASS` or `EVIDENCE: <slice> FAIL — [notes]` | Screenshot paths or failure description |
| API Tester | `API: <slice> PASS` or `API: <slice> FAIL — [findings]` | Per-criterion security/perf/contract findings |
| Any teammate | `too-big.` / `regressed.` / `ambiguous.` | Abort tokens — lead handles immediately |

## Gating rules

- Implementers run in parallel on their owned slices — no sequential gate between roles
- API-consuming implementers wait only for the `CONTRACT:` message for their dependent slices, not for full GREEN from Backend
- Shadow testers verify each slice as `GREEN:` arrives — no batch at end
- Reality Checker is dispatched only after: every implementer has sent `GREEN:` for all its slices **and** every shadow tester has sent PASS for every slice
- Do not declare done until Reality Checker issues `Verdict: PASS`

## Handling refusals

If an implementer returns `too-big.`, `regressed.`, or `ambiguous.`:
- `too-big.` — re-slice: break into smaller pieces
- `regressed.` — read the regression report; fix failing tests before continuing
- `ambiguous.` — clarify the slice spec and re-dispatch

## Shutdown

When Reality Checker issues PASS:

1. Send `shutdown_request` to each teammate via `SendMessage`
2. Confirm all teammates have shut down
3. Report to user:

```
Feature complete.
Slices shipped: [list]
Tests added: [total count]
Team: [list of roles used]
Any deferred items: [list or "none"]
```
