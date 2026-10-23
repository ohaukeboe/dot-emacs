# Data Model: Agent Commit Gate

All state is either Nix-declared (immutable per generation) or small files the
user (via Emacs) or the gate writes at runtime. No database.

## Gate mode

How a commit on a user checkout is handled.

| Value | Meaning |
|---|---|
| `ask` | Today's behaviour: Claude Code permission prompt |
| `emacs` | Review in Magit; outcome returned as deny + reason |
| `deny` | Refused: agent commits disabled |

Source precedence (D4): `AGENT_COMMIT_GATE` env → override file (repo key) →
override file (`"*"`) → `agents.commitGate.mainCheckout`. An invalid value in
the env var or file is ignored with a note in the reason, and the next source
is used (never fails open: worst case is the Nix default).

## Worktree setting

`agents.commitGate.claudeWorktrees`: `gated` (default) | `free`. Nix only.

## Override file

`$XDG_STATE_HOME/agent-commit-gate/override.json`, written only by Emacs.

```json
{ "*": "emacs", "/home/oskar/projects/dot-emacs/.git": "ask" }
```

- Keys: `"*"` or an absolute common git dir (`git rev-parse
  --path-format=absolute --git-common-dir`).
- Values: a gate mode. A missing file or a parse error is treated as empty.
- Written atomically (temp + rename).

## Commit request

Derived per Bash call by `agent-commit-gate decide`.

| Field | Source |
|---|---|
| `tool_use_id` | payload |
| `cwd` | payload |
| `target_dir` | cwd + `cd X &&` + `-C` chain; `null` when unresolvable |
| `message` | joined `-m` values or `-F` file; `null` when absent or unsupported |
| `unsupported` | first unsupported option, if any |
| `staging_problem` | existing commit-guard check result |

## Agent worktree (classification)

The target is an agent worktree iff all D5 checks hold:
`git_dir != common_dir`, `toplevel ⊂ dirname(common_dir)/.claude/worktrees/`,
`git_dir/CLAUDE_BASE` exists, `HEAD == refs/heads/worktree-<basename(toplevel)>`.

## Review request directory

`$XDG_RUNTIME_DIR/agent-commit-gate/<tool_use_id>/`, mode 0700, created by
the gate, removed by the gate after it reads the result (or on timeout).

| File | Writer | Content |
|---|---|---|
| `msg` | gate | proposed message |
| `request.json` | gate | `{dir, gate_pid, deadline}` (epoch seconds) |
| `result.json` | Emacs | see Review outcome |

## Review outcome (`result.json`)

```json
{ "status": "committed", "sha": "abc1234…", "subject": "feat: …" }
{ "status": "not-committed", "reason": "cancelled by the user" }
```

`reason` values: `cancelled by the user`, `empty message`,
`commit hook failed (exit N)`, `review already open in this repository`,
`magit refused: <msg>`, `request expired`.

### State transitions (one request)

```text
created ──emacsclient ok──▶ open ──user finishes, git exit 0──▶ committed
   │                         │──cancel / empty / hook fail──▶ not-committed
   │                         │──gate deadline──▶ cancelled-by-gate ─▶ (gate denies "timed out")
   │                         └──gate pid gone, user finishes──▶ refused (no commit)
   └──emacsclient fails──▶ (gate falls back to ask)
```
