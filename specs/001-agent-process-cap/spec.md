# Feature Specification: Agent Process Runtime Cap

**Feature Branch**: `001-agent-process-cap`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "dot-emacs-k6c — Cap runaway agent-spawned processes with systemd-run --scope RuntimeMaxSec"

## Clarifications

### Session 2026-09-23

- Q: Which agent tools must the runtime cap cover — only Claude Code's shell tool, or every AI agent harness this repo configures? → A: Claude Code Bash tool only; other harnesses explicitly out of scope.
- Q: When the cap fires, must the kill be recorded durably on the machine, or is the agent-visible result enough? → A: Durable record per kill, naming the overrun command, timestamp and which allowance was exceeded.
- Q: At the allowance, must a command get a chance to shut down cleanly before being killed outright? → A: Graceful termination request first, then a hard kill after a short grace period.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A hung agent command dies on its own (Priority: P1)

The Claude Code agent runs a shell command on the workstation. The command hangs —
an infinite loop, a daemon that never exits, a read that never returns. The
agent session later ends or is killed. Without anyone noticing, the command and
its children keep running and keep consuming CPU. With this feature, the machine
terminates that command and every process it started once a configured runtime
limit is reached, whether or not the session that launched it still exists.

**Why this priority**: This is the entire reason the feature exists. Three
orphans from dead sessions were found on the work laptop, two of them pinning a
full core each for over five days — roughly 40–50 W of continuous waste heat,
package temperature at 80 °C and fans at ~3180 RPM while the machine looked
idle. Killing them by hand dropped the machine to 57 °C and ~2525 RPM.

**Independent Test**: Start a command that never terminates through the agent's
shell tool, kill the launching session, wait past the cap, and confirm nothing
from that command remains on the machine.

**Acceptance Scenarios**:

1. **Given** an agent-launched command that never exits, **When** the runtime cap elapses, **Then** the command is asked to stop, and after a short grace period it and all of its descendants are gone, with no process from it remaining.
2. **Given** such a command whose launching session has already been force-killed and whose processes have been re-parented away from it, **When** the cap elapses, **Then** those processes are still terminated.
3. **Given** a command that is terminated by the cap, **When** the agent reads the result, **Then** the output identifies the runtime cap as the cause rather than presenting an unexplained failure.

---

### User Story 2 - Legitimate long work still finishes (Priority: P1)

The same workstation regularly runs commands that are slow but entirely
legitimate: a full system build, a flake evaluation, a VM-based test. These must
complete untouched. Work the agent deliberately detaches to run in the
background is expected to run longer than foreground work and gets a
correspondingly longer allowance.

**Why this priority**: A cap that kills real work is worse than the leak it
fixes — it would be disabled within a day. The feature is only adoptable if its
limits are invisible during normal use.

**Independent Test**: Run the repository's slowest legitimate build through the
agent's shell tool with the cap active and confirm it completes normally with
its usual output and exit status.

**Acceptance Scenarios**:

1. **Given** a full system build that takes many minutes, **When** it is run through the agent's shell tool, **Then** it completes normally and is not interrupted.
2. **Given** a command the agent starts as background work, **When** it runs longer than the foreground allowance but under the background allowance, **Then** it is not interrupted.
3. **Given** any command that completes on its own, **When** its result is compared against the same command run without the cap, **Then** standard output, standard error, exit status, working directory and consumed standard input are identical.

---

### User Story 3 - An operator can opt a command out and tune the limits (Priority: P2)

Occasionally a command must be allowed to outlive the cap — starting a long-term
daemon on purpose, for example. The person configuring the machine can mark such
an invocation as exempt, and can set the limits themselves per machine.

**Why this priority**: An escape hatch keeps the default strict. Without one,
the pressure is to raise the cap for everyone or switch it off; with one, the
default can stay aggressive because a rare exception has a documented answer.

