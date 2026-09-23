# Phase 0 Research: Agent Process Runtime Cap

**Feature**: `001-agent-process-cap` | **Date**: 2026-09-23

All findings below were re-verified on `work-laptop` during this planning session
(systemd 261.2, NixOS). The earlier round of this work was lost before it was
committed, so nothing here is carried over on trust.

## R1. Enforcement mechanism: transient systemd scope

**Decision**: wrap each command in `systemd-run --user --scope --expand-environment=no
-p RuntimeMaxSec=<cap> -p TimeoutStopSec=<grace> --description=<tag> -- bash -c '<command>'`.

**Rationale**: the runtime limit is enforced by the user's `systemd` manager, not
by the launching process, which is exactly what the failure mode requires — the
launcher is the thing that disappears. Verified:

- `RuntimeMaxSec=3` + `TimeoutStopSec=2` on a command that traps and ignores
  `SIGTERM`: elapsed 5.51 s, exit status 137. `SIGTERM` at the cap, `SIGKILL`
  at the end of the grace period. This is FR-002a, measured.
- Launcher killed with `SIGKILL` 0.5 s after start, child re-parented: the
  scope stayed `active` with `Until: … 2s left`, then ended `failed` with
  `result 'timeout'`, cgroup emptied, no stray processes. This is FR-002 and
  SC-001, measured.
- Overhead: 20 wrapped no-ops took 0.181 s versus 0.104 s unwrapped — about
  4 ms per command.

**Alternatives considered**:

- `timeout(1)` wrapper — rejected: `timeout` is itself part of the process tree
  that dies when the session is killed, so it cannot reap the exact case that
  caused this issue.
- Periodic reaper unit scanning for old processes under `/tmp/claude-1000/` —
  rejected as the primary mechanism: it only cleans up after the fact, needs a
  heuristic for "too old", and cannot distinguish a wanted long build from an
  orphan. The scope's own accounting knows both facts exactly.
- Claude Code's built-in Bash timeout — rejected, and it is the root cause of
  the observed leak: on timeout it moves the command to a background task
  rather than killing it. That is how three orphans survived for days.

## R2. `--expand-environment=no` is mandatory

**Decision**: always pass `--expand-environment=no`.

**Rationale**: verified corruption without it. `systemd-run --user --scope --
bash -c 'echo "[$FOO] pid=$$"'` printed `[hello] pid=$` — `systemd-run` expanded
`$FOO` itself and collapsed `$$` to a literal `$`. With the flag: `[hello]
pid=341826`, correct. Any command mentioning a shell variable is silently
mangled without it (FR-009).

## R3. Transparency of the wrapper

**Decision**: the wrapper is transparent for every observable the harness uses.

Verified individually, with the flag from R2 in place:

| Observable | Result |
|---|---|
| stdin | `printf 'line1\nline2\n' \| …wc -l` → `2` |
| exit status | `exit 7` → `exit=7` |
| stdout/stderr separation | `echo OUT; echo ERR >&2` → streams stayed separate |
| working directory | `cd /tmp && … pwd -P` → `/tmp` (inside one command) |

One known contaminant: when the scope is killed, the launching shell prints its
own signal notice (`Terminated   sleep 0.2`) on **its** stderr, which lands
inside the command's captured stderr. Keep the real stderr on a spare fd and
restore it, so only the command's own output reaches the harness (FR-004).

## R4. Shell state: only the working directory matters, and it is cheap to keep

**Decision**: wrap every command — no pass-through list for `cd`/`export`/`source`
— and propagate the inner shell's final working directory back to the outer
shell after the scope exits.

**Rationale**: measured in this session across two consecutive Bash calls.
`export CAPTEST_X=persisted; cd /tmp` in one call, then `echo "[$CAPTEST_X]";
pwd -P` in the next, produced `[]` and `/home/oskar/projects/dot-emacs`. This
harness version persists neither environment variables nor the working directory
between calls; it captures `pwd -P` after the command (visible in a captured
process command line: `… && pwd -P >| /tmp/claude-35c8-cwd`) and then resets the
directory to the project root, reporting `Shell cwd was reset to …`.

