# Contract: Emacs side

Implemented as the package `workstation/emacs/packages/agent-commit-gate.el`, with its ERT suite in
`agent-commit-gate-test.el`. It follows the `beads.el` pattern, and is loaded and documented in
`workstation/emacs/config.org` under "Agent commit review" with autoloads. It is a package rather
than inline config so that `packages.test-agent-commit-review` can load it.

## Called by the gate

| Function | Args | Returns | Effect |
|---|---|---|---|
| `agent-commit-gate-review` | `DIR REQ` (strings) | `t` immediately | Opens the Magit commit buffer in `DIR` with `--edit --file=REQ/msg`, shows the staged diff, raises the frame. Writes `REQ/result.json` once git exits |
| `agent-commit-gate-review-cancel` | `REQ` | `t` | Cancels that request's commit buffer (`with-editor-cancel`). No-op if it is gone |

Rules:
- If the repository already has an open agent review, it writes
  `not-committed` "review already open in this repository" and returns.
- The result file is written atomically (temp + rename) and only once.
- Through a buffer-local `with-editor-finish-query-functions` entry, it refuses before a finish (cancels instead, with a message to the user) if
  `gate_pid` from `REQ/request.json` is no longer alive or `deadline` has
  passed. In that case it writes `not-committed` "request expired" (D7).
- The buffer is ordinary `git-commit-mode`, so `C-c C-c`, `C-c C-k`, message
  history and the diff window behave as they do now.

## User commands

| Command | Effect |
|---|---|
| `agent-commit-gate-set` | Prompts for a scope (this repository or `*`) and a mode (`ask` `emacs` `deny` `default`), then writes the override file. `default` removes the key |
| `agent-commit-gate-show` | Echoes the effective mode for the current repository and where it comes from |

The override file path is fixed by convention:
`$XDG_STATE_HOME/agent-commit-gate/override.json`, falling back to
`~/.local/state` when the variable is unset. The gate and Emacs both compute
it the same way, and Nix only uses it for the deny rules. config.org has no
channel for Nix-provided values, so a fixed path avoids inventing one.