**Independent Test**: Run one command with the exemption marker and one without,
and confirm only the unmarked one is subject to the cap while both otherwise
behave identically.

**Acceptance Scenarios**:

1. **Given** a command carrying the explicit exemption marker, **When** it runs, **Then** it is not capped and the marker itself does not reach the command.
2. **Given** a machine that sets different limits from the default, **When** a command runs on it, **Then** the machine's own limits apply.
3. **Given** a configured limit that is nonsensical (zero, negative, or a foreground allowance above the background allowance), **When** the configuration is evaluated, **Then** evaluation fails with a message naming the file and the fix.

---

### Edge Cases

- **Launcher already dead.** The process that started the command is killed and its children are re-parented to the init process. They must still be reaped at the cap.
- **Deliberate background work.** Work the agent detaches on purpose must not be killed at the foreground allowance.
- **Commands that change shell state.** A command whose purpose is to alter the calling shell's own state — changing directory, exporting a variable, sourcing a file — must keep having that effect, because the agent persists the working directory between calls.
- **Commands containing shell variables.** A command mentioning `$VAR` or `$$` must reach the shell byte-for-byte as written; the capping layer must not expand or rewrite it.
- **Capping mechanism unavailable.** On a host where the mechanism is missing, commands must run uncapped rather than fail. A layer that breaks every command is worse than the leak.
- **Termination noise.** A command killed at the cap must not have the shell's own signal-death chatter mixed into the command's captured output.
- **A command that ignores the stop request.** A wedged process that does not react to a graceful stop must still be gone when the grace period ends.
- **Interaction with existing command rewriting.** Another rewriting step already runs on the same commands. Two independent rewriters of the same input would race, with a nondeterministic winner; the outcome must be deterministic and both effects must survive.
- **Deliberately started daemons.** A daemon started by an agent is capped like anything else unless explicitly exempted — the process that caused this issue was itself a long-lived daemon.
- **Leftover bookkeeping.** Terminating a command must leave no residual system bookkeeping (stale units, non-empty accounting groups) behind.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every shell command the Claude Code agent runs on the workstation through its shell tool MUST be subject to a maximum runtime, after which it is terminated. Other agent harnesses configured in this repository are out of scope.
- **FR-002**: Termination MUST cover the command and every process it started, including processes whose parent has already exited and which have been re-parented to the init process.
- **FR-002a**: Termination MUST begin with a graceful stop request, giving the command a short, bounded grace period to release locks and remove partial output, followed by an unconditional hard kill of anything still alive when the grace period ends.
- **FR-003**: Commands the agent runs in the background MUST get their own, longer allowance, distinct from the foreground allowance.
- **FR-004**: A capped command that completes on its own MUST be indistinguishable from the same command run uncapped: identical standard output, standard error, exit status, resulting working directory, and standard-input consumption.
- **FR-005**: A command terminated by the cap MUST report a result that identifies the cap as the cause.
- **FR-005a**: Every capped termination MUST additionally be recorded durably on the machine, naming the command that overran, the time, and which allowance it exceeded, so kills remain auditable after the session that caused them is gone.
- **FR-006**: Users MUST be able to exempt an individual command from the cap with an explicit marker on that invocation; the marker MUST NOT reach the command itself.
- **FR-007**: The system MUST fall back to running commands uncapped when the capping mechanism is unavailable on the host.
- **FR-008**: A command's effect on shell state MUST be no different capped than uncapped. Measured during implementation: with this harness there is no difference to preserve — it resets the working directory to the project root after every call and carries no environment variables between calls, so no command can alter the caller's persistent state whether it is capped or not. Within a single command, statements still share one shell. Propagating an inner `cd` back to the caller is impossible from a child process and is tracked as `dot-emacs-2d2` against the day a harness version persists the directory.
- **FR-009**: The command text MUST reach the shell exactly as the agent wrote it, with no variable expansion or substitution introduced by the capping layer.
- **FR-010**: The cap MUST compose deterministically with the existing command-rewriting step, in a defined order, so that both effects always apply and neither can win a race.
- **FR-011**: Both allowances MUST be configurable per machine as typed configuration values, with nonsensical values rejected at configuration-evaluation time.
- **FR-012**: Long-lived daemons started by an agent MUST be capped like any other command; no automatic exemption may be inferred from what the command looks like.
- **FR-013**: Terminating a command MUST leave no residual system bookkeeping behind.
- **FR-014**: ~~The feature MUST carry a regression test that fails if capping, transparency, or reaping of a re-parented process regresses.~~ **Withdrawn on the owner's instruction during implementation** ("remove the tests after verifying it works"). Every behaviour above was verified once, on the real built artifacts, and the verification harness was then discarded. The durable guard is evaluation-level instead: six assertions plus `shellcheck` on both shell components, which is the other branch Constitution Principle III allows. A regression in the runtime behaviour will not be caught automatically.

