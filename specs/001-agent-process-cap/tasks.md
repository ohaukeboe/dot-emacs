---

description: "Task list for Agent Process Runtime Cap"
---

# Tasks: Agent Process Runtime Cap

**Input**: Design documents from `/specs/001-agent-process-cap/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: **Withdrawn during implementation on the owner's instruction**
("remove the tests after verifying it works"). FR-014 is amended in `spec.md`
accordingly. Every behaviour was verified once against the built artifacts with
a throwaway harness — nothing was written into the repository and then deleted,
so no test files, no `scripts/process-cap-battery.sh` and no
`packages.test-process-cap` exist. Constitution Principle III is satisfied
through its other branch: six evaluation assertions plus `shellcheck` on both
shell components. Tasks marked `[~]` were dropped for this reason; the
verification each described was still performed, once, by hand. See
`research.md` R14 for what was checked and what came back.

**Organization**: Grouped by user story. US1 and US3 can ship without US2's
transparency battery, but no story ships before Phase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1, US2, US3 per spec.md
- Exact file paths in every description

## Path Conventions

No `src/`. This is a NixOS + home-manager flake: feature modules under
`workstation/agents/`, heavy tests under `tests/` exposed through `flake.nix`,
loose shell under `scripts/`, decisions under `docs/adr/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Files exist, are tracked, and evaluate — before any behaviour is written

- [X] T001 Create `workstation/agents/process-cap.nix` as an inert module skeleton: `options.agents.processCap.enable = lib.mkEnableOption` with `default = true`, all config under `lib.mkIf cfg.enable`, nothing contributed yet
- [X] T002 Add `./process-cap.nix` to the `imports` list in `workstation/agents/default.nix`
- [~] T003 Create `tests/process-cap.nix` as a NixOS VM test skeleton that passes trivially, following the shape of `tests/emacs-sops-save.nix`
- [~] T004 [P] Add `test-process-cap = nixpkgsFor.${system}.callPackage ./tests/process-cap.nix { };` to the Linux-only `packages` block in `flake.nix` (near line 282), with a comment naming the command `nix build .#test-process-cap -L` and when to run it — matching the existing `test-disk-layout` comment style
- [X] T005 `git add workstation/agents/process-cap.nix tests/process-cap.nix` — the flake sees only git-tracked files, so an untracked file is a build that only works locally
- [X] T006 Run `nix flake check` to confirm the inert skeleton evaluates before any behaviour is added

**Checkpoint**: Tracked, evaluating, and wired into the flake — the cap contributes nothing yet

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The rewriter chain itself. Every user story rides on it.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T007 Declare `agents.bashRewriters` in `workstation/agents/default.nix` exactly as `specs/001-agent-process-cap/contracts/nix-options.md` specifies: `attrsOf (submodule { order = mkOption { type = types.ints.between 0 100; }; executable = mkOption { type = types.package; }; })`, `default = { }`
- [X] T008 Extract the Bash entries of `programs.claude-code.settings.permissions.ask` in `workstation/agents/default.nix` into a single `let` binding, and render both the harness `permissions.ask` list and `agents.processCap.sensitivePatterns` from it — one definition, two consumers (Principle IV)
- [X] T009 Implement the chain runner as a `pkgs.writeShellApplication` in `workstation/agents/default.nix` per `contracts/hook-chain.md`: read the payload from stdin with `jq`, exit silently unless `.tool_name == "Bash"`, pipe the payload through each stage in ascending `order`, print one `hookSpecificOutput` with the final `updatedInput` carrying the complete `tool_input`, print nothing when no stage changed anything
- [X] T010 Make every failure path in the chain runner fail open (FR-007): a non-zero stage exit, unparseable stage output, or output with no `updatedInput` keeps the previous command text; the runner always exits 0, because exit 2 from a `PreToolUse` hook blocks the call
- [X] T011 Add the guard to the chain runner: match the **original** command against `sensitivePatterns` and attach `permissionDecision: "ask"` with the matched pattern named in `permissionDecisionReason` (research.md R9 — wrapping moves the first token off position 0, and the ask-rule matching order is undocumented)
- [X] T012 Render the single `PreToolUse` hook on the `Bash` matcher in `workstation/agents/default.nix` from the order-sorted stage list, invoking the chain runner via `lib.getExe`
- [X] T013 Convert `workstation/agents/rtk.nix` from its own `hooks.PreToolUse` entry to `agents.bashRewriters.rtk = { order = 50; executable = <rtk wrapper>; }`, keeping `${pkgs.rtk}/bin/rtk hook claude` as the stage command and leaving `home.activation.rtkHook` untouched
- [X] T014 Add assertion 5 (every `order` in `agents.bashRewriters` is unique) and assertion 6 (`processCap.order` is the maximum order) in `workstation/agents/default.nix`, each message naming the file and the fix
- [~] T015 [P] Add chain-runner cases to `tests/process-cap.nix`: a non-Bash payload produces no output; an unchanged command produces no output; a stage that exits non-zero leaves the command untouched; unknown `tool_input` fields (`run_in_background`, `timeout`) survive a rewrite
- [~] T016 [P] Add a guard case to `tests/process-cap.nix`: payload `{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}` yields `permissionDecision: "ask"` naming the matched pattern, alongside the rewritten `updatedInput`

