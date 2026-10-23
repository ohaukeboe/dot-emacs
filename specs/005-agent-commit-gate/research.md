# Research: Agent Commit Gate

Phase 0 for [plan.md](plan.md). The evidence (Claude Code docs, claude-code-ide,
Magit and with-editor source, a live `isolation: "worktree"` run) is in
[`docs/claude-commit-gate-magit-research.md`](../../docs/claude-commit-gate-magit-research.md),
abbreviated below as **R**. This file records only the decisions.

## D1. Where the gate decision is made

- **Decision**: Inside the existing `agent-bash-rewriter-chain`, which already
  owns every Bash decision. When the original command contains a `git commit`
  segment, the chain calls a new executable, `agent-commit-gate decide`, with
  the original payload. It then emits the gate's decision (`allow`, `ask` or
  `deny`, plus the reason) together with the chain's `updatedInput`. The
  separate `commit-guard` hook is removed, and its checks become step 0 of
  `decide`.
- **Rationale**: Matching hooks run in parallel, and the winning `updatedInput`
  is undefined (ADR 0003). An `allow` for a worktree commit only works when
  the command text no longer matches the static ask rule, and that happens
  only through the chain's rewrite (R, *A fact that settles ADR 0003's open
  question*). Deny beats ask beats allow, so the staging check keeps its
  meaning when it is folded in.
- **Alternatives considered**: A second PreToolUse hook for the gate, rejected
  because it races the chain. Keeping `commit-guard` as its own hook and adding
  the gate to the chain would work, but runs the same parser twice and splits
  one decision across two hooks.

## D2. How the static ask rule interacts with the gate

- **Decision**: Keep `"git commit"` in `agents.sensitiveBashPrefixes`. The chain's
  generic re-assertion skips a prefix that the gate has already decided.
- **Rationale**: Permission rules are matched against the hook's
  `updatedInput` (hooks.md, quoted in R). The rewritten text
  (`agent-process-cap run fg …`) never matches `Bash(git commit:*)`, so the
  static rule is inert while the chain works. It only takes effect when the
  chain is killed or fails, and then the command reaches the harness unchanged
  and is prompted for. That is the fail-safe FR-019 needs.
- **Open risk**: This rests on documented behaviour that has not been tested
  here. Quickstart scenario Q7 tests it.

## D3. The hook timeout and fail-closed behaviour

- **Decision**: Set the chain hook entry's `timeout` to
  `agents.commitGate.emacsTimeout + 60` unconditionally, because a runtime
  override can switch to Emacs review at any time. Add `onFailure = "block"`
  only when `lib.versionAtLeast config.programs.claude-code.package.version
  "2.1.295"`, which is pure evaluation.
- **Rationale**: Claude Code's default is 600 s, and a timed-out PreToolUse hook
  fails open (hooks.md *Timeouts*). The gate's own deadline is shorter than the
  hook timeout, so the gate always gets to cancel the review and deny first.
  Other commands return in milliseconds, so the longer timeout costs nothing.
- **Alternatives considered**: Leaving the default timeout, rejected because it
  caps the review at 10 minutes and races the gate's own deadline. A
  version-independent `onFailure`, rejected because older Claude Code versions
  may reject the unknown key.

## D4. Toggle mechanism and precedence

- **Decision**: Three sources, highest precedence first:
  1. the `AGENT_COMMIT_GATE` env var in Claude Code's process env, set at
     launch;
  2. the override file `$XDG_STATE_HOME/agent-commit-gate/override.json`,
     looked up by the repository's common git dir first and then by `"*"`;
  3. the Nix default, `agents.commitGate.mainCheckout`.

  The worktree setting comes from Nix only.
- **Rationale**: Hooks inherit Claude Code's environment, and Claude cannot
  change its parent's environment. `$HOME` is read-only for sandboxed Bash
  (ADR 0004). The Edit and Write tools run outside the sandbox, so
  `permissions.deny` gets `Edit(<file>)` and `Write(<file>)`. Emacs runs
  outside the sandbox and writes the file. Keying by common git dir means a
  repository and all of its worktrees share one override.
- **Alternatives considered**: `git config` (writable from a worktree through
  the shared `.git`), `settings.local.json` `env` (undocumented whether it
  reaches hooks), and Nix only (needs a rebuild). See R, the Q1 table.

## D5. Detecting a Claude-created worktree

- **Decision**: Resolve the target directory from `payload.cwd`, a leading
  `cd X &&`, and the commit segment's `-C` options. Any `--git-dir`,
  `--work-tree`, `GIT_DIR=` or `GIT_WORK_TREE=` means the main checkout. Then
  require all of the following:
  - the absolute git dir differs from the common dir;
  - the top level is under `dirname(common)/.claude/worktrees/`;
  - `<git-dir>/CLAUDE_BASE` exists;
  - HEAD is the branch `worktree-<basename(toplevel)>`.