Propagating the inner directory anyway costs three statements and makes the
wrapper correct on harness versions that *do* persist it. This supersedes the
earlier design's exemption list, which was a real hole: `cd repo && ./hang`
starts with `cd` and would have escaped the cap entirely (FR-008 is satisfied by
propagation instead of by exemption).

**Alternatives considered**: exempt commands whose first top-level token is a
shell builtin — rejected as above, leaky and unnecessary.

## R5. Durable kill records

**Decision**: carry the command text in the scope's `--description` with a fixed
`claude-cap` tag and the allowance that applies, and read kills back out of the
journal.

**Rationale**: verified journal output for a capped command:

```
Started [systemd-run] …/bash -c "while true; do sleep 0.3; done".
captest-341958.scope: Scope reached runtime time limit. Stopping.
captest-341958.scope: Failed with result 'timeout'.
```

The command text is already in the `Started` line and the timeout is already
distinguishable by `result 'timeout'`, both under the same unit, with
timestamps. Setting the description to `claude-cap <fg|bg> <cap>s: <command>`
adds the one missing fact — which allowance applied — and gives a single stable
grep target (FR-005a, SC-002). No extra logging daemon, no log file to rotate.

**Alternatives considered**: a separate log file under `$XDG_STATE_HOME` —
rejected, duplicates what the journal already records and adds rotation; a
metrics counter — deferred, the journal answers "was the cap too tight" without
it.

## R6. Composition with the existing `rtk` rewriter

**Decision**: one `PreToolUse` Bash hook that runs an ordered chain of rewriter
stages, declared through a new typed option. `rtk` becomes a stage in that chain
rather than its own hook.

**Rationale**: the Claude Code hooks documentation states plainly that "All
matching hooks run in parallel", and does not define what happens when two
hooks both return `hookSpecificOutput.updatedInput`. Two independent rewriting
hooks would therefore race with an undefined winner, and one of the two rewrites
would be lost nondeterministically. A single hook running stages in a declared
order is deterministic by construction (FR-010). Because this constrains how any
future rewriter is added, it is recorded as an ADR.

Verified `rtk`'s stage contract by feeding it hook payloads directly:

- Rewrites: `{"command":"git status","description":"x"}` →
  `{"hookSpecificOutput":{…,"updatedInput":{"command":"rtk git status","description":"x"}}}`.
- No rewrite: empty stdout, exit 0 (`sleep 5`, `echo hi`). Empty output means
  "unchanged", not failure.
- Unknown fields survive a rewrite: `run_in_background` and `timeout` were
  echoed back untouched, so `updatedInput` can be treated as the whole
  `tool_input` without losing fields.

Hook timeout is not a constraint: the documented default for `command` hooks is
600 s, and the chain's own work is milliseconds.

## R7. Foreground and background allowances

**Decision**: 3600 s foreground, 14400 s background, both typed options with
assertions. `run_in_background` is read from the hook payload to pick the
allowance.

**Rationale**: `run_in_background: true` appears in real Bash payloads in this
project's own transcripts (8 occurrences), and is absent otherwise, so the hook
can select the allowance with `.tool_input.run_in_background // false` (FR-003).

The target is processes that live for *days*, so the allowance only has to sit
above the slowest legitimate command, not close to it.

**Open measurement, deliberately not blocking**: a cold full-system toplevel
build has still not been timed. `nix build --dry-run
'.#nixosConfigurations.work-laptop.config.system.build.toplevel'` reports
nothing to build on this machine, so the number is not obtainable without
forcing a rebuild of a large closure, which costs more than the answer is worth.
Instead the risk is monitored: R5 makes every kill auditable, so a legitimate
build killed at 3600 s shows up in the journal with its command text, and the
allowance is raised then. The `nocap` opt-out (FR-006) covers a known-long
command in the meantime.

**Alternatives considered**: a single allowance for both — rejected, either it is
too tight for deliberate background work or too loose to matter for foreground
hangs; deriving the cap from the harness's own `timeout` field — rejected, that
field is the harness's soft timeout and is frequently absent.