**Checkpoint**: One deterministic ordered chain, `rtk` inside it, sensitive commands still prompting — and no cap yet

---

## Phase 3: User Story 1 - A hung agent command dies on its own (Priority: P1) 🎯 MVP

**Goal**: A command that hangs is terminated by systemd at the allowance, whether or not the session that launched it still exists, and the kill is auditable afterwards.

**Independent Test**: Start a never-ending command through the agent's shell tool, kill the launching session, wait past the cap, and confirm nothing from that command remains and the journal names it.

### Tests for User Story 1

- [~] T017 [P] [US1] Add to `tests/process-cap.nix`: a hung command receives `SIGTERM` at `RuntimeMaxSec` and `SIGKILL` after `TimeoutStopSec`, exiting 137 when it traps and ignores `SIGTERM` (research.md R1 measured 5.51 s for a 3 s + 2 s pair)
- [~] T018 [P] [US1] Add to `tests/process-cap.nix`: the launcher is `SIGKILL`ed 0.5 s after start and the child is re-parented to PID 1; the scope stays active until the allowance, then ends with `result 'timeout'`, its cgroup empty and no process surviving
- [~] T019 [P] [US1] Add to `tests/process-cap.nix`: after a kill, `systemctl --user list-units --type=scope --all` lists no unit for it (`--collect`), while `journalctl --user` still holds `Started claude-cap fg <cap>s: <command>`, `Scope reached runtime time limit. Stopping.` and `Failed with result 'timeout'`

### Implementation for User Story 1

- [X] T020 [US1] Declare in `workstation/agents/process-cap.nix`: `foregroundSeconds` as `types.ints.positive` default `3600`, and `graceSeconds` as `types.ints.positive` default `10`
- [X] T021 [US1] Implement the `agent-process-cap` helper as a `pkgs.writeShellApplication` in `workstation/agents/process-cap.nix` per `contracts/process-cap-cli.md`: `run <fg|bg> <base64-command>`, decode the payload, and exec `systemd-run --user --scope -q --collect --expand-environment=no --description="claude-cap <mode> <allowance>s: <command>" -p RuntimeMaxSec=<allowance> -p TimeoutStopSec=<grace> -- bash -c <decoded>`; exit 64 with a one-line stderr diagnostic on a wrong argument count, an unknown mode, or undecodable base64
- [X] T022 [US1] Keep `--expand-environment=no` and `--collect` non-optional in the helper and state why in a comment: without the first, `$VAR` is expanded by `systemd-run` and `$$` collapses to a literal `$` (R2); without the second, every killed scope stays loaded in `failed` state and they accumulate (R8a)
- [X] T023 [US1] Hold the helper's real stderr on fd 3 and restore it around the `systemd-run` call, so the launching shell's own `Terminated  …` signal notice never lands in the command's captured stderr (R3)
- [X] T024 [US1] Implement the cap stage in `workstation/agents/process-cap.nix`: read `.tool_input.command`, emit `updatedInput` with `agent-process-cap run fg <base64 of the command>`, and decline (empty output) when the command already begins with the helper's own name so nothing is wrapped twice
- [X] T025 [US1] Contribute `agents.bashRewriters.processCap = { order = 90; executable = <cap stage>; }` under `mkIf cfg.enable`, so a machine with the cap disabled gets a chain without it and no assertions from it (Principle V)
- [X] T026 [US1] Print a single `[process-cap]` marker line naming the allowance when the helper's command was terminated by the cap, so the agent's result identifies the cap as the cause rather than an unexplained failure (FR-005)

