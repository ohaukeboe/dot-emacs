# Contract: `agent-process-cap` helper

**Feature**: `001-agent-process-cap` | **Consumers**: the cap rewriter stage
(indirectly, the agent's shell)

## Invocation

```text
agent-process-cap run <fg|bg> <base64-command>
```

| Argument | Meaning |
|---|---|
| `run` | The only subcommand. Reserved word, so a future `explain` or `check` can be added without ambiguity |
| `fg` \| `bg` | Which allowance applies, decided by the stage from `run_in_background` |
| `base64-command` | The original command text, base64-encoded. Alphanumeric plus `+/=` only, so it survives the harness's `eval '…'` (R10) |

Wrong argument count, an unknown mode, or undecodable base64: print a one-line
diagnostic on stderr and exit 64. This is a bug in the stage, not in the user's
command, and must be loud rather than silent.

## Behaviour

1. Decode the payload.
2. If `systemd-run` is not executable or the user bus is unreachable, run the
   command directly with `bash -c` and exit with its status — uncapped
   (FR-007).
3. Otherwise run:

   ```text
   systemd-run --user --scope -q --collect --expand-environment=no \
     --description="claude-cap <mode> <allowance>s: <command>" \
     -p RuntimeMaxSec=<allowance> -p TimeoutStopSec=<grace> \
     -- bash -c "<decoded command>"
   ```

   Nothing may be appended to the command text (R12): a trailing heredoc reads
   an appended line as part of its body, and a trailing comment swallows it.
   ```

   `--expand-environment=no` is mandatory: without it `$VAR` is expanded by
   `systemd-run` and `$$` collapses to a literal `$` (verified, R2).
   `--collect` is mandatory too: without it every killed scope stays loaded in
   `failed` state and they accumulate (verified, R8a).

4. Exit with the command's own status.

## Guarantees

| Observable | Guarantee | Verified by |
|---|---|---|
| stdout | Byte-identical to uncapped | R3, battery in `quickstart.md` |
| stderr | Byte-identical to uncapped. The launching shell's own signal notice (`Terminated  …`) is kept off it by holding the real stderr on fd 3 | R3 |
| exit status | The command's own; `143` when the command honours `SIGTERM` at the cap, `137` when the grace period elapses | R1 |
| stdin | Passed through unchanged | R3 |
| working directory | The command starts in the caller's directory, and statements within one command share a shell. An inner `cd` does **not** move the caller — impossible from a child process, and moot with this harness, which resets the directory every call (R13) | R3, R13 |
| overhead | ≤ 10 ms per command (measured 4 ms) | R1 |

## Opt-out

The opt-out is handled by the **stage**, not by this helper: a command whose
first token is the configured opt-out token (default `nocap`) has that token
stripped and is emitted unwrapped, so the helper never sees it. The helper has
no flag to disable capping — there must be exactly one way to opt out (FR-006).

## Journal contract

Each capped command produces, under its own transient unit:

- `Started claude-cap <mode> <allowance>s: <command>.` on start.
- On overrun: `Scope reached runtime time limit. Stopping.` followed by
  `Failed with result 'timeout'.`
- No unit left behind afterwards: `--collect` removes it while the journal keeps
  the record (FR-013, SC-006).

Kills are therefore queryable by the fixed `claude-cap` tag, with the command
text and the allowance that applied both present (FR-005a). Verified against
real journal output in R5.