## R8. Fail-open behaviour

**Decision**: if `systemd-run` is unavailable, the user bus is unreachable, or
the chain errors for any reason, emit the command unchanged.

**Rationale**: a hook that breaks every Bash call is a worse outage than the
leak it prevents, and the hook runs on every command the agent issues (FR-007).
The `rtk` stage is treated the same way: nonzero exit or unparseable output
means "keep the previous command text".

## R8a. `--collect` is required, or every kill leaks a failed unit

**Decision**: pass `--collect` to `systemd-run`.

**Rationale**: a scope killed by its runtime limit ends in `failed` state and
stays **loaded** until someone runs `systemctl --user reset-failed`. Two such
units were found lingering during this session — one from this session's own
tests and one from the earlier, lost round of this work
(`captest19665.scope`, `sleep 999`), which is direct evidence that they
accumulate unattended. With `--collect`, the unit is garbage-collected as soon
as it fails: verified, `capcollect-test.scope` was absent from
`systemctl --user list-units --type=scope --all` one second after the kill,
while the journal kept the full record:

```
Started claude-cap fg 2s: sleep 30.
capcollect-test.scope: Scope reached runtime time limit. Stopping.
capcollect-test.scope: Failed with result 'timeout'.
```

This is FR-013 and SC-006, and it also confirms R5's description format end to
end — the tag, the mode, the allowance and the command text all appear in the
`Started` line.

**Alternatives considered**: a periodic `systemctl --user reset-failed` timer —
rejected, it is cleanup of a mess that `--collect` prevents at the source.

## R9. Permission rules versus command rewriting (found during planning)

**Decision**: the chain runner re-asserts the repository's own sensitive-command
patterns itself, on the **original** command text, and returns
`permissionDecision: "ask"` when one matches. The pattern list is derived from
the same Nix value that produces
`programs.claude-code.settings.permissions.ask`, so there is one source of
truth.

**Rationale**: wrapping a command necessarily moves its first token away from
position 0, so a prefix rule such as `Bash(git commit:*)` no longer matches the
text that will run. The documentation says "PreToolUse hooks run before the
permission prompt" and that "Claude Code evaluates deny and ask rules regardless
of what a PreToolUse hook returns", but does not state whether those rules are
matched against the original input or against a hook's `updatedInput`. Probing
the difference requires triggering real permission prompts, which is not worth
interrupting the user for.

Re-asserting in the hook makes the outcome correct under either ordering: a
hook-returned `ask` prompts, and a matching ask rule prompts too, so the worst
case is one prompt rather than a silently weakened rule.

This also closes a pre-existing hole the same analysis exposed: `rtk` already
rewrites sensitive commands today — `rtk hook check "git commit -m x"` yields
`rtk git commit -m x`, and `git push` likewise — so the ask rules that
`workstation/agents/default.nix` adds to "give the CLAUDE.md git rule teeth"
depend on that same undocumented ordering right now.

**Alternatives considered**:

- Skip capping any command that matches a sensitive pattern — rejected: it makes
  the cap's coverage depend on an unrelated list, and `sudo nixos-rebuild` is
  exactly the kind of long command worth capping.
- Set the cap out of band with `BASH_ENV`, leaving the command text untouched —
  rejected for now: it needs a transient scope to adopt an already-running
  process over D-Bus, it fires for every nested non-interactive `bash` in the
  session including ones inside builds, and none of it is verified. Kept as the
  fallback if re-asserting the patterns proves unworkable.

## R10. Command text is passed as base64, not re-quoted

**Decision**: the rewritten command is
`agent-process-cap run <fg|bg> <base64 of the original command>`, and the helper
decodes it and hands it to `bash -c` inside the scope.

**Rationale**: the harness embeds the command in `eval '<command>'` — visible in
a captured process command line from this session — so any single quote the
wrapper introduces would break the call. base64 output is alphanumeric plus
`+/=`, which is safe inside both quoting styles, needs no escaping analysis, and
has no temp file to create, clean up, or race on. The original text is still
recoverable for humans from the scope description (R5) and from the hook's
`permissionDecisionReason`.

