# Session sheet — <charter slug>

## CHARTER

Explore <area>
with <persona / resources>
to discover <what kind of information>.

## DRIVER

- driver: <chrome-devtools-mcp | mobile-mcp | …>
- tools bound: observe=`<tool>` act=`<tool>,…` capture=`<tool>` inspect=`<tool>`
- target: <url | app package/bundle id>
- device: <viewport WxH | device model + OS version>
- capability notes: <probe-gated extras available, e.g. emulate, crash reports>
- leak handling: <how element identity, log temporality and waits were handled>

## PERSONA

<Two sentences. State the constraint, not a backstory.>

## TESTER

<agent/model identifier> · run by <user>

## START

<yyyy-mm-dd HH:MM TZ> · duration <N> min

## TASK BREAKDOWN

- test design and execution: <N>%
- bug investigation and reporting: <N>%
- session setup: <N>%
- charter vs opportunity: <N>% / <N>%

## DATA FILES

Every artifact captured this session, one per line, as a path the validator can
resolve:

- `artifacts/<slug>/01-before.png`
- `artifacts/<slug>/01-snapshot.txt`
- `artifacts/<slug>/02-console.log`

## TEST NOTES

Numbered trajectory. One line per step: intent, element acted on by label and
role, expected, actual.

1. …
2. …

Anything that failed the evidence gate goes here as a note, not as a finding.
Say why it failed: "logs not captured", "could not re-trigger", "possible
mis-tap".

## ISSUES

Problems with the *test session* itself — blocked paths, missing access, driver
limitations, anything that made the testing worse. Not product defects.

- …

## BUGS

One block per finding. `evidence:` is required and every path in it must
resolve, or the validator fails the sheet.

### <short title>

- kind: usability | functional | accessibility
- severity: 0–4 (usability) — see references/charters.md
- persona: <the constraint under which it appeared>
- element: <accessible name + role> (web: plus `uid` from the snapshot)
- steps:
  1. …
  2. …
- expected: …
- actual: …
- not-execution-error: <how a mis-tap was ruled out — the deliberate redo, the
  snapshot showing the action landed>
- wait budget: <only for "no observable change" findings>
- evidence: `artifacts/<slug>/01-before.png`, `artifacts/<slug>/01-after.png`

## PATHS NOT TAKEN

Branches seen and not followed. Required — this is where the coverage gap is
declared rather than hidden.

- …

## PROOF

- **Past** — what happened during the session.
- **Results** — what was achieved, by finding title.
- **Obstacles** — what got in the way of good testing.
- **Outlook** — charters still to run, paths still to take.
- **Feelings** — how the persona experienced it. **Not evidence.** The only
  subjective line in the sheet, and it is labelled as such.

## STANDING

These findings are falsifiable hypotheses about the artifact, produced by an
agent driving the app. They are a first-pass screen and need human confirmation.
They are not evidence about how any real person or group experiences this
product. <If applicable: this run is a heuristic probe, not accessibility
testing with disabled people.>
