# Implementation Plan: Agent Process Runtime Cap

**Branch**: `001-agent-process-cap` | **Date**: 2026-09-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-agent-process-cap/spec.md`

## Summary

Every Bash command Claude Code runs on these workstations is rewritten by a
single `PreToolUse` hook into a transient systemd scope carrying a runtime
limit, so a command that hangs is terminated by the user's systemd manager —
`SIGTERM` at the limit, `SIGKILL` after a grace period — whether or not the
session that launched it still exists. The hook is one ordered chain rather than
a second rewriting hook, because Claude Code runs matching hooks in parallel and
two rewriters would race. `rtk` becomes a stage in that chain; the cap is the
last stage. The chain re-asserts this repository's sensitive-command patterns on
the pre-rewrite text so wrapping cannot weaken an ask rule, and passes the
command to the scope as base64 so no quoting can corrupt it.

## Technical Context

**Language/Version**: Nix (nixpkgs unstable, flakes), POSIX shell via
`pkgs.writeShellApplication`, `jq` for hook JSON

**Primary Dependencies**: `systemd` 261.2 (`systemd-run --user --scope`,
`RuntimeMaxSec`, `TimeoutStopSec`), `home-manager`
(`programs.claude-code.settings.hooks`), `pkgs.rtk`, `pkgs.jq`

**Storage**: none. Kill records live in the existing user journal; cap policy is
Nix configuration

**Testing**: `nix flake check` (evaluation + `shellcheck` via
`writeShellApplication`), new `packages.test-process-cap` NixOS VM test, plus a
transparency battery script run inside that test

**Target Platform**: NixOS, x86_64-linux, `systemd --user` session; the three
machines in `machines/machines.nix`

**Project Type**: single-repo NixOS/home-manager configuration; new feature
module under `workstation/agents/`

**Performance Goals**: wrapper overhead ≤ 10 ms per command (measured 4 ms);
hook chain well under the 600 s `command`-hook default timeout

**Constraints**: fail open — any failure in the chain must yield the original
command; byte-identical stdout/stderr/exit status/cwd versus uncapped; no single
quotes in the rewritten command, because the harness embeds it in `eval '…'`

**Scale/Scope**: one hook on the Bash matcher, two rewriter stages, two typed
allowances, three machines, one agent harness (Claude Code only, per the
clarification session)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Verdict |
|---|---|---|
| I. Evaluation-time verification | Allowances, grace period and opt-out token declared as narrow `mkOption` types; ordering of rewriter stages typed; assertions for cap ordering and non-empty sensitive-pattern list; all shell built via `writeShellApplication` so `shellcheck` runs at build time; executables referenced with `lib.getExe` | PASS — see Phase 1 contracts; six assertions listed in `contracts/nix-options.md` |
| II. Determinism and reproducibility | No new external sources; nothing read from ambient state at evaluation time; cap values are data in the module, per-machine overrides go through `machines/<hostname>/config.nix`; new files `git add`ed before building | PASS |
| III. Fast default gate, heavy tests opt-in | `nix flake check` gains only evaluation-level work; the VM test is exposed as `packages.test-process-cap` with a comment naming the command and when to run it; the feature is a fix for a bug evaluation could not have caught, so it ships with that targeted regression test as Principle III requires | PASS |
| IV. Single source of truth | Sensitive-command patterns are defined once and feed both `permissions.ask` and the chain's guard; cap policy lives only in `process-cap.nix`; the chain-composition decision is recorded as ADR 0003; `CONTEXT.md` gains the new domain terms; `AGENTS.md` and `CLAUDE.md` updated together | PASS |
| V. Toggleable modules, declarative machines | `agents.processCap.enable` with all config under `mkIf`; disabled state contributes no packages, no hook stage and no assertions; no module reaches into another module's internals — `rtk.nix` and `process-cap.nix` both only contribute to the declared `agents.bashRewriters` option | PASS |

Post-design re-check: see [Post-Design Constitution Re-Check](#post-design-constitution-re-check).

## Project Structure

### Documentation (this feature)

```text
specs/001-agent-process-cap/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output — R1..R11, all verified this session
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── hook-chain.md    # PreToolUse chain runner and stage contract
│   ├── process-cap-cli.md  # agent-process-cap command-line contract
│   └── nix-options.md   # Typed options, defaults, assertions
└── checklists/
    └── requirements.md  # Spec quality checklist (16/16)
```

### Source Code (repository root)

```text
workstation/agents/
├── default.nix               # + agents.bashRewriters option; builds the single
│                             #   PreToolUse Bash hook from the ordered chain
├── rtk.nix                   # hook entry replaced by a chain stage at order 50
├── process-cap.nix           # NEW — cap module: options, assertions, stage at order 90
├── process-cap-docs.md       # NEW — agent-facing doc: the cap and the nocap opt-out
└── agents-global.md          # unchanged