**Alternatives considered**: write the command to a temp file and pass the path —
rejected, adds cleanup and a TOCTOU window; escape quotes in place — rejected,
this is the class of bug that silently corrupts one command in a hundred.

## R11. Baseline timings on this machine

- `nix flake check`: 47.09 s (measured this session, exit 0). Earlier recorded
  baseline was 45.13 s, so the SC-003 reference number holds.
- `nix build --dry-run '.#nixosConfigurations.work-laptop.config.system.build.toplevel'`:
  nothing to build — the closure is cached, which is why the cold-build figure
  in R7 stays open.


## R12. Nothing may be appended to the command text (found during implementation)

**Decision**: hand the command to the inner shell as `bash -c "$command"` and
append nothing to it.

**Rationale**: the first implementation appended bookkeeping —
`; __cap_rc=$?; pwd -P >"$0"; exit $__cap_rc` — to capture the inner working
directory. The transparency battery caught it immediately: a command ending in
a heredoc read the appended line as part of the heredoc body.

```
uncapped stdout: heredoc body
capped   stdout: heredoc body
                 EOF; __cap_rc=0; pwd -P >"/tmp/tmp.cWZhjDdsVQ" 2>/dev/null; exit
capped   stderr: warning: here-document at line 1 delimited by end-of-file (wanted `EOF')
```

A trailing comment would swallow the append entirely, and a trailing backslash
continuation would join it to the last line. Passing the command as an argument
and `eval`-ing it avoids the parse problem but does not help the directory
anyway (R13), so the append was removed outright. With it gone the battery is
clean across all 18 constructs.

## R13. The inner working directory cannot be propagated (corrects R4)

**Decision**: do not try. A `cd` inside a capped command moves the scope's
shell only.

**Rationale**: R4 proposed writing the inner `$PWD` to a temp file and having
"the outer shell" restore it. The outer shell here is the helper, which is a
*child* of the harness's shell — and a child cannot change its parent's working
directory. The helper's own `cd` dies with the helper.

It costs nothing today, for the reason R4 did measure correctly: this harness
resets the directory to the project root after every call and persists no
environment variables, so no command alters the caller's state capped or not.
Restoring it would require the *stage* to emit a compound command that runs
`cd` in the caller's own shell, which is tracked as `dot-emacs-2d2` rather than
built pre-emptively.

## R14. Verified behaviour of the shipped artifacts

Run against the built `agent-process-cap`, `agent-process-cap-stage` and
`agent-bash-rewriter-chain`, not against hand-written equivalents.

| Check | Result |
|---|---|
| Chain, non-Bash payload | no output, exit 0 |
| Chain, garbage stdin | no output, exit 0 |
| Chain, plain command | wrapped `… run fg bml4IGJ1aWxkIC4jZm9v` |
| Chain, stage order | `git status` → payload decodes to `rtk git status`, so rtk ran first and the cap wrapped its output |
| Chain, `git commit -m x` | `permissionDecision: "ask"`, reason names the prefix `git commit` |
| Chain, `rm -rf /tmp/zzz` | `ask`, reason names `rm -rf` |
| Chain, `run_in_background: true` | mode `bg` |
| Chain, `nocap emacs --daemon=scratch` | `emacs --daemon=scratch`, unwrapped, token stripped |
| Chain, unknown fields | `description`, `run_in_background`, `timeout` all preserved |
| Helper, transparency battery | 18 constructs, 0 mismatches in stdout, stderr and exit status |
| Helper, bad arguments | exit 64 with a usage line |
| Helper, no user bus | command runs uncapped, exit 0 |
| Helper, journal | `Started claude-cap fg 3600s: echo journal-check.` |
| Helper, hung command honouring SIGTERM | exit 143 at 60 s (cap temporarily lowered), `[process-cap]` marker printed, no shell signal notice in the output |
| Helper, command ignoring SIGTERM | exit 137 at 63 s — the grace period then the hard kill |
