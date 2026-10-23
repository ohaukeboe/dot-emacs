# Claude Code commit gate: toggles, worktree mode, and review in Magit

Research report (2026-10-23). Questions:

1. Can the commit gate be made easily toggleable?
2. Can Claude commit freely in worktrees it created itself, but still need
   approval on the user's own checkout?
3. Can approval happen in Emacs/Magit (review the staged diff, edit the
   message, then commit or abort) instead of Claude Code's permission prompt?

Checked against the live setup: Claude Code **2.1.289** (`AI_AGENT` in a
subagent's environment), git 2.55.0, magit 20261005.508, with-editor
20261003.1832, claude-code-ide.el `50a3d55`. Claude Code docs were fetched
from `code.claude.com/docs/en/*.md` on 2026-10-23.

## TL;DR

1. **Yes.** Today the gate is three independent mechanisms (a static `ask`
   rule, the rewriter chain's re-assertion, and the commit-guard deny hook),
   and a hook `allow` can't override a static ask rule. The cleanest toggle is
   a Nix enum option for the default mode, plus a runtime override file that
   only the user can write. Emacs is outside the sandbox, so it can write the
   file, and the Edit/Write tools get a deny rule for it. Gate decisions move
   into the one Bash hook that already owns decisions, the rewriter chain.
2. **Yes, and it can be detected reliably enough for this threat model.** The
   hook runs unsandboxed and sees the payload's `cwd`. It resolves the
   directory git actually acts on (`cd X &&`, `git -C X`), then checks four
   things: `--absolute-git-dir` differs from `--git-common-dir`, the worktree
   top level is under `<repo>/.claude/worktrees/`, the worktree's git dir
   holds the `CLAUDE_BASE` marker, and the current branch is `worktree-*`.
   All four were observed on a real `isolation: "worktree"` worktree. Anything
   else counts as the main checkout and stays gated.
3. **Yes, through a command hook that calls `emacsclient`, with no MCP
   needed.** The docs say command hooks run outside the sandbox with full
   user access, so the hidden `/run/user/1000/emacs` socket is not a problem
   for them. The hook opens `magit-commit-create` with
   `--edit --file=<Claude's message>`, which shows the staged diff and an
   editable `COMMIT_EDITMSG`, and then waits on the git process. It
   returns `deny` with a reason that says "committed as <sha>" or "user
   aborted". `GIT_EDITOR`/`core.editor` set to emacsclient does **not**
   work from the sandboxed Bash tool, and claude-code-ide's `emacs-tools` MCP
   server can't block for user input, so it's only good for an asynchronous
   "propose commit" tool.

Biggest blockers:

- A static `Bash(git commit:*)` ask rule can't be overridden by a hook
  `allow`. Free worktree commits only work because the rewriter chain always
  rewrites the text, so the static rule no longer matches.
- A PreToolUse hook that times out **fails open** into the normal permission
  flow. `onFailure: "block"` needs 2.1.295, and 2.1.289 is installed.
- Commits made by Emacs are signed with the user's key, not the agent's
  signing key.

## How the current gate works

The "gate" is three layers, all generated from Nix in `workstation/agents/`:

| Layer                                                         | Where                                                                                                                                                           | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Static ask rule                                               | `default.nix:232-249` (`agents.sensitiveBashPrefixes`, includes `"git commit"`), rendered at `default.nix:321` as `permissions.ask = map (p: "Bash(${p}:*)") …` | The harness prompts for `git commit …`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Rewriter-chain re-assertion                                   | `default.nix:27-130` (`agent-bash-rewriter-chain`), registered as the single `PreToolUse`/`Bash` hook at `default.nix:337-355`                                  | After rtk (order 50) and the process cap (order 90) rewrite the command, it matches the **original** text against the same prefixes and returns `permissionDecision: "ask"` plus `updatedInput` (`default.nix:98-122`). Commands matching a project's `sandbox.excludedCommands` skip the chain (`default.nix:45-82`)                                                                                                                                                                                                                                      |
| Commit guard (the "hook that denies commits that break this") | `commit-guard.nix:17-33` adds a separate `PreToolUse` hook, `matcher = "Bash"`, `command = agent-commit-guard` (a `writePython3Bin` of `commit-guard.py`)       | `commit-guard.py:136-182` tokenises the command with `shlex`, splits on `&& \|\| ; \| & ( )`, and skips env assignments and wrappers (`env`, `nocap`, `rtk`, `sudo`, …). If any segment is `git commit`, it returns **deny** when the same call also runs a staging subcommand (`add rm mv stage update-index apply reset restore checkout`), or when the commit uses `-a/-i/-o/-p`, `--all/--include/--only/--patch/--interactive/--pathspec-from-file`, `--`, or a bare pathspec. Otherwise it prints nothing. Unparseable input is left to the ask rule |

The module wiring is `agents.tools.<name>.hooks.PreToolUse` (option at
`default.nix:160-164`), with all tools' lists concatenated per phase
(`default.nix:337`). The guard is deliberately a separate hook rather than
a rewriter stage, because it never emits `updatedInput` and deny beats ask
(`commit-guard.nix:18-21`). The docs confirm the precedence:
"`deny` > `defer` > `ask` > `allow`" (hooks.md, *PreToolUse decision
control*).

There is also prose in the global memory: `agents-global.md:6-7` ("Never
`git commit` … without an explicit instruction", "Stage and commit in
separate Bash calls").

### A fact that settles ADR 0003's open question

ADR 0003 says it was unknown whether ask rules match the original input or the
hook's `updatedInput`. The hooks reference now says it outright:

> Claude Code evaluates permission rules … against the input your hook
> returns, not the input Claude sent.
> — hooks.md, *PreToolUse decision control*, `updatedInput` row

So the static `Bash(git commit:*)` rule **never matches** a command the chain
rewrote: the final text is `agent-process-cap run fg <base64>`, and the cap
stage always wraps unless the command was opted out with `nocap` or is
excluded (`process-cap.nix:160-200`). In practice the chain's re-assertion
is the real gate, and the static rule is the fail-safe for when the chain
doesn't run or doesn't finish. The design below depends on this.

Also from the docs: "a matching ask rule still prompts even when the hook
returned `"allow"` or `"ask"`" (permissions.md, *Precedence among rules,
hooks, and mods*). A hook alone therefore can't relax a static ask rule. It
can only make that rule stop matching.

## Q1: making the gate toggleable

| Mechanism | Who can flip it | Pros | Cons |
|---|---|---|---|
| **Nix option** (`agents.commitGate.mode`) | User, needs `home-manager switch` | Declarative, reviewable, asserted | Slow to toggle. `~/.claude/settings.json` is a read-only store symlink (`auto-mode.nix:4-5`) |
| **Env var at launch** (`AGENT_COMMIT_GATE=off claude`) | User, per session | Simple. Hooks inherit Claude Code's environment ("A hook process inherits the parent environment", hooks.md *Common input fields*) | Claude can't change a running session's env, which is good. Inside Emacs it needs `process-environment` or the ghostel environment set before launch |
| **Runtime flag file** (`$XDG_STATE_HOME/agent-commit-gate/…`) | User from Emacs/CLI | Instant, can be global or per repo | Sandboxed Bash can't write `$HOME` (`sandbox.nix` writablePaths, ADR 0004). The Edit/Write tools run **outside** the sandbox (sandboxing.md *What runs outside the sandbox*), so add `permissions.deny` `Edit(…)`/`Write(…)` rules for the path |
| **Project `.claude/settings.local.json`** (`env` key, or a key the hook reads with `jq`) | User approves an Edit prompt | Per project, already protected: sandbox protected path (sandboxing.md *Protected paths*) plus the existing `Edit(/.claude/settings.local.json)` ask rule (`sandbox.nix` permissions.ask) | Unverified: the docs don't say whether settings `env` values reach hook processes. Reading the file with `jq` works, and the chain already does this for `excludedCommands` (`default.nix:53-63`). An unknown top-level key may draw a settings-validation warning (unverified) |
| `git config agent.commitGate` | User | Per repo | `.git/config` is a sandbox protected path in the working directory only (sandboxing.md *Protected paths*). In a linked worktree the common `.git` is writable (see risks), so Claude could flip it there. Avoid |

**Recommendation.** Use the Nix enum as the default, plus an optional
runtime override file that the hook checks first. Emacs gets a command
`my/claude-commit-gate-set` to write the file. The env var is a third, highest
precedence override for one-off sessions. None of these can be flipped by
Claude: the sandbox blocks the file for Bash, deny rules block it for the
Edit/Write tools, and Claude can't change the session env.

## Q2: free commits in Claude-created worktrees

### What Claude Code creates (observed and documented)

Documented (worktrees.md):

- `--worktree <name>`: "created under `.claude/worktrees/<name>/` at your
  repository root, on a new branch named `worktree-<name>`" (*Start Claude in
  a worktree*). `EnterWorktree` and `isolation: worktree` use the same place
  (*Ask Claude to create a worktree*, *Isolate subagents with worktrees*).
- "Claude Code writes a marker into the git metadata of every worktree it
  creates with git" (*Clean up subagent and background-session worktrees*).
  The marker's name is not documented.
- "While an agent is running, Claude Code holds a `git worktree lock` on its
  worktree."
- Hooks: "`${CLAUDE_PROJECT_DIR}` stays put … `cwd` follows Claude: the `cwd`
  field in the hook's input JSON is the worktree root, and it moves again when
  Claude runs `cd`" (*Ask Claude to create a worktree*, note).
- While isolated, Claude Code itself blocks Bash commands whose working
  directory is the main checkout, and commands that redirect git into it
  through `git -C`, `--git-dir`, `GIT_DIR`/`GIT_WORK_TREE`, or `cd`
  (*How Claude Code enforces isolation*).

Observed on a real `Agent(isolation: "worktree")` run in this repo. The
worktree was removed automatically afterwards; `git worktree list` was
clean again.

```
toplevel        /home/oskar/projects/dot-emacs/.claude/worktrees/agent-a6e5942e182b8a9f6
git-dir         /home/oskar/projects/dot-emacs/.git/worktrees/agent-a6e5942e182b8a9f6
git-common-dir  /home/oskar/projects/dot-emacs/.git
branch          worktree-agent-a6e5942e182b8a9f6
<git-dir>/CLAUDE_BASE   193362dab86b…   (base commit; this is the marker)
<git-dir>/locked        claude agent agent-a6e5942e182b8a9f6 (pid 349825 start 22234416)
env             CLAUDECODE=1, CLAUDE_CODE_SESSION_ID=…, CLAUDE_PID=…, PWD=<worktree>
```

The sandbox for that subagent added both the worktree and
`/home/oskar/projects/dot-emacs/.git` (the **common** git dir) to its write
allowlist. Committing needs that, and it has a consequence described under
Risks.

### Detection algorithm (for the hook, which runs unsandboxed)

1. **Resolve the target directory.** Start from `payload.cwd`. Apply a leading
   `cd <dir> &&` segment and the commit segment's `git -C <dir>`. Several `-C`
   options compose relative to each other, as git does. If the commit segment
   uses `--git-dir`, `--work-tree`, or a `GIT_DIR=`/`GIT_WORK_TREE=`
   assignment, or the command can't be parsed, treat it as **main checkout**.
   `commit-guard.py:91-105` already walks these options and only needs to keep
   their values.
2. `git -C <dir> rev-parse --path-format=absolute --absolute-git-dir
   --git-common-dir --show-toplevel`. `--git-common-dir` prints
   "`$GIT_COMMON_DIR` if defined, else `$GIT_DIR`"
   ([git-rev-parse](https://git-scm.com/docs/git-rev-parse)), so
   **git-dir == common-dir means the main checkout, which stays gated.**
3. For a linked worktree, require **all** of:
   - toplevel is under `dirname(common-dir)/.claude/worktrees/`, the
     documented default;
   - `<git-dir>/CLAUDE_BASE` exists (observed marker, name undocumented);
   - `git symbolic-ref --short HEAD` equals `worktree-<basename(toplevel)>`.
     This stops Claude from checking out one of the user's branches inside
     its worktree and committing to it there.
   - Optional: when `payload.agent_id` is set, check that the worktree name
     is `agent-<agent_id>`. This held in the observation, but the `agent_id`
     format in hook payloads was not verified.
4. Pass: `allow` in `claudeWorktrees = "free"` mode. Fail: apply the
   main-checkout mode.

User-made worktrees (`git worktree add ../foo`) fail step 3 and stay gated.

## Q3: approving the commit in Emacs/Magit

### Constraints, from primary sources

- **Hooks are outside the sandbox.** "The sandbox wraps shell commands. …
  command hooks, local MCP servers, plugin monitors, LSP servers … run with
  your full access" (sandboxing.md *What runs outside the sandbox*). Also:
  "Hook commands themselves run unsandboxed" (hooks.md, *DirectoryAdded*).
  ADR 0004 already records this under Consequences. A command hook can
  therefore reach `/run/user/1000/emacs/server`, even though
  `sandbox.nix:300` hides it from Bash commands.
- **Hook timeout:** "Defaults: 600 for `command`, `http`, and `mcp_tool`"
  (hooks.md *Common fields*). PreToolUse isn't lowered. The per-hook
  `timeout` field raises it. "On `PreToolUse`, a timed-out `command`, `http`,
  or `mcp_tool` hook doesn't block the tool call … The call continues through
  the normal permission flow" (hooks.md *Timeouts*). `onFailure: "block"`
  changes this, but "Requires Claude Code v2.1.295 or later", and 2.1.289 is
  installed.
- **Process and memory caps:** the process cap only wraps Bash tool commands
  through the rewriter chain (`process-cap.nix`), not hook processes, so the
  hook's own `timeout` is the only runtime limit. A hook lands in the session's
  `claude-<pid>.scope`, with that scope's memory limit, which is negligible
  here.
- **Who sees what:** `deny` reason → shown to Claude; `ask` reason → shown in
  the prompt; `allow` reason → debug log only. Use `additionalContext` to talk
  to Claude (hooks.md *PreToolUse decision control*).
- **Emacs server:** `config.org:114` calls `(server-start)`. Claude
  runs inside ghostel with `EDITOR=emacsclient` (`config.org:3459`), and
  hooks inherit that environment.

### Options

| Option | Works? | Notes |
|---|---|---|
| **A. PreToolUse command hook → `emacsclient --eval` → Magit commit buffer; Emacs runs the commit; hook returns `deny` + reason** | **Yes (recommended)** | No socket exposed to the sandbox. The user sees `magit-diff-staged` (shown automatically when `magit-commit-show-diff` is t, `magit-commit.el:45`) and edits the message. Emacs runs the real `git commit`, so what's staged at that moment is exactly what's committed. Deny is the only decision that stops the Bash command from committing a second time. The reason text tells Claude the result ("Committed as abc123 by the user in Emacs; do not run git commit again" or "User aborted in Emacs") |
| A′. Same, but Emacs only edits and approves; hook returns `allow` + `updatedInput` = `git commit -F <edited-msg>` | Possible, more fragile | Keeps Claude as committer (agent signing key, sandboxed). But the index can change between review and commit (a time-of-check/time-of-use gap). A guard like `test "$(git write-tree)" = <reviewed-tree> && git commit -F …` closes it. Two hooks returning `updatedInput` race ("winning updatedInput undefined", ADR 0003), so this must live inside the rewriter chain |
| A″. Hook returns `allow` and replaces the command with `git show --stat HEAD`, so Claude sees a success | Possible | Nicer result for Claude, but it silently swaps the command. Same chain-only constraint |
| **B. `GIT_EDITOR`/`core.editor` = emacsclient, `git commit -e -m …` from Bash** | **No** | emacsclient can't reach the socket (hidden, `sandbox.nix:300`). with-editor's fallback "sleeping editor" prints its request to stdout for "a process filter" and "can only be used as $EDITOR of child process of the current Emacs instance" (`with-editor.el:193-212`). The Bash tool's stdout goes to Claude, not to Emacs. Exposing the socket would give sandboxed commands arbitrary elisp, so full user access, which defeats ADR 0004 |
| **C. `emacs-tools` MCP tool (claude-code-ide) that Claude calls, e.g. `propose_commit`** | Only asynchronously | The HTTP MCP server calls the tool synchronously, `(apply tool-function args)`, and responds in the same request (`claude-code-ide-mcp-http-server.el:214-245`). Only the built-in IDE `openDiff` handler supports deferred replies (`claude-code-ide-mcp-handlers.el:460-462`, `claude-code-ide-mcp.el:398-420`). A tool that waits for the user would block Emacs or need a `recursive-edit` inside a process filter, which is fragile and unverified. Workable shape: the tool opens the Magit buffer and returns "opened for review" at once, and Emacs later reports the outcome with `my/claude-code-ide-paste` (`config.org:4471`), the same mechanism `magit_review_comments` uses. MCP runs outside the sandbox anyway, so it isn't needed to get around the sandbox. The emacs-tools server exists only in sessions started by claude-code-ide (`claude-code-ide-mcp-server.el:278-290`, `--mcp-config` URL `http://localhost:<port>/mcp/<session>`) |
| D. `type: "mcp_tool"` PreToolUse hook calling an emacs-tools tool | No | Same blocking problem as C. Also, the docs say a tool result with `isError` → "non-blocking error and execution continues" (hooks.md *MCP tool hook fields*) |

### Abort, failure and timeout semantics for option A

- **C-c C-c (finish):** git creates the commit and exits 0, and Emacs records
  the new HEAD. The hook returns deny with "committed as <sha>: <subject>".
- **C-c C-k (cancel), empty message, or a failing git `pre-commit`/`commit-msg`
  hook:** git exits non-zero, and the hook returns deny with "not committed:
  <reason>". Base the outcome on the **git process exit status**, not on
  `git-commit-post-finish-hook`. That hook is skipped when git takes longer
  than `git-commit-post-finish-hook-timeout` (2 s) (`git-commit.el:1300-1346`).
  `magit-commit-create` returns the process: it calls
  `magit-run-git-with-editor`, which "return[s] the process object"
  (`magit-process.el:618-639`, `magit-commit.el:208-217`). Attach a
  sentinel to it.
- **Nothing staged:** `magit-commit-assert` would ask in the minibuffer. Check
  `git diff --cached --quiet` in the hook first and deny "nothing staged".
- **Emacs not running or unreachable** (`emacsclient -a false --eval t`
  fails): fall back to `ask`, the current behaviour.
- **Timeouts:** give the hook its own deadline, e.g. `emacsTimeout`, shorter
  than the hook entry's `timeout`. On expiry it cancels the buffer
  (`emacsclient --eval` → `with-editor-cancel` in that buffer) and denies
  "timed out". If Claude Code kills the hook first, its output is discarded
  and the call goes through normal permissions. In that case the static
  `Bash(git commit:*)` rule matches the **unrewritten** original text and
  prompts, so it fails safe, as long as `"git commit"` stays in the static
  ask list. After a kill, the Magit buffer may still be open. The elisp must
  refuse to commit once the hook has given up (it checks a "claimed" flag in
  the result file) to avoid a double commit.
- **Concurrency:** key the request and result files by `tool_use_id` under
  `$XDG_RUNTIME_DIR/agent-commit-gate/`.

## Recommended design

### Nix (`workstation/agents/commit-gate.nix`, replacing `commit-guard.nix`)

```nix
options.agents.commitGate = {
  enable = mkEnableOption "agent git commit gate" // { default = true; };
  mainCheckout = mkOption {            # user's own checkouts
    type = types.enum [ "ask" "emacs" "deny" ];
    default = "ask";
  };
  claudeWorktrees = mkOption {         # .claude/worktrees/<n> on worktree-<n>
    type = types.enum [ "free" "gated" ];
    default = "gated";
  };
  emacsTimeout = mkOption { type = types.ints.positive; default = 1200; };
  overrideFile = mkOption {            # written by Emacs, never by the agent
    type = types.str;
    default = "${config.xdg.stateHome}/agent-commit-gate/override.json";
  };
};
```

- Keep `"git commit"` in `agents.sensitiveBashPrefixes`. The static
  rule is the fail-safe for an unrewritten command.
- In the rewriter chain (`default.nix:98-130`), before the generic prefix
  re-assertion: if the original text contains a `git commit` segment, run
  `agent-commit-gate decide` on the original payload and emit its decision
  (`allow`/`ask`/`deny` + reason) with the chain's `updatedInput`. All Bash
  decisions stay in the single hook ADR 0003 calls for, so no second hook
  races on `updatedInput`.
- Set `timeout = cfg.emacsTimeout + 60` on the chain's hook entry when
  `mainCheckout = "emacs"`. Other commands are unaffected because they
  return in milliseconds.
- `permissions.deny` gets `Edit(${overrideFile})` and `Write(${overrideFile})`.
- Fold `commit-guard.py`'s checks into `agent-commit-gate` as step 0 (still a
  deny), so in Emacs mode the reviewed diff is still exactly what's
  committed.
- Update `agents-global.md:6-7`: commits in Claude's own `.claude/worktrees`
  on `worktree-*` branches are allowed when the gate says so, and a commit
  denied with "committed by the user in Emacs" must not be retried. Add an
  ADR amending 0003 and 0004.

### Hook outline (`agent-commit-gate decide`, Python)

```
payload = read stdin
seg = parse(command)                       # reuse commit-guard parser
if staging_problem(seg): deny(reason)      # existing guard
mode = env AGENT_COMMIT_GATE or override_file[repo] or override_file["*"] or nix default
dir = resolve_dir(payload.cwd, seg)        # cd / -C; GIT_DIR etc. → None
if dir and is_claude_worktree(dir) and claudeWorktrees == "free": allow
if mode == "ask":   ask("commit on user checkout")
if mode == "deny":  deny("commits disabled")
# mode == "emacs"
if not emacs_reachable(): ask("Emacs not reachable")
msg = extract_message(seg)                 # -m… joined as paragraphs (git-commit docs), -F file
if msg is None or unsupported_flags(seg): ask(...)   # --amend, --no-verify, -C … → plain prompt
if nothing_staged(dir): deny("nothing staged")
req = $XDG_RUNTIME_DIR/agent-commit-gate/<tool_use_id>; write req/msg
emacsclient --eval "(my/agent-commit-review \"dir\" \"req\")"
wait for req/result (poll) until emacsTimeout
  timeout → emacsclient --eval "(my/agent-commit-review-cancel \"req\")"; deny("timed out")
result.exit == 0 → deny("Committed by the user in Emacs as <sha> <subject>. Do not run git commit again.")
else            → deny("User did not commit (<reason>). Ask before trying again.")
```

### Elisp outline (`config.org`, Magit section)

```elisp
(defun my/agent-commit-review (dir req)
  "Open a Magit commit for Claude's request REQ in DIR; report to REQ/result."
  (let* ((default-directory dir)
         (msg (expand-file-name "msg" req))
         (proc (magit-commit-create (list "--edit" (concat "--file=" msg)))))
    (if (not (processp proc))
        (my/agent-commit--write req 1 "magit refused (nothing staged?)")
      (add-function :after (process-sentinel proc)
        (lambda (p _)
          (when (memq (process-status p) '(exit signal))
            (my/agent-commit--write
             req (process-exit-status p)
             (and (zerop (process-exit-status p))
                  (magit-rev-parse "HEAD")))))))
    ;; Raise the frame so the user notices; optionally (select-frame-set-input-focus …)
    t))
```

`my/agent-commit--write` writes `result.json` atomically (write to a temp
file, then rename). `my/agent-commit-review-cancel` finds the
`COMMIT_EDITMSG` buffer for that repo and calls `with-editor-cancel`. The
commit buffer is ordinary `git-commit-mode`, so `C-c C-c`/`C-c C-k`, message
history and the diff window all work as they do now.

## Open questions and risks

- **Fail-open on hook timeout** (hooks.md *Timeouts*). The design leans on the
  static ask rule matching the unrewritten text when the chain is killed. That
  follows from the docs, but someone should **test it** by forcing a slow
  chain. Upgrade to ≥ 2.1.295 and set `onFailure: "block"` on the chain entry.
- **The "rules match `updatedInput`" behaviour** is documented
  (hooks.md:1947 in the fetched copy). It changes ADR 0003's reasoning:
  today's static ask rule is effectively inert for rewritten commands. Confirm
  this with one real prompt test.
- **The worktree marker name `CLAUDE_BASE` is undocumented**, observed on
  2.1.289 only, and may change. The path and branch conventions are
  documented. If the marker disappears, the check falls back to gated, which
  is safe.
- **A sandboxed agent in a worktree can write the common `.git`.** The
  subagent's write allowlist contained `/home/oskar/projects/dot-emacs/.git`.
  It could forge `CLAUDE_BASE`, or create its own `.claude/worktrees/x` with
  `git worktree add`. That's acceptable under ADR 0004's cooperative-agent
  threat model, but it's not a security boundary. It is also **unverified**
  whether the common `.git/config` and `.git/hooks` stay write-protected
  from a worktree session: protected paths cover "`hooks` and `config` inside
  `.git`" only "in your working directory" (sandboxing.md *Protected
  paths*). This was not probed. Worth an `agent-sandbox-probe` case.
- **Signing and authorship.** In option A, Emacs runs `git commit` with the
  user's own config, so the commit is signed with the **main** key, not the
  agent signing key that `sandbox.nix:446-457` sets through
  `GIT_CONFIG_PARAMETERS` for Claude's processes. That can be argued either
  way (the user reviewed and committed). If agent attribution matters, the
  elisp can pass `-c user.signingkey=…` in `magit-git-global-arguments` for
  that call, or use option A′.
- **Whether `settings.env` values reach hook processes** is not documented, so
  the design doesn't depend on it.
- **`deny` reads as a tool error to Claude.** The reason text must say clearly
  that the commit happened, and the memory doc should say so too, or Claude
  may retry or apologise. Option A″ avoids this but rewrites commands
  silently.
- **Unsupported commit forms** (`--amend`, `-C`, `--no-verify`,
  `--fixup`) fall back to `ask` in Emacs mode. Amending through Magit could
  be added later.
- **Hooks are not per agent.** An `isolation: worktree` subagent and the main
  session share the hook, and the payload's `agent_id` distinguishes them.
  Subagents run in the background, so a blocking Emacs review only holds up
  that subagent's tool call.

## Sources

Local (paths relative to the repository root unless absolute):

- `workstation/agents/commit-guard.nix:1-34`, `commit-guard.py:1-186`
- `workstation/agents/default.nix:14-130` (chain), `:232-249` (prefixes), `:321` (ask rules), `:337-355` (hook rendering)
- `workstation/agents/sandbox.nix:291-310` (hidden sockets incl. emacs, bus), `:446-457` (agent signing env)
- `workstation/agents/process-cap.nix:160-200`, `auto-mode.nix:1-10`, `agents-global.md:6-7`
- `docs/adr/0003-agent-bash-rewriter-chain.md`, `docs/adr/0004-agent-sandbox-policy.md`
- `workstation/emacs/config.org:114`, `:1265-1290`, `:3456-3459`, `:4471`
- `/nix/store/5xikszl4xbkig4vmqgvaymggjqpsyr5v-emacs-claude-code-ide-50a3d55/share/emacs/site-lisp/`: `claude-code-ide-mcp-server.el:101-140, 278-290`; `claude-code-ide-mcp-http-server.el:80-140, 214-245, 314-322`; `claude-code-ide-mcp-handlers.el:460-512`; `claude-code-ide-mcp.el:398-420`
- `/nix/store/dmds69siim1kwipxvd5b8yyllpq25kxa-emacs-packages-deps/share/emacs/site-lisp/elpa/`: `magit-20261005.508/magit-commit.el:45, 208-217`; `magit-process.el:618-639`; `git-commit.el:1300-1346`; `with-editor-20261003.1832/with-editor.el:193-218, 327-390`
- Live observation: `Agent(isolation: "worktree")` run, 2026-10-23, Claude Code 2.1.289 (output quoted above)

Claude Code docs (fetched 2026-10-23):

- https://code.claude.com/docs/en/hooks: *Common fields* (timeout defaults, `onFailure` ≥ 2.1.295), *Timeouts*, *Common input fields* (cwd, agent_id, environment inheritance), *PreToolUse decision control* (allow/deny/ask/defer, `updatedInput` evaluated by permission rules, precedence), *MCP tool hook fields*, *WorktreeCreate/WorktreeRemove*, *DirectoryAdded* ("Hook commands themselves run unsandboxed")
- https://code.claude.com/docs/en/permissions: *Precedence among rules, hooks, and mods*; rule order "deny, then ask, then allow"
- https://code.claude.com/docs/en/sandboxing: *What runs outside the sandbox*, *Auto-allow mode*, *Protected paths*
- https://code.claude.com/docs/en/worktrees: path/branch conventions, marker, locks, hook `cwd` vs `CLAUDE_PROJECT_DIR`, isolation checks
- https://code.claude.com/docs/en/mcp: tool timeouts (`MCP_TOOL_TIMEOUT`, per-server `timeout`), `requiresUserInteraction`
- https://code.claude.com/docs/en/settings: `env` block and project trust

Git:

- https://git-scm.com/docs/git-rev-parse: `--git-common-dir`, `--absolute-git-dir`
- https://git-scm.com/docs/git-commit: multiple `-m` "concatenated as separate paragraphs"; `--edit` with `-F`/`-m`
