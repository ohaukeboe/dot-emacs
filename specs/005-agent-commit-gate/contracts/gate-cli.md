# Contract: `agent-commit-gate decide`

Called by `agent-bash-rewriter-chain` with the **original** PreToolUse payload
on stdin, but only when the original command has a `git commit` segment. It
runs outside the sandbox.

## Environment read

- `AGENT_COMMIT_GATE`: optional mode override.
- `XDG_RUNTIME_DIR`, `XDG_STATE_HOME`: inherited.
- `AGENT_COMMIT_GATE_CONFIG`: a store path to JSON
  `{mainCheckout, claudeWorktrees, emacsTimeout, emacsclient}`,
  baked in by Nix. It is not user-settable at runtime, because the chain
  passes the store path explicitly.

## Stdout

Always exactly one JSON object, and the exit code is always 0:

```json
{ "decision": "allow" | "ask" | "deny", "reason": "<text>" }
```

The chain wraps it as `hookSpecificOutput.permissionDecision` /
`permissionDecisionReason`, plus its own `updatedInput`. On empty or invalid
output, or a non-zero exit, the chain falls back to `ask` (fail closed).

## Decision order

1. A staging problem (from commit-guard) → `deny` with the existing message.
2. Resolve the mode (D4) and classify the target (D5).
3. An agent worktree with `claudeWorktrees = free` → `allow`.
4. `deny` mode → `deny` "Agent commits are disabled (mode from <source>)."
5. `ask` mode → `ask` "Commit on the user's checkout."
6. `emacs` mode:
   - unsupported form, or no message → `ask` "<why>; Emacs review cannot show this faithfully"
   - Emacs unreachable (`emacsclient -a false --eval t` fails within 3 s) → `ask` "Emacs not reachable"
   - nothing staged (`git diff --cached --quiet` exits 0) → `deny` "Nothing is staged."
   - otherwise run the review (see emacs-review.md) and map the outcome:

| Outcome | Decision | Reason text for the agent |
|---|---|---|
| committed | deny | `The user reviewed and committed this in Emacs as <sha> "<subject>". The commit is done; do not run git commit again.` |
| not-committed | deny | `The user did not commit (<reason>). Nothing was committed. Ask the user before trying again.` |
| timeout | deny | `The Emacs review timed out after <n>s and was cancelled. Nothing was committed. Ask the user before trying again.` |

The reason for every `allow`/`ask` names the mode's source (env, override
repo, override `*`, nix) so the user can see why at the prompt.
