# ADR 0003 — One ordered rewriter chain for agent Bash commands

**Status:** Accepted (2026-09-23)

## Context

Two things in this configuration want to rewrite the shell commands an agent
runs before they execute:

- `rtk` rewrites them to save tokens (`git status` → `rtk git status`), through a
  `PreToolUse` hook on the `Bash` matcher.
- The process cap (`dot-emacs-k6c`) wraps them in a transient systemd scope with
  a runtime limit, so a hang is killed instead of surviving its session.

The obvious shape — each module registering its own `PreToolUse` hook — does not
work. The Claude Code hooks documentation states that "All matching hooks run in
parallel", and says nothing about what happens when two of them return
`hookSpecificOutput.updatedInput`. Two independent rewriters of the same command
therefore race, and one of the two rewrites is lost nondeterministically. A cap
that applies to nine commands in ten is not a cap.

A second problem surfaced while designing the cap. Any rewrite moves a command's
first token off position 0: `git commit -m x` becomes `rtk git commit -m x`, and
a capped command becomes `agent-process-cap run fg <base64>`. This repository
sets `permissions.ask` rules like `Bash(git commit:*)` precisely to give the
`CLAUDE.md` git rule teeth. The documentation says PreToolUse hooks "run before
the permission prompt" and that "Claude Code evaluates deny and ask rules
regardless of what a PreToolUse hook returns", but never states whether those
rules are matched against the original input or against a hook's `updatedInput`.
Establishing which would require triggering real permission prompts.

Note that this exposure predates the cap: `rtk hook check "git commit -m x"`
already yields `rtk git commit -m x` today.

## Decision

**One `PreToolUse` hook on the `Bash` matcher, running an ordered chain of
stages.** Modules register a stage in `agents.bashRewriters` with an `order` and
an `executable`; no module adds a Bash `PreToolUse` hook of its own.
`workstation/agents/default.nix` sorts by order and renders the single hook.

- `rtk` is the stage at order 50.
- The process cap is the stage at order 90, asserted to be last, because it
  consumes the final command text into a base64 payload.
- Equal orders are an evaluation error: they would reintroduce exactly the
  nondeterminism this decision removes.

**The chain re-asserts the sensitive command prefixes itself.** It matches the
**original** command text against `agents.sensitiveBashPrefixes` and returns
`permissionDecision: "ask"` when one hits. That list is also what renders the
harness's own `permissions.ask` Bash rules, so there is one definition. The
outcome is then the same whichever input the harness matches its rules against;
the worst case is one prompt instead of a silently weakened rule.

**Stages are pure text transformations.** A stage reads the payload on stdin and
prints either nothing (no change) or a `hookSpecificOutput` carrying
`updatedInput`. Empty output means unchanged — the convention `rtk` already
uses. A stage must not execute the command, touch the filesystem, or depend on
the working directory.

**The chain fails open.** A stage that exits non-zero, prints nothing, or prints
output without an `updatedInput` leaves the command text as it was. The chain
always exits 0, because exit 2 from a `PreToolUse` hook blocks the tool call:
breaking every Bash command is a worse outage than any leak it would prevent.

## Consequences

- Adding a rewriter is now a two-line contribution to `agents.bashRewriters`,
  and its position relative to every other rewriter is explicit and asserted.
- The order is a real constraint, not a preference. A stage placed after the cap
  would rewrite text that is already inside the base64 payload and would have no
  effect on what runs.
- Rewritten sensitive commands keep prompting regardless of how the harness
  matches its rules, which also closes the pre-existing `rtk` exposure.
- The chain is one more process per Bash call. Measured cost is milliseconds
  against a documented 600 s hook timeout.
- The stage contract is ours, not upstream's. If Claude Code ever documents
  deterministic composition of parallel `updatedInput` hooks, this indirection
  could be dropped — but not before, and the stage contract would still be the
  cheaper way to order two rewrites.
