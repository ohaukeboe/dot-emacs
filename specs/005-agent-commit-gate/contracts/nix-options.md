# Contract: `agents.commitGate` options

Declared in `workstation/agents/commit-gate.nix`, which replaces `commit-guard.nix`.

| Option | Type | Default | Meaning |
|---|---|---|---|
| `enable` | bool | `true` | Gate on. When it is off, the static ask rule and the plain re-assertion still apply (today's behaviour minus the staging guard) |
| `mainCheckout` | enum `ask` `emacs` `deny` | `"ask"` | Default mode for commits that are not in an agent worktree |
| `claudeWorktrees` | enum `gated` `free` | `"gated"` | Whether commits in an agent worktree skip the gate |
| `emacsTimeout` | `ints.between 30 3000` | `1200` | Seconds the gate waits for a review |

The override file is not an option. Its path is fixed at
`${config.xdg.stateHome}/agent-commit-gate/override.json`, matching what the
gate and Emacs compute at runtime (see emacs-review.md).

## What it renders

- `agents.tools.commit-gate.packages = [ agent-commit-gate ]`, plus the gate
  executable that the chain calls by its store path.
- `programs.claude-code.settings.permissions.deny` gets
  `Edit(<override path>)` and `Write(<override path>)`.
- The chain hook entry in `default.nix` gets
  `timeout = emacsTimeout + 60`, and `onFailure = "block"` when the
  Claude Code package version is ≥ 2.1.295.
- `agents-global.md` text, or a per-tool doc, describing the behaviour (FR-020).

## Assertions

1. `enable → elem "git commit" agents.sensitiveBashPrefixes`. The static
   rule is the fail-safe (D2).
2. `enable → agents.bashRewriters != {}`. The gate runs inside the chain, and
   without stages the chain hook isn't rendered. Message: either make the
   chain hook render unconditionally when the gate is enabled, or name the
   missing stage.
3. `emacsTimeout + 60 ≤` the hook ceiling, if Claude Code documents one.
   Otherwise drop this assertion.
