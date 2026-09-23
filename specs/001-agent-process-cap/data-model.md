# Phase 1 Data Model: Agent Process Runtime Cap

**Feature**: `001-agent-process-cap` | **Date**: 2026-09-23

This feature stores nothing. The "data" is a hook payload in flight, a
Nix-declared policy, and journal entries. Each entity below is described by the
fields the implementation actually reads or writes.

## Capped command

One Bash tool call, together with the process tree it creates. Created when the
hook fires, gone when the scope exits.

| Field | Source | Type | Notes |
|---|---|---|---|
| `original` | `.tool_input.command` from the hook payload | string | Never modified; used for the guard match and the journal description |
| `rewritten` | chain output | string | `agent-process-cap run <fg\|bg> <base64>`, or `original` unchanged when a stage declines |
| `background` | `.tool_input.run_in_background // false` | bool | Selects which allowance applies (FR-003) |
| `allowance` | derived | seconds | `foregroundSeconds` or `backgroundSeconds` |
| `optedOut` | leading opt-out token on `original` | bool | Token is stripped before execution (FR-006) |
| `scopeUnit` | `systemd-run` | transient unit name | Basis for journal lookup |
| `status` | scope result | enum | See state transitions below |

### State transitions

```text
                     ┌─ opted out ──────────────────► passthrough (uncapped)
                     │
payload ─► guard ─► stages ─► wrapped ─► running ─┬─► completed          (own exit status)
                     │                            ├─► terminated-graceful (SIGTERM honoured, 143)
                     │                            └─► terminated-hard     (grace elapsed, 137)
                     │
                     └─ chain failure / systemd-run absent ─► passthrough (uncapped, FR-007)
```

`running → terminated-graceful` happens at `allowance`;
`terminated-graceful → terminated-hard` at `allowance + graceSeconds`.
Both were measured in R1: exit 137 after 5.51 s for `RuntimeMaxSec=3`,
`TimeoutStopSec=2` with `SIGTERM` trapped and ignored.

### Validation rules

- `original` is read as an opaque byte string. No expansion, no requoting, no
  parsing beyond the opt-out token check (FR-009).
- A command is wrapped at most once. The helper is never itself wrapped: the
  cap stage declines when `original` already begins with the helper's own name.
- `passthrough` is the outcome of every error path. There is no state in which
  the chain refuses to run a command.

## Cap policy

Per-machine Nix configuration. One instance per host, all of it typed
(Principle I); see `contracts/nix-options.md` for the option declarations.

| Field | Type | Default | Constraint |
|---|---|---|---|
| `enable` | bool | `true` | Off contributes no stage, no package, no assertion |
| `foregroundSeconds` | `ints.positive` | 3600 | Must be ≥ 60 and ≤ `backgroundSeconds` |
| `backgroundSeconds` | `ints.positive` | 14400 | Must be ≥ `foregroundSeconds` |
| `graceSeconds` | `ints.positive` | 10 | Must be ≥ 1 and < `foregroundSeconds` |
| `optOutToken` | `strMatching "[a-z][a-z0-9-]*"` | `nocap` | Single lowercase word, matched as a leading token followed by a space |
| `sensitivePatterns` | `listOf str` | derived from the `permissions.ask` Bash rules | Must be non-empty while `enable` is true (R9) |

## Rewriter stage

An entry in `agents.bashRewriters`. Ordered, named, and contributed by whichever
module owns it.

| Field | Type | Notes |
|---|---|---|
| `name` | attribute name | `rtk`, `processCap` |
| `order` | `ints.between 0 100` | `rtk` = 50, cap = 90; the cap must run last so it wraps the final text |
| `executable` | package | Invoked with the payload on stdin; empty stdout means "unchanged" |

Two stages may not share an `order` — asserted, because equal orders reintroduce
exactly the nondeterminism ADR 0003 exists to remove.

## Kill record

A journal entry, not a file. Written by systemd; read back by a human or by the
acceptance checks.

| Field | Where it comes from | Example |
|---|---|---|
| timestamp | journal | `2026-09-23T14:32:31+02:00` |
| unit | scope name | `captest-341958.scope` |
| command and allowance | scope `--description` | `claude-cap fg 3600s: nix build .#…` |
| outcome | systemd message | `Scope reached runtime time limit. Stopping.` then `Failed with result 'timeout'` |

Retention and rotation are the journal's existing behaviour; this feature adds
no rotation of its own. Lookup is by the fixed `claude-cap` tag in the
description (FR-005a, SC-002).