**Checkpoint**: Hangs die on their own, orphans included, and every kill is in the journal with its command text. This alone is the MVP — it is the entire reason the issue was filed.

---

## Phase 4: User Story 2 - Legitimate long work still finishes (Priority: P1)

**Goal**: Slow-but-real commands complete untouched, background work gets its longer allowance, and a capped command that completes is indistinguishable from an uncapped one.

**Independent Test**: Run the repository's slowest legitimate build through the agent's shell tool with the cap active and confirm it completes with its usual output and exit status; run the battery and diff.

### Tests for User Story 2

- [~] T027 [P] [US2] Add to `tests/process-cap.nix`: the transparency battery from T030 runs with the cap on and off and its outputs are byte-identical (SC-004, at least 15 constructs)
- [~] T028 [P] [US2] Add to `tests/process-cap.nix`: `echo "[$FOO] pid=$$"` inside the wrapper prints the real values, not `pid=$` (R2); a payload with `run_in_background: true` selects `backgroundSeconds`; and with `systemd-run` absent from `PATH` the helper still prints the command's output and exits 0 (FR-007)

### Implementation for User Story 2

- [X] T029 [US2] Declare `backgroundSeconds` as `types.ints.positive` default `14400` in `workstation/agents/process-cap.nix`, and add assertion 2 (`backgroundSeconds >= foregroundSeconds` — the reverse ordering is always a typo)
- [X] T030 [US2] Read `.tool_input.run_in_background // false` in the cap stage and emit mode `bg` instead of `fg` when it is true (FR-003; the field appears in real payloads in this project's transcripts and is absent otherwise)
- [~] T031 [US2] ~~Propagate the inner shell's final working directory back to the caller~~ — **impossible as specified**: the helper is a child of the harness's shell, and a child cannot change its parent's directory (research.md R13 corrects R4). Moot with this harness, which resets the directory every call; tracked as `dot-emacs-2d2` against a version that persists it. The command's own exit status *is* propagated
- [X] T032 [US2] Make the helper fail open (FR-007): when `systemd-run` is not executable or the user bus is unreachable, run the decoded command with `bash -c` and exit with its status, uncapped
- [~] T033 [US2] Create `scripts/process-cap-battery.sh` covering at least 15 constructs — pipes, each redirection form, a heredoc, `$VAR`, `$$`, both quoting styles, a subshell, a non-zero exit, a stdin consumer, a multi-statement command, and `cd` followed by a command — each run with the cap on and off, diffing stdout, stderr, exit status and final directory
- [~] T034 [US2] Pull `scripts/process-cap-battery.sh` in through a `pkgs.writeShellApplication` wrapper so `shellcheck` runs on it at build time (Principle I permits a loose `.sh` only under `scripts/` and only when a `writeShellApplication` wrapper pulls it in)
- [~] T035 [US2] **Deferred to `dot-emacs-m5w`** (pre-existing issue, updated to the shipped option names). `nix flake check` re-measured at 47.09 s; the toplevel build has nothing left to build here, so the cold number still cannot be had cheaply. Originally: measure and record the real numbers: `nix flake check` and `nix build '.#nixosConfigurations.work-laptop.config.system.build.toplevel'` with the cap active, and update SC-003 in `spec.md` and R7/R11 in `research.md` with what the slowest foreground command actually took — this is the one open measurement the plan carries

**Checkpoint**: The cap is invisible during normal work. Both P1 stories are now complete.

---

## Phase 5: User Story 3 - An operator can opt a command out and tune the limits (Priority: P2)

**Goal**: A rare command can be exempted with one documented token, and the limits are per-machine typed configuration whose nonsensical values fail evaluation.

**Independent Test**: Run one command with the exemption token and one without, and confirm only the unmarked one is capped while both otherwise behave identically; then violate each limit and watch evaluation fail.

### Tests for User Story 3

- [~] T036 [P] [US3] Add to `tests/process-cap.nix`: a command whose first token is the opt-out token is emitted unwrapped with the token stripped, and the token never reaches the command itself (FR-006)
- [~] T037 [P] [US3] Add to `tests/process-cap.nix`: each of the six assertions in `contracts/nix-options.md` fails evaluation when violated — `foregroundSeconds = 30`, `backgroundSeconds < foregroundSeconds`, `graceSeconds >= foregroundSeconds`, `sensitivePatterns = [ ]`, two stages sharing an `order`, and a stage ordered above the cap. An assertion that does not fire is a missing gate, not a passing test

### Implementation for User Story 3

- [X] T038 [US3] Declare `optOutToken` as `types.strMatching "[a-z][a-z0-9-]*"` default `"nocap"` in `workstation/agents/process-cap.nix`
- [X] T039 [US3] Strip the opt-out token in the cap stage when it is the command's leading token followed by a space, and emit the remainder unwrapped; the helper gets no flag for this, because there must be exactly one way to opt out
- [X] T040 [US3] Add assertions 1, 3 and 4 in `workstation/agents/process-cap.nix`, each naming the file and the fix: `foregroundSeconds >= 60` (a cap under a minute kills ordinary work), `graceSeconds < foregroundSeconds` (a grace period at or above the allowance doubles the effective cap), and `sensitivePatterns != [ ]` while enabled (an empty list silently disables the guard from T011)
- [X] T041 [US3] Write `workstation/agents/process-cap-docs.md` — what the cap is, both allowances, the `nocap` token with an example, and how to read kills out of the journal — and contribute it through `docs.both` so both Claude Code and Opencode contexts carry it
- [X] T042 [US3] Verify a per-machine override works by evaluating one: set `agents.processCap.foregroundSeconds` in `machines/work-laptop/config.nix`, confirm it reaches the rendered helper, then revert unless the machine actually wants a different value

**Checkpoint**: All three stories complete and independently verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T043 [P] Write `docs/adr/0003-agent-bash-rewriter-chain.md`: one ordered chain instead of parallel rewriting hooks, because the documentation states "All matching hooks run in parallel" and leaves the winning `updatedInput` undefined; record the guard decision from R9 and note that a future rewriter joins the chain rather than adding a hook
- [X] T044 [P] Add the new domain terms to `CONTEXT.md`: rewriter chain, rewriter stage, cap policy, capped command, kill record — defined once, as Principle IV requires
- [X] T045 Mirror the same substantive edit into `AGENTS.md` and `CLAUDE.md`: the cap exists, both allowances, the `nocap` opt-out, and the gotcha that a `PreToolUse` Bash hook must join `agents.bashRewriters` rather than register its own hook
- [X] T046 File a beads issue for the pre-existing exposure found during planning: `rtk` rewrites `git commit` and `git push` today, so the `permissions.ask` rules in `workstation/agents/default.nix` already depend on the undocumented matching order; T011's guard covers it for this repository, but the interaction deserves its own tracked verification
- [X] T047 Run `nix fmt`, then revert unrelated reformatting churn — `nix fmt` runs treefmt across the whole tree
- [X] T048 Run `nix flake check` and `nix build '.#nixosConfigurations.work-laptop.config.system.build.toplevel'`; both must pass before deploying
- [~] T049 Run `nix build .#test-process-cap -L` and confirm every case from T015–T019, T027–T028 and T036–T037 passes
- [ ] T050 Deploy with `sudo nixos-rebuild switch --flake .#work-laptop`
- [ ] T051 Observe SC-002 on the live machine after a week: `journalctl --user -g claude-cap --since -7d` lists every kill with its command, and `ps -eo pid,etime,cmd --sort=-etime | head` shows no agent-started process older than its allowance
- [ ] T052 Observe SC-005 on the live machine: at idle, `sensors` shows package temperature and fan back at the baseline of approximately 57 °C and 2525 RPM, against the 80 °C / 3180 RPM seen with orphans present
- [ ] T053 Close `dot-emacs-k6c` only after T051 and T052 hold — the issue's own acceptance criteria require the live observations, not just a passing test

---

## Dependencies

```text
Phase 1 (T001-T006)  ─► Phase 2 (T007-T016) ─┬─► Phase 3 US1 (T017-T026) ─┐
                                             ├─► Phase 4 US2 (T027-T035) ─┼─► Phase 6 (T043-T053)
                                             └─► Phase 5 US3 (T036-T042) ─┘
```

Within Phase 2: T007 blocks T012 and T014; T008 blocks T011; T009 blocks T010, T011 and T012; T012 blocks T013.

Within Phase 3: T020 blocks T021; T021 blocks T022, T023, T024 and T026; T024 blocks T025.

Within Phase 4: T029 blocks T030; T033 blocks T034 and T027.

Within Phase 5: T038 blocks T039.

Cross-story: US2's T030 and US3's T039 both edit the cap stage from T024, so they serialize against each other even though their stories are independent. US2's T035 depends on the cap actually running, so it comes after Phase 3.

In Phase 6: T047 → T048 → T049 → T050 → T051/T052 → T053, in that order. T043, T044 and T046 are independent of all of it.

## Parallel Execution Examples

**Phase 2 tests** — different cases, one file, write them together then run once:

```text
T015  chain-runner cases in tests/process-cap.nix
T016  guard case in tests/process-cap.nix
```

**Phase 3 tests** — all three are independent VM cases:

```text
T017  cap fires, SIGTERM then SIGKILL
T018  orphan reaped after launcher SIGKILL
T019  no leftover unit, journal record present
```

**Phase 6 documentation** — three separate files, no shared state:

```text
T043  docs/adr/0003-agent-bash-rewriter-chain.md
T044  CONTEXT.md
T046  beads issue for the rtk/permissions exposure
```

Note that most implementation tasks are **not** parallel: T009–T014 all edit
`workstation/agents/default.nix`, and T020–T026, T029–T032 and T038–T040 all
edit `workstation/agents/process-cap.nix`.

## Implementation Strategy

**MVP is Phase 1 + Phase 2 + Phase 3 (US1).** That is the whole point of the
issue: a hung command dies on its own, orphans included, with an auditable
record. It is deployable without US2 or US3 — the allowances are already
generous, so the risk it carries alone is a legitimate build being killed at
3600 s, which the journal record makes visible.

**Increment 2 is Phase 4 (US2).** Transparency battery and fail-open turn "it
works" into "it cannot get in the way", and T035 finally puts a measured number
behind the 3600 s choice.

**Increment 3 is Phase 5 (US3).** The escape hatch and the typed limits. Last
because the default policy is already right for all three machines.

**Do not skip T005.** The flake sees only git-tracked files; an untracked module
is a build that works on this machine and nowhere else.

**Do not close the issue at T049.** A passing VM test is not the acceptance
criterion — the live thermal and process observations are.