### Key Entities

- **Capped command**: a single shell invocation made by an agent, together with the process tree it creates; the unit that is timed and, if it overruns, terminated as a whole.
- **Cap policy**: the configured limits for a machine — a foreground allowance, a longer background allowance, and the exemption marker that bypasses both.
- **Kill record**: the durable per-termination entry — command text, time, allowance exceeded — that makes cap firings auditable and reveals whether an allowance is set too tight.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A command that never exits is gone no later than one minute past its allowance — grace period included — in 100% of trials, including trials where the launching session was force-killed first.
- **SC-002**: Seven days after deployment, no agent-started process on the machine is older than its allowance, and every kill in that window is retrievable from the machine's own records with the command that caused it.
- **SC-003**: The repository's routine verification run (measured baseline: 45 s) and a full system build complete without interruption, and the foreground allowance is at least twice the slowest observed legitimate foreground command.
- **SC-004**: Across a battery of at least 15 representative shell constructs, output is byte-identical with the cap active and with it disabled.
- **SC-005**: With no work running, package temperature and fan speed return to the machine's idle baseline of approximately 57 °C and 2525 RPM, down from the 80 °C / 3180 RPM observed with orphans present.
- **SC-006**: After a capped termination, zero residual system bookkeeping entries remain for that command.
- **SC-007**: An operator can exempt one command from the cap using a single documented marker, with no configuration change and no restart.

## Assumptions

- Only the NixOS workstations in this repository are in scope; the three machines share one configuration and one cap policy unless a machine overrides it.
- Only the Claude Code agent's shell tool is capped. Every orphan observed so far came from it, and it is the only harness with an established interception point. Other agent harnesses are out of scope for this feature; extending the cap to one is separate work, justified by an observed leak there.
- Default allowances are 3600 s for foreground commands and 14400 s for background commands. These target processes that live for days, not commands that are merely slow. The full-system-build measurement that confirms the 2× headroom in SC-003 is outstanding.
- The agent's own command timeout is not a substitute: on timeout it moves the command to a background task rather than killing it, which is how the observed orphans survived.
- Reaping is enforced by the operating system's own process supervision, not by the launching session, since the launching session is exactly what disappears in the failure case.
- A per-invocation time limit is already an accepted pattern in this repository (an existing editor integration guards its call with a 25 s timeout); this feature generalises it to arbitrary agent-spawned commands.
- No durable automated test ships with this feature, at the owner's instruction. Verification was a one-off against the built helper, stage and chain: an 18-case transparency battery with the cap on and off, a hung command at a temporarily lowered cap, a re-parented orphan, the opt-out, the fail-open path, and the journal record. Re-verifying after a change means redoing that by hand.
- Kill records land in the machine's own system log, readable by the machine's administrator. Command text may contain file paths and arguments; this is acceptable because these are single-user workstations and the same text is already visible in agent transcripts.
- The decision about how the cap composes with the existing command-rewriting step has lasting consequences and is recorded as an architecture decision record.