- **Rationale**: The path and branch conventions are documented (worktrees.md),
  and the marker was observed on 2.1.289. If any check fails, the commit is
  treated as gated, which is safe (FR-017). The branch check stops a commit to
  the user's own branch checked out inside an agent worktree.
- **Alternatives considered**: Checking `agent_id` against the worktree name,
  rejected because the `agent_id` format is unverified and because
  `--worktree` sessions have no `agent_id`. Path alone, rejected because the
  agent can `git worktree add` anywhere.
- **Accepted limitation**: The agent can forge the marker through the shared
  `.git`. This is a cooperative-agent threat model (ADR 0004).

## D6. Emacs review mechanism

- **Decision**: The gate, running unsandboxed, calls
  `emacsclient --eval "(agent-commit-gate-review DIR REQ)"`. That function runs
  `magit-commit-create '("--edit" "--file=REQ/msg")` and attaches a sentinel
  to the returned git process, which writes `REQ/result.json` atomically. The
  gate polls for the result. The outcome is always returned as `deny` with a
  reason, so the agent's own command never runs.
- **Rationale**: Hooks run outside the sandbox and can reach the Emacs socket.
  Basing the outcome on git's exit status is reliable, while
  `git-commit-post-finish-hook` has a 2 s timeout. Because Emacs runs the
  commit itself, what gets committed is exactly what was staged when the user
  finished (FR-009). Deny is the only decision that guarantees no second
  commit (FR-011).
- **Alternatives considered**: `GIT_EDITOR` set to emacsclient, which can't
  work because the socket is hidden from the sandbox. An emacs-tools MCP tool,
  which can't block, so it could only be asynchronous. Allowing a rewritten
  `git commit -F <edited>`, which leaves a gap where the index can change
  between review and commit, and keeps the agent as the signer. Deferred.

## D7. Stale reviews: timeout, interrupt, concurrency

- **Decision**: Each request gets the directory
  `$XDG_RUNTIME_DIR/agent-commit-gate/<tool_use_id>/` holding `msg`,
  `request.json` (with the gate's pid and deadline) and later `result.json`.
  - **Timeout**: on its deadline the gate calls
    `(agent-commit-gate-review-cancel REQ)`, which runs `with-editor-cancel` in
    that commit buffer, and then denies with "timed out".
  - **Interrupt**: the elisp adds a buffer-local `with-editor-pre-finish-hook`
    that refuses to finish when the gate pid is gone or the deadline has
    passed. It tells the user why and cancels instead.
  - **Concurrency**: the directory is keyed by `tool_use_id`, so each request
    is separate (FR-015). A second review in the same repository is refused
    while one is open, because git holds `index.lock` and Magit would mix up
    the `COMMIT_EDITMSG` buffers.
- **Rationale**: This covers the spec's edge cases without a daemon. The
  sandbox can't write `$XDG_RUNTIME_DIR`, so the agent can't forge a result.
- **Resolved in implementation**: `with-editor-pre-finish-hook` can't abort,
  because it is plain `run-hooks`. But `with-editor-finish` runs
  `with-editor-finish-query-functions` through
  `run-hook-with-args-until-failure`, so a buffer-local entry that returns nil
  aborts the finish. That is what the code uses. The ERT test
  `agent-commit-gate-test-finish-refused-when-gate-is-gone` covers it.

## D8. Message extraction and unsupported forms

- **Decision**: `-m`/`--message` values are joined with blank lines, which is
  what git does. `-F`/`--file` is read from the target directory, and `-F -`
  is unsupported. These cause a fallback to `ask`: `--amend`, `-C`, `-c`,
  `--fixup`, `--squash`, `--no-verify`/`-n`, `--allow-empty`, `--author`,
  `--date`, `--reset-author`, `--no-edit`, `--dry-run`, and any option that
  isn't recognised (FR-012).
- **Rationale**: The review must show exactly what will be committed. Anything
  the review can't reproduce faithfully goes to the normal prompt.

## D9. Testing strategy

- **Decision**:
  - `checks.agent-commit-gate`: Python `unittest` for parsing, precedence and
    worktree detection, run against fixture repositories built with `git` in
    the build sandbox (a real `git worktree add` with a hand-made
    `CLAUDE_BASE`). This is cheap and is Principle III compliant.
  - `packages.test-agent-commit-review`: Emacs in batch mode with Magit loads
    the tangled review functions. It drives `agent-commit-gate-review`, inserts
    an edit, calls `with-editor-finish` or `with-editor-cancel`, and checks
    `result.json` and `git log`. It's opt-in because of the Emacs closure, and
    follows the `test-emacs-sops-save` pattern.
  - The parts that need a live Claude Code (Q1–Q8 in quickstart.md) are
    manual.
- **Rationale**: Constitution I and III. Evaluation guards cover the option
  types, the version-gated `onFailure`, and the assertion that `"git commit"`
  stays in the sensitive prefixes while the gate is enabled.
