# Charters, personas and severity

## What a charter is

One mission, written down before the run, testable in one sitting:

```
Explore <area>
with <resources / persona constraint>
to discover <what kind of information>
```

Example:

```
Explore the signup-to-first-project flow
with a signed-out first-run persona on a throttled network
to discover where the user loses track of what happens next.
```

Keep sessions short — roughly 45–90 minutes of equivalent work, softly. One
charter per session sheet. A charter that grows a second goal mid-run is two
charters: close the sheet, open another.

## Charter library

Run at least two per feature, and **always pair a happy path with an error
path**. A single happy-path run is the one thing agents do well on their own,
and it is where the fewest real problems live.

### Happy path

The task the feature exists for, done the intended way. Yields: missing
feedback, unclear labels, steps that need knowledge the UI never gave.

### Error / adversarial

Deliberately wrong input and hostile sequencing. Yields the largest share of
real findings.

- Empty required fields; whitespace only; maximum-length and over-length input
- Wrong format (email without `@`, letters in a number field, emoji, RTL text)
- Wrong credentials, expired token, already-registered email
- Double-submit; rapid repeat taps; submit while a request is in flight
- Back / browser-back / hardware-back out of a half-finished flow, then re-enter
- Cancel at each step and check what was already persisted

For each: is the message specific, does it say how to fix it, does it keep what
the user typed, and can they recover without starting over?

### Accessibility

A **heuristic probe**, not accessibility testing with disabled people. Label it
as such in the report, every time.

- Every interactive element has a name and the right role
- Focus order follows reading order; focus is visible; no keyboard trap
- Largest font / 200% zoom: does anything clip, overlap, or become unreachable
- Touch targets reachable one-handed; nothing depends on hover alone
- Nothing depends on color alone to carry meaning
- On web, the a11y snapshot *is* evidence; on mobile, an unlabelled control is
  the finding

### First run

Fresh install or fully signed-out, no seeded data, no permissions granted.

- Empty states: do they say what to do, or just say "nothing here"
- Permission prompts: is the reason given before the OS dialog appears
- Onboarding: can it be skipped, and is the app usable if it was
- What breaks if the user denies a permission

### Interrupted state

The real-world condition most flows are never tested against.

- Background the app mid-flow, return a minute later
- Kill and relaunch mid-flow: is the draft still there
- Rotate, or resize the viewport, mid-flow
- Lose the network mid-request; restore it
- Follow a deep link straight into the middle of a flow

### Returning user

Existing account with existing data. Yields: stale data, wrong counts, state
that does not match what the last session left behind, migration and
long-list behaviour.

## Personas

A persona varies what is **observable**, not backstory. Two sentences is
enough; the constraint is the whole point, because the constraint changes what
the UI has to do.

| Axis | Constraint |
| --- | --- |
| Input | screen reader, keyboard only, one-handed, large font, 200% zoom |
| Network | throttled, flaky, offline mid-request |
| Account | signed-out, first-run, returning with data, expired session |
| Device | small screen, low-end, rotated, wrong locale or RTL |
| Context | interrupted, in a hurry, resuming a day later |

Run the same charter under two different personas before writing a third
charter — the constraint usually surfaces more than the new goal would.

Do **not** write persona backstory as if it predicted behaviour. It does not.
See `evidence.md`.

## Severity

Usability findings, on frequency × impact × persistence:

| Rating | Meaning |
| --- | --- |
| `0` | Not a usability problem |
| `1` | Cosmetic — fix only if time allows |
| `2` | Minor — low priority |
| `3` | Major — important, high priority |
| `4` | Catastrophe — must fix before release |

Rate the *problem*, not your confidence in it. Confidence is carried by the
evidence gate: a finding that cannot cite a resolvable artifact does not get a
severity, because it does not get reported.

Functional defects carry a repro instead of a rating: driver, device or
viewport, entry point, numbered steps, expected, actual, artifact paths.

## Paths not taken

Every session sheet ends with the branches seen and not taken — the dialogs not
opened, the links not followed, the inputs not tried. This is a required
section, not a courtesy: the default failure of an agent-run session is narrow
coverage that reads as thorough.
