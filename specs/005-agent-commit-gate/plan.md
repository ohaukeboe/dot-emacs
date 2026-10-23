# Implementation Plan: Agent Commit Gate

**Branch**: `005-agent-commit-gate` | **Date**: 2026-10-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-agent-commit-gate/spec.md`

## Summary

Replace the `commit-guard` hook with a commit gate that runs inside the
existing Bash rewriter chain. It decides each `git commit` according to three
things:

- a mode: `ask`, `emacs` or `deny`, from the env var, then the Emacs-written
  override file, then the Nix default;
- a worktree setting: `free` or `gated`, applied only to worktrees Claude
  created;
- the existing staging guard.

In `emacs` mode the gate runs unsandboxed and opens a Magit commit buffer
through `emacsclient`, prefilled with the agent's message next to the staged
diff. Emacs runs the commit itself, and the gate returns `deny` with a reason
that tells the agent the outcome. The static `Bash(git commit:*)` ask rule
stays as the fail-safe. Decisions and evidence are in [research.md](research.md).

## Technical Context

**Language/Version**: Nix (home-manager module), Python 3 (`writePython3Bin`, the same as today's commit-guard), Bash (the chain, `writeShellApplication`), Emacs Lisp (literate, `config.org`)

**Primary Dependencies**: Claude Code 2.1.289 (hooks), git ≥ 2.55, Magit 20261005, with-editor 20261003, `emacsclient`

**Storage**: Files only. The override is JSON under `$XDG_STATE_HOME`, and per-request directories live under `$XDG_RUNTIME_DIR`

**Testing**: `checks.agent-commit-gate` (Python `unittest` against fixture repositories); opt-in `packages.test-agent-commit-review` (Emacs batch with Magit); manual scenarios in [quickstart.md](quickstart.md)

**Target Platform**: NixOS workstations (x13-laptop, work-laptop, desktop), with the user's Emacs server running

**Project Type**: Home-manager feature module, plus an Emacs config section

**Performance Goals**: The gate adds less than 100 ms to non-commit Bash calls (it is invoked only for `git commit` segments). Reaching the Emacs buffer takes under 1 s

**Constraints**: The gate must never fail open (FR-019). There must be no second Bash PreToolUse hook that returns `updatedInput` (ADR 0003). The sandbox must stay unchanged, with no Emacs socket exposed (ADR 0004)

**Scale/Scope**: One user and three machines. About 1–3 commit requests at once (the main session plus background agents)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How |
|---|---|---|
| I. Evaluation-time verification | ✅ | Enum and int options with the narrowest types. Assertions keep `"git commit"` in the sensitive prefixes and require the chain to exist. `onFailure` is gated on `lib.versionAtLeast`. The gate is a `writePython3Bin` (flake8 at build time). The chain change stays in `writeShellApplication`. Executables are referenced with `lib.getExe` |
| II. Determinism | ✅ | No `getEnv` at evaluation. The env var and override file are read at runtime by the gate only. The override path comes from `config.xdg.stateHome` |
| III. Fast gate, heavy tests opt-in | ✅ | The Python unit tests are a cheap check. The Emacs and Magit test is `packages.*` with a run-command comment |
| IV. Single source of truth | ✅ | The Emacs code lives in `config.org`. A new ADR 0006 amends ADR 0003 (chain owns the commit decision; rules match `updatedInput`) and ADR 0004 (an unsandboxed hook reaches Emacs). GLOSSARY gains "commit gate" and "agent worktree" |
| V. Toggleable modules | ✅ | `agents.commitGate.enable` follows the same `agents.tools.<name>` pattern as commit-guard. When it's off, the module contributes nothing beyond what the core chain already does |
| Docs parity | ✅ | `agents-global.md` is updated (FR-020). The CLAUDE.md "Global" line about the commit hook stays true; check AGENTS.md mirrors it |

Post-design re-check: still passes. No violations, so Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/005-agent-commit-gate/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── nix-options.md
│   ├── gate-cli.md
│   └── emacs-review.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
workstation/agents/
├── commit-gate.nix        # NEW: options, gate package, deny rules, docs (replaces commit-guard.nix)
├── commit-gate.py         # NEW: commit-guard.py parser + mode/worktree/Emacs decision
├── commit-guard.nix       # REMOVED
├── commit-guard.py        # REMOVED (folded into commit-gate.py)
├── default.nix            # chain: call gate on commit segments; skip generic re-assert for them; hook timeout/onFailure; import
└── agents-global.md       # commit rules updated (FR-020)

workstation/emacs/packages/agent-commit-gate{,-test}.el  # review + override commands, ERT suite
workstation/emacs/config.org   # "Agent commit review" section: use-package with autoloads

tests/
├── agent-commit-gate.nix         # NEW check: unittest + fixture repos
├── agent-commit-gate_test.py     # NEW
└── agent-commit-review.nix       # NEW packages.test-agent-commit-review (Emacs batch + Magit)

flake.nix                  # register the check and the opt-in package
docs/adr/0006-agent-commit-gate.md   # NEW
GLOSSARY.md                # new terms
```

**Structure Decision**: Follow the existing `workstation/agents/<tool>.nix`
plus helper-script pattern. Tests go under `tests/`, wired in through
`flake.nix` the same way as `expiring-override` (the check) and
`test-emacs-sops-save` (the opt-in package).

## Implementation order (for /speckit-tasks)

1. Move the commit-guard parser into `commit-gate.py`, with the `decide` modes
   `ask` and `deny` and no Emacs yet. Add the chain integration, the
   assertions and the unit tests. This is the MVP for Story 2 and keeps
   today's behaviour as the default.
2. Worktree classification and `claudeWorktrees` (Story 3) and its unit tests.
3. The Emacs review: the elisp, the gate's `emacs` branch, timeouts, stale
   request handling and the opt-in test (Story 1).
4. ADR 0006, GLOSSARY, `agents-global.md`, then the manual quickstart Q1–Q12.

## Complexity Tracking

None.
