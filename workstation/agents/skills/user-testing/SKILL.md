---
name: user-testing
description: Run a persona-driven user-testing session against a live application — usability friction and exploratory functional QA in one pass — driving whatever UI-automation MCP is attached (chrome-devtools-mcp for web, mobile-mcp for Android/iOS, or another driver). Use when the user says "user test this", "run a usability test", "test this app as a user", "try the signup flow as a new user", "does this UI make sense", "find UX problems", "explore this app for bugs", or asks for a UX review of something that is actually running. Not for unit, integration or scripted E2E tests, and not for reviewing a design that is not running.
---

# User testing a live application

Drive a running application the way a person with a goal would, and report what
got in their way. Two kinds of finding come out of one session: **usability
friction** (confusion, dead ends, missing feedback, heuristic violations) and
**functional defects** (broken states, bad error messages, accessibility
failures).

## What this produces, and what it is not

Findings are **falsifiable hypotheses about the artifact**, each backed by an
artifact a human can re-open. They are a first-pass screen, not user research.

Never write, and never let the report imply:

- "users would…", "most people would…", "X% of users…"
- anything about how a real group — especially a marginalized one — experiences
  the product

There is no behavioral evidence in this session. There is a trajectory through a
real UI and a pile of captured artifacts. Report those. `references/evidence.md`
records why this boundary exists, with sources.

## The loop

### 0 · Resolve the driver

Probe which UI-automation tools are actually available in this session, then
bind the four verb families to them. Never assume a driver.

| Verb family | Means |
| --- | --- |
| `observe` | get a structured list of on-screen elements |
| `act` | tap / click, type, scroll, go back, navigate |
| `capture` | screenshot, screen recording |
| `inspect` | console or device logs, network, crashes, performance |

Read the matching file in `references/drivers/` for the driver you found —
`chrome-devtools.md` or `mobile.md`. Each one carries the verb mapping **and
the places where the abstraction leaks**, which are not optional reading:
element identity is durable on web and stale-on-layout-change on mobile; log
capture is retrospective on web and prospective-only on mobile; mobile has no
wait primitive at all.

If the driver you found has no file, write one from
`references/drivers/_template.md` before running, and say so in the report.

If no UI-automation tools are present, stop and say which one to attach. Do not
substitute reasoning about screenshots the user pasted — that is the exact mode
with the highest false-positive rate.

Record the driver, the tool names bound, and the capability set in the session
sheet header. A finding replayed against the wrong driver is worthless.

### 1 · Charter the session

A session is one charter, time-boxed, with a written mission. Pick charters from
`references/charters.md`; run **several short sessions, not one long one**.

One charter per session sheet. A charter that grows a second goal mid-run is two
charters — close the sheet and open another.

Agents collapse onto a single path by default, so coverage has to be forced
structurally rather than trusted:

- run at least one **error/adversarial** charter alongside any happy path
- vary the **entry point** (deep link, cold start, signed-out, back button)
- at the end, list the branches you saw and did **not** take

### 2 · Pick the persona

A persona here varies what is **observable**, not backstory. Useful axes:
screen reader on, 200% zoom or largest font, one-handed, throttled network,
first-run vs returning, signed-out, no permissions granted, wrong locale,
interrupted mid-flow.

Persona depth buys believability, not accuracy. Two sentences is enough. What
matters is the constraint, because the constraint changes what the UI has to do.

### 3 · Run as the actor

Pursue the charter's goal like someone who wants it done. Before each action,
`observe`; after each action, `observe` again and note what changed.

Keep a running trajectory: step number, intent, element acted on (by its label
and role, not only its coordinates), what you expected, what happened.

When something looks wrong, **do not route around it**. Capture, note it, and
either stop the subtask or take the detour *explicitly* with a trajectory line
saying you did. An agent that silently finds another way to the goal is the
single documented reason agent test runs miss real defects.

When nothing responds, you cannot tell slow from broken by looking. Re-observe
until the screen changes or the budget runs out, and **record the wait budget**
as part of any "no response" note.

### 4 · Observer pass

Launch a **subagent** to judge the run. Give it the trajectory, the artifact
paths, the driver's leak notes and the persona. **Do not give it the goal.**

Its job is narrow: for each anomaly, decide whether the evidence supports a
defect in the application, an execution error by the actor, or neither. It does
not attribute cause beyond that, and it does not care whether the task
succeeded.

This split exists because goal-pursuit suppresses defect reporting. Judging your
own run while still holding the goal produces both error directions: real
defects written off as your own mis-taps, and imagined defects where the
screenshots show none.

### 5 · Evidence gate

A finding ships only if **both** hold:

1. **It is real.** An artifact from the running app shows it: a screenshot, an
   element snapshot, a log line, a failed request, a crash. Cite the artifact by
   path. On mobile, cite the element *label* plus a screenshot — coordinates are
   not a durable identifier.
2. **It is not you.** The trajectory shows the action landed on the element you
   meant. If it might have been a mis-tap, redo it deliberately from a fresh
   observe and capture again. A blind retry is not evidence.

Anything failing either test goes in **Notes**, not **Issues** or **Bugs**.
Drop it entirely rather than hedge it into a finding.

Severity for usability findings, on the frequency × impact × persistence scale
in `references/charters.md`:

| | |
| --- | --- |
| `0` | not a usability problem |
| `1` | cosmetic — fix if time allows |
| `2` | minor — low priority |
| `3` | major — important, high priority |
| `4` | catastrophe — must fix before release |

Functional defects carry a repro instead: driver, entry point, numbered steps,
expected, actual, artifact paths.

### 6 · Write the session sheet

Copy `assets/session-sheet.md` and fill every section. The sheet is the unit of
output; prose lives inside the tags, never instead of them.

Then run the validator:

```bash
scripts/validate-session-sheet <sheet.md>
```

It fails the sheet when a section is missing or a finding cites an artifact path
that does not exist on disk. Fix what it reports before writing the report —
a citation that does not resolve is the failure mode this whole skill is built
to prevent.

### 7 · Report

Deliver two things:

1. **The session sheet(s)** — written to the path the user asked for, or
   `docs/user-tests/<yyyy-mm-dd>-<charter-slug>.md` by default.
2. **An artifact page** — the findings ranked by severity, with the screenshots
   inline, the repro steps, the paths not taken, and the standing disclaimer
   that these are hypotheses to verify. Publish it with the Artifact tool and
   give the user the link.

Close with the PROOF debrief from the session sheet: what happened, what was
achieved, what got in the way, what still needs running, and how the persona
felt. The last one is the only subjective line in the whole report, and it is
labelled **not evidence**.

## Hard rules

- **No finding without a resolvable artifact path.** No exceptions, no hedged
  "possible issue" entries.
- **No behavioral claims.** See the top of this file.
- **Never fabricate a screen you did not reach.** If auth, payment or a device
  capability blocked the charter, that is an Obstacle, and the charter is
  reported as partially run.
- **Never take a destructive action to "see what happens"** — no deleting
  another user's data, no real payments, no sending mail to real addresses.
  Ask first, every time, and record the refusal as an untested branch.
- **Label the run's standing.** An accessibility-persona run or a run against a
  novel product is a **heuristic probe**, not a substitute for testing with the
  people it concerns. Say so in the report.

## Files

- `references/drivers/` — one file per UI-automation driver: verb mapping and
  its leaks. `_template.md` to add a new one.
- `references/charters.md` — charter library and the severity scale.
- `references/evidence.md` — dated research backing, with sources. Every number
  lives here.
- `assets/session-sheet.md` — the SBTM session sheet template.
- `scripts/validate-session-sheet` — artifact-existence and structure validator.
