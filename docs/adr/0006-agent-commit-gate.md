# ADR 0006: A commit gate in the rewriter chain, with review in Emacs

**Status:** Accepted (2026-10-23). Amends ADR 0003 and ADR 0004.

## Context

Until now, an agent's `git commit` was gated in three places. There was a
static `Bash(git commit:*)` ask rule, the rewriter chain asked again based on
the original text, and a separate `commit-guard` hook denied any commit that
also staged files in the same call. The user approved commits at a terminal
prompt that showed only the command. A poor message could not be fixed there:
the user had to reject the commit and explain in chat. Commits in an
agent's isolated worktree were gated as well, although nothing reaches the
user's branches from there until the user merges it. See
`specs/005-agent-commit-gate/` and
`docs/claude-commit-gate-magit-research.md`.

ADR 0003 left one question open: are ask rules matched against the original
input or against a hook's `updatedInput`? The hooks reference now answers it.
Permission rules are evaluated "against the input your hook returns, not the
input Claude sent". It also says that a matching ask rule still prompts when
a hook returns `allow`.

## Decision

**The rewriter chain owns the commit decision.** When the original command
runs `git commit`, the chain calls `agent-commit-gate decide` on the
unrewritten payload. Its `allow`, `ask` or `deny` becomes the hook's
`permissionDecision`, alongside the chain's `updatedInput`. The
`commit-guard` hook is gone, and its staging check is the gate's first step.
A second hook would race the chain over `updatedInput` (ADR 0003), and an
`allow` only holds because the chain rewrites the text so that the static
rule stops matching.

**The static ask rule stays as the fail-safe.** If the chain is killed or
fails before it decides, Claude Code sees the original text, the static
`Bash(git commit:*)` rule matches, and the commit is prompted for. Claude Code
2.1.295 adds `onFailure = "block"`. The chain sets it once the installed
version supports it.

**The mode is ask, emacs or deny.** It comes from the `AGENT_COMMIT_GATE`
env var at launch, then from an override file that Emacs writes
(per repository, then `*`), then from Nix. The agent can't change it:
sandboxed Bash can't write `$HOME`, the Edit and Write tools have deny rules
for the file, and a hook inherits Claude Code's environment, not the
command's.

**In emacs mode, Emacs makes the commit.** The gate runs as a hook outside the
sandbox. It reaches Emacs through `emacsclient` and calls
`agent-commit-gate-review`, which opens Magit's commit buffer with the
agent's message. The gate then waits for git's exit status. The agent's own
command is always denied, with the outcome as the reason, so one request
never commits twice. The Emacs socket stays hidden from sandboxed commands.

**Free commits in the agent's own worktrees are opt-in.** This is
`claudeWorktrees = "free"`. It requires a linked worktree under
`.claude/worktrees/`, the `CLAUDE_BASE` marker, and HEAD on
`worktree-<name>`. An allow covers the whole command text, so it is given
only to the plainest form: `git [-C dir] commit -m …`, optionally after
`cd dir &&`. Any wrapper, env assignment, or other git or commit option
makes the command fall back to the mode. So does anything the shell would
expand, substitute or redirect, judged with quoting: single-quoted text is
literal, and double-quoted text only expands `$` and backticks. Claude's
usual message, with a `Co-Authored-By: Name <email>` trailer in double
quotes, therefore qualifies.

## Consequences

- The gate fails closed: no decision, output it can't parse, or any exception
  means `ask`. This differs from the chain's rewriting stages, which fail open
  (ADR 0003), because a lost rewrite costs tokens but a lost commit decision
  costs a commit nobody approved.
- The chain's hook timeout is raised to `emacsTimeout + 60` seconds, so the
  gate can always withdraw a review before Claude Code gives up on the hook.
  A review the gate has abandoned refuses to commit.
- A commit made in Emacs is signed with the user's key, not the agent's
  signing key. The user reviewed it and made it.
- The worktree test is not a security boundary. An agent in a worktree can
  write the shared `.git` and forge the marker. This is accepted under ADR
  0004's cooperative-agent threat model. The test guards against mistakes.
- The worktree marker name `CLAUDE_BASE` is undocumented. If Claude Code
  renames it, free mode quietly stops applying, and commits are gated again.