scripts/
└── process-cap-battery.sh    # NEW — transparency battery, wrapped by writeShellApplication

tests/
└── process-cap.nix           # NEW — NixOS VM test (cap fires, orphan reaped, battery, journal)

docs/adr/
└── 0003-agent-bash-rewriter-chain.md  # NEW — one ordered chain, not parallel hooks

flake.nix                     # + packages.test-process-cap
CONTEXT.md                    # + rewriter chain, cap policy, kill record terms
AGENTS.md, CLAUDE.md          # + the cap and the nocap opt-out, mirrored
```

**Structure Decision**: this repository has no `src/`; features are
home-manager/NixOS modules. The cap is a new module under `workstation/agents/`
alongside the other agent integrations, contributing to a new option in
`workstation/agents/default.nix` exactly as `rtk.nix` and `caveman.nix` already
contribute to `agents.tools`. The heavy test goes under `tests/` and is exposed
through `flake.nix` as a `packages.*` attribute, matching `test-disk-layout` and
`test-emacs-sops-save`.

## Implementation Shape

Three pieces, in dependency order.

1. **`agents.bashRewriters`** (in `workstation/agents/default.nix`) — an
   attribute set of named stages, each with an `order` (int) and an
   `executable` (package). `default.nix` sorts by order, renders one
   `PreToolUse` hook on the `Bash` matcher whose command is the chain runner,
   and passes the sorted stage list to it. Replaces the per-tool
   `hooks.PreToolUse` Bash entries.

2. **Chain runner** — a `writeShellApplication` that reads the hook payload,
   snapshots the original command, pipes the payload through each stage in
   order, and prints one `hookSpecificOutput` with the final `updatedInput`. It
   attaches `permissionDecision: "ask"` when the original command matches a
   sensitive pattern (R9), and prints nothing at all when no stage changed
   anything or when any step fails (R8).

3. **Cap stage and helper** (in `workstation/agents/process-cap.nix`) — the
   stage picks the allowance from `.tool_input.run_in_background`, honours the
   `nocap` opt-out by stripping the token and skipping the wrap, and emits
   `agent-process-cap run <fg|bg> <base64>`. The helper runs the decoded command
   inside `systemd-run --user --scope --collect --expand-environment=no` with
   `RuntimeMaxSec`, `TimeoutStopSec` and a `claude-cap <fg|bg> <cap>s: <command>`
   description, keeps the real stderr on fd 3 so the shell's signal notice never
   reaches the captured output, restores the inner working directory, and exits
   with the command's own status.

Ordering matters: `rtk` at 50 rewrites `git status` to `rtk git status`, the cap
at 90 wraps whatever text survives the earlier stages. Reversing them would cap
the pre-rtk command and lose the rewrite.

## Open Risk

The cold full-system build time is still unmeasured (R7, R11): the closure is
cached on this machine, so the number cannot be had cheaply. The 3600 s
foreground allowance is therefore a judgement, not a measurement. It is
monitored rather than assumed — every kill is journal-visible with its command
text (R5), so a legitimate build killed at the cap is identifiable after the
fact and the allowance is raised then. `nocap` covers a known-long command in
the meantime.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| A rewriter *chain* option rather than each tool registering its own `PreToolUse` hook | Claude Code runs matching hooks in parallel and does not define which `updatedInput` wins, so two rewriting hooks race nondeterministically (R6) | One hook per tool is simpler but loses one of the two rewrites at random; recorded as ADR 0003 |
| The chain re-asserts sensitive-command patterns itself | Wrapping moves the command's first token off position 0, and whether ask rules are matched before or after a hook's rewrite is undocumented (R9) | Trusting the harness's own matcher is simpler but would silently weaken `Bash(git commit:*)` and friends — and that hole already exists today through `rtk` |
| base64 payload instead of the readable wrapped command | The harness embeds the command in `eval '…'`, so an introduced single quote breaks the call (R10) | In-place quote escaping is simpler and is precisely the class of bug that corrupts one command in a hundred |

## Post-Design Constitution Re-Check

- **I**: every value the design introduces is a typed option with an assertion
  where evaluation cannot infer the constraint (`contracts/nix-options.md`);
  both shell components are `writeShellApplication`, so `shellcheck` gates them
  in `nix flake check`. PASS
- **II**: no new inputs, no ambient reads, no per-machine manual steps. PASS
- **III**: `checks.*` unchanged in character; the VM test is a `packages.*`
  attribute with a usage comment. PASS
- **IV**: the sensitive-pattern list feeds both `permissions.ask` and the guard
  from one definition; ADR 0003 records the chain decision; documentation parity
  is an explicit task. PASS
- **V**: `agents.processCap.enable` gates everything, including the stage
  contribution, so a machine with it off gets an unchanged hook chain. PASS

No principle is violated; the three entries in Complexity Tracking are
justified departures from the *simplest* shape, each with an ADR or a measured
reason, not departures from a principle.
