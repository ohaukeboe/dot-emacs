# Quickstart: validating the Agent Commit Gate

## Automated

```bash
git add -A specs/005-agent-commit-gate workstation/agents tests   # flake sees tracked files only
nix flake check                                  # incl. checks.agent-commit-gate (parser, precedence, worktree detection)
nix build .#test-agent-commit-review -L          # opt-in: Emacs batch drives a Magit review (finish, cancel, expired)
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

Each one is expected to pass. The two test files are the unit tests for
[gate-cli.md](contracts/gate-cli.md) and the Emacs contract in
[emacs-review.md](contracts/emacs-review.md).

## Manual, live Claude Code session (after switch)

Use a scratch repository: `git init $TMPDIR/gate-demo` with one commit. In
each scenario, ask the agent to stage `a.txt` and commit it with a message.

| # | Setup | Expected |
|---|---|---|
| Q1 | Nix default `ask`, no override | Normal permission prompt. The reason says "mode from nix" |
| Q2 | `M-x agent-commit-gate-set` → this repo → `emacs` | The Magit commit buffer opens with the staged diff and the agent's message. Edit the subject and `C-c C-c`: one commit with the edited subject, and the agent reports its sha and stops |
| Q3 | Like Q2, but `C-c C-k` | No commit. The agent reports that it was declined and doesn't retry |
| Q4 | Like Q2, with Emacs stopped (`emacsclient -a false --eval t` fails) | Falls back to the normal prompt, with the reason "Emacs not reachable" |
| Q5 | Override `deny` | Refused with "Agent commits are disabled". `agent-commit-gate-set` → `default` restores Q1 |
| Q6 | Ask the agent to edit the override file, or set `AGENT_COMMIT_GATE` for its own command | The Edit/Write tools are denied. A per-command env var has no effect, and the mode is unchanged |
| Q7 | **Fail-safe.** Temporarily make the chain sleep longer than its timeout (a local debug env, reverted afterwards), then commit | Claude Code still prompts on `git commit`, through the static rule, and never commits unprompted. This confirms D2 |
| Q8 | `claudeWorktrees = "free"`, then start a task with `isolation: "worktree"` and ask it to commit there | It commits with no prompt. A commit in the main checkout in the same session still follows the mode |
| Q9 | Like Q8, but the worktree was made by hand with `git worktree add ../w` | Gated |
| Q10 | In `emacs` mode, set `emacsTimeout = 30`, open a review and wait | After 30 s the buffer is cancelled and the agent reports "timed out". A later `C-c C-c` in a leftover buffer does nothing |
| Q11 | `git add a.txt && git commit -m x` in one call, in any mode, including a free worktree | Denied by the staging guard, with the existing message |
| Q12 | `git commit --amend` in `emacs` mode | Normal prompt, with the reason "unsupported form" |
