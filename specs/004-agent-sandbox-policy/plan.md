# Implementation Plan: Agent Sandbox Policy

**Branch**: `004-agent-sandbox-policy` (spec directory; work is on `main` until you branch) | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-agent-sandbox-policy/spec.md`

## Summary

Turn Claude Code's built-in sandbox back on, with a Nix-generated baseline
that fixes what made it unusable before. Allow all Unix sockets so the Nix
daemon and a signing agent work, then mask the dangerous sockets and the
credential paths by path. The masks are credential denies, which no project
scope can remove. Strict mode removes the unconfined retry. Ask rules on the
project settings files turn every policy change the agent proposes into a
diff the user approves, even in auto mode. Commits are signed through a second
ssh-agent that holds only a signing-only key. The session D-Bus, which carries
the keyring, is hidden, and `agent-process-cap` moves to the user manager's
private socket. An `agent-sandbox-probe` command, generated from the same
option values, is the runtime check for every protection.

## Technical Context

**Language/Version**: Nix (nixpkgs unstable, flakes), Home Manager module.
POSIX shell via `pkgs.writeShellApplication`.

**Primary Dependencies**: Claude Code built-in sandbox (bubblewrap + socat on
Linux), `home-manager` `programs.claude-code.settings`, `sops-nix`, `openssh`
(`ssh-agent`, `ssh-keygen -Y sign`), `systemd --user`.

**Storage**: Baseline in `~/.claude/settings.json` (Nix store symlink).
Project policy in `<project>/.claude/settings.local.json`. Signing key in
`sops/home/secrets.yaml`.

**Testing**: `nix flake check` (typed options, assertions A1 to A5,
shellcheck). The `agent-sandbox-probe` runtime check is run by the agent per
the quickstart. No VM test (see Complexity Tracking).

**Target Platform**: NixOS x86_64-linux, the three machines in
`machines/machines.nix`. Home Manager on all of them.

**Project Type**: Single-repo NixOS/Home Manager configuration. New module in
`workstation/agents/`.

**Performance Goals**: No measurable per-command overhead beyond bubblewrap
startup (tens of ms). Probe run under 60 s, dominated by `nix-shell -p hello`.

**Constraints**: Must not break Nix (FR-007), signing (FR-019), process-cap
(FR-026), Emacs integration, or remote control. No literal username in module
code (constitution IV). Linux socket rules are all-or-nothing (research R2).

**Scale/Scope**: One module, about 12 credential paths, about 10 hidden
sockets, 4 related file edits, 1 new user service, 1 probe script, 1 ADR.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Verdict |
|---|---|---|
| I. Evaluation-time verification | Every value is a narrow `mkOption` (`strMatching` for paths, keys, socket names, env names). Assertions A1 to A5 cover the invariants evaluation can see: no hiding the daemon, manager or signing socket; bus hidden when process-cap is on; sops secret defined; `~/.ssh` denied; ControlPath not in `/tmp`. Probe and agent service are built with `writeShellApplication` and `lib.getExe`. | PASS |
| II. Determinism | No new external sources. `runtimeDir` is an option with a default, overridable per machine. No ambient reads at evaluation. | PASS |
| III. Fast gate, heavy tests opt-in | Only evaluation work goes into `checks`. The runtime check is a probe command, not a check. No VM test, justified below. | PASS with justification |
| IV. Single source of truth | One list generates the sandbox denies, the Read denies and the probe rows. `sensitiveBashPrefixes` stays the single ask list. ADR `0004-agent-sandbox-policy.md` records the threat model and the choice of built-in sandbox over a whole-process wrapper. `CONTEXT.md` gains the terms *sandbox baseline*, *project policy*, *policy proposal* and *agent signing key*. Any `AGENTS.md` or `CLAUDE.md` edit is mirrored. | PASS |
| V. Toggleable modules | `agents.sandbox.enable` with all config under `mkIf`. When disabled it contributes nothing, and the default `sandbox.enabled = false` stays. Reads only `agents.processCap.enable` and `config.sops.secrets`, through declared options. | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/004-agent-sandbox-policy/
├── plan.md              # This file
├── spec.md
├── research.md          # R1..R14
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── nix-options.md
│   ├── project-policy.md
│   └── probe-cli.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
workstation/agents/
├── sandbox.nix          # NEW: agents.sandbox options, settings rendering, assertions, probe
├── default.nix          # import sandbox.nix; drop `sandbox.enabled = false`
├── process-cap.nix      # fail-open check accepts systemd/private
└── agents-global.md     # "## Sandbox" agent guidance
workstation/ssh.nix      # ControlPath ~/.ssh/cm-%C; ssh-agent-sign user service
workstation/sops.nix     # "ssh/agent-signing" secret
sops/home/secrets.yaml   # new key (manual, via sops)
docs/adr/0004-agent-sandbox-policy.md   # NEW
CONTEXT.md               # new terms under "Agents"
```

**Structure Decision**: The new module follows the existing per-concern
pattern in `workstation/agents/` (`process-cap.nix`, `memory-cap.nix`), with
`agents.<name>` options and an import in `default.nix`. The signing agent
lives in `ssh.nix` next to the main agent. The sandbox module only consumes
its socket name and public key.

## Phase 0 / Phase 1 outputs

- [research.md](./research.md): no open unknowns. Five items are marked
  **validate**, each with a fallback chosen in advance: socket masking (R3),
  missing paths (R3), signing through the agent inside the sandbox (R6), live
  reload for non-filesystem keys (R8), and `/dev/kvm` (R10).
- [data-model.md](./data-model.md), [contracts/](./contracts/),
  [quickstart.md](./quickstart.md).

## Post-Design Constitution Re-Check

- I: assertions A1 to A5 are in `contracts/nix-options.md`. The probe covers
  what evaluation cannot (runtime masking). PASS.
- II: the signing public key is data in the module, and the private key is in
  sops. PASS.
- III: unchanged. PASS with justification.
- IV: one list feeds three consumers (sandbox denies, Read denies, probe
  rows). PASS.
- V: the disabled module renders no `sandbox`, `env` or permission entries,
  and adds no service, because the signing service is gated on
  `agents.sandbox.signing.enable` through an option read in `ssh.nix`. PASS.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| No `packages.test-*` VM regression test (constitution III asks for one when a bug evaluation can't catch is fixed) | The behaviour under test is Claude Code's own sandbox inside an authenticated interactive session. A NixOS VM would need the proprietary binary, network access and an account. | A VM test of bare bubblewrap would test bwrap, not the settings Claude Code renders. The `agent-sandbox-probe` command is generated from the same options and run in the real session. That is the targeted regression check, and the quickstart makes running it a step of every rollout. |
| `allowAllUnixSockets = true` widens the sandbox's default | The Nix daemon and the signing agent are Unix sockets, and Linux has no per-path allowlist (R2). | Blocking all sockets breaks FR-007 and FR-019, which is the failure that disabled the sandbox before. |
