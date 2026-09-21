# Driver: <name> (<platform>)

Copy this file to `<driver>.md` when you meet a UI-automation MCP that has no
file here yet — Playwright MCP, browser-use, a desktop-automation server, a
vendor's device-cloud server. Fill it in *before* running the session, and say
in the report that the driver file was written this session and is unverified.

Record the date you inspected the tool surface. These servers are version-pinned
and drift; a stale mapping produces confident, wrong repro steps.

Surface verified: `<yyyy-mm-dd>`

## Verb mapping

| Verb | Tools |
| --- | --- |
| `observe` | |
| `act` | |
| `capture` | |
| `inspect` | |
| *(setup)* | |

## Leaks

Work through all three. "None" is a valid answer, but only after checking the
tool's own description — assume nothing.

### 1 · Element identity

Answer: what identifies an element, and how long does that identifier stay
valid?

- Semantic (role + accessible name + stable id) or positional (coordinates)?
- Does it survive a re-render, a scroll, a layout change, a rotation?
- **What does a finding cite so a human can re-find the element?** Positional
  identifiers must never be the citation — pair them with a label and a
  screenshot.

### 2 · Log temporality

Answer: is log/console capture retrospective (read after acting) or prospective
(must be armed before acting)?

The skill defines `inspect` as **arm → act → collect**. A retrospective driver
no-ops the arm step. A prospective driver *requires* it, and silently returns
nothing otherwise — which reads as a clean run and is not one.

Also note: what clears the buffer, and any silence timeout.

### 3 · Wait

Answer: is there a wait primitive?

- If yes, name it, and note whether network inspection is also available — the
  two together are what lets a finding distinguish *slow* from *broken*.
- If no, define the polling idiom and require the wait budget to be recorded in
  any "no response" finding.

## Driver-only capabilities

List what this driver can do that the core loop does not assume, and what it
cannot do that other drivers can. Each becomes an optional, probe-gated charter
— never a core step, or the skill stops being portable.

## Capture conventions

- What to capture before and after a finding-producing action.
- How to write evidence to a stable path the session sheet can cite (the
  validator checks the path exists).
- Anything this driver captures that others cannot (recordings, crash reports,
  traces).
