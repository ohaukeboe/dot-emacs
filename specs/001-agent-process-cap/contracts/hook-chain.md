# Contract: PreToolUse Bash rewriter chain

**Feature**: `001-agent-process-cap` | **Consumers**: Claude Code hook system,
`rtk`, the cap stage

## Chain runner

Invoked as the single `PreToolUse` hook command for the `Bash` matcher.

**Input** (stdin): the Claude Code `PreToolUse` payload. Fields read:

| Path | Type | Required |
|---|---|---|
| `.tool_name` | string | yes — the runner exits silently unless it is `Bash` |
| `.tool_input.command` | string | yes |
| `.tool_input.run_in_background` | bool | no, defaults to `false` |

**Output** (stdout): either nothing, or exactly one JSON object:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecisionReason": "<human-readable summary of what changed>",
    "updatedInput": { "...": "the whole tool_input, with command replaced" }
  }
}
```

- Empty stdout means "no change"; this is the same convention `rtk` already
  uses (verified: `sleep 5` and `echo hi` produce no output, exit 0).
- `updatedInput` carries the complete `tool_input`. Fields the runner does not
  understand are passed through untouched — verified for `run_in_background`
  and `timeout`.
- `permissionDecision: "ask"` is added when the **original** command matches one
  of `sensitivePatterns`, with the matched pattern named in
  `permissionDecisionReason`.

**Exit status**: always 0. A non-zero exit from a `PreToolUse` hook has meanings
this feature must not invoke (exit 2 blocks the call), so every failure path
prints nothing and exits 0 — fail open (FR-007).

## Stage contract

Each stage is an executable invoked once per command, in ascending `order`.

- **stdin**: the current payload — the original for the first stage, and for
  each later stage the payload with `.tool_input` replaced by the previous
  stage's `updatedInput`.
- **stdout**: empty (no change), or one object of the same shape as above; only
  `hookSpecificOutput.updatedInput` is consumed from it.
- **exit status**: 0 for success. Any non-zero exit, unparseable output, or
  output missing `updatedInput` is treated as "no change" — the chain keeps the
  previous text and continues (FR-007).
- **timeout**: stages must return in well under a second. The documented
  default timeout for a `command` hook is 600 s, so there is no practical limit
  to design against.

Stages must be pure text transformations of the command. A stage must not
execute the command, must not touch the filesystem, and must not depend on the
working directory.

### Registered stages

| Order | Stage | Effect |
|---|---|---|
| 50 | `rtk` | `${pkgs.rtk}/bin/rtk hook claude` — token-saving command rewrites |
| 90 | `processCap` | Wraps the surviving text in the cap helper invocation |

The cap must hold the highest order: it consumes the final command text, so any
stage after it would rewrite text that is already inside the wrapper payload.
Asserted at evaluation time.
