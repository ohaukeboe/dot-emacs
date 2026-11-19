# Research: Review Threads

Phase 0 of [plan.md](plan.md). Each entry resolves one unknown from the plan's
Technical Context.

## R1. How a thread forks the main conversation

- **Decision**: Start the thread as a new claude-code-ide instance whose CLI
  runs with `--resume <session-id> --fork-session`. During that start,
  `claude-code-ide-cli-extra-flags` is let-bound to the existing flags plus the
  fork flags.
- **Rationale**: `claude-code-ide--start-session` builds its command from
  `claude-code-ide-cli-extra-flags` and has no other hook for extra arguments.
  `--fork-session` gives the new instance its own conversation id, with the
  history copied up to the fork. That is exactly FR-004: the thread knows the
  context, and nothing in it reaches the main conversation. The new instance
  also gets its own MCP server, side window slot and buffer, like any instance.
- **Alternatives considered**:
  - `/branch` inside the main terminal: it switches that terminal over to the
    new conversation, so the main instance stops being the main one. Rejected.
  - `--continue --fork-session`: forks the most recent conversation in the
    directory, which is wrong as soon as two instances run for the project.
    Rejected.
  - A fresh instance with no history: the user rejected it (spec
    Clarifications).

## R2. Finding the main instance's conversation id

- **Decision**: Read `~/.claude/sessions/<pid>.json`, where `<pid>` is the
  instance's `claude-code-ide-mcp-session-cli-pid`, and take its `sessionId`.
  Read it at fork time, never cached. If the file or the key is missing, signal
  a `user-error` naming the instance, and send nothing.
- **Rationale**: claude-code-ide does not track Claude's conversation id. Its
  `session-id` is its own MCP registry key. Claude Code keeps one JSON file per
  running CLI process, keyed by pid, holding `sessionId` and `cwd`, and updates
  it when the conversation changes (for example after `/branch`). Reading the
  file only at fork time keeps up with such changes. `cli-pid` is set once the
  CLI connects to the instance's MCP server, which is true for any instance a
  review could have been sent to.
- **Alternatives considered**:
  - The newest transcript under `~/.claude/projects/<cwd>/`: ambiguous with
    several instances in one directory. Rejected.
  - A SessionStart hook that reports the id to Emacs: more moving parts across
    Nix, the hook and Emacs, for the same information. Rejected.
- **Risk**: The file is a Claude Code internal, not a documented interface.
  This is the same kind of dependency the config already has on
  claude-code-ide internals. The glue's comment names it next to the
  claude-code-ide internals it leans on, for re-checking on upgrades.

## R3. Getting the prompt into a freshly started thread

- **Decision**:
  - **Submit** (`@ s`, `@ d`): pass the prompt as the CLI's positional initial
    prompt, shell-quoted and appended after the fork flags. The CLI submits it
    once it is ready.
  - **No submit** (`@ p`, `C-u @ d`): wait, bounded by a timeout defcustom
    (default 30 s), until the instance's MCP client is connected and the
    terminal has been quiet briefly. Then paste through the existing paste
    primitive and do not press RET. On timeout, signal a `user-error` and mark
    nothing sent.
  - **Reused thread** (per-item follow-up): paste into the live buffer exactly
    as today, since that instance is already running.
- **Rationale**: `claude-code-ide--start-session` returns after a fixed
  stabilization delay. Resuming a long conversation can take longer than that,
  and a paste that arrives before the input box exists is lost. The positional
  prompt needs no readiness check at all, so it covers the common case
  robustly. The no-submit case has no CLI flag that prefills the input
  without submitting, so it needs the wait.
- **Alternatives considered**:
  - Always wait, then paste: one code path, but every submit becomes
    synchronous and can block Emacs for seconds. Kept only for no-submit.
  - Async paste on a timer: the hand-off then cannot know when to mark items
    sent (FR-011). Rejected.
- **Risk**: The command line has argument-size limits (ARG_MAX, about 2 MB,
  and 128 KiB for a single argument on Linux). Review prompts are usually far
  below them, but the glue guards anyway: a prompt over 100 000 bytes is not
  passed as the positional prompt. The thread is forked without it, and the
  prompt takes the no-submit path (wait, then paste) followed by RET.

## R4. Menu options and their persistence

- **Decision**: Add two switches to the `magit-review` transient:
  - `-t` "Separate thread" → `--thread`
  - `-n` "New thread each time" → `--new-thread`

  `--new-thread` off means per-item grouping, the spec default. The prefix
  gets `:remember-value '(exit quit)`, so the value lasts for the Emacs session
  once the menu is left. `C-x C-s` saves it as the default, the standard
  transient save. Commands read the options with `(transient-args
  'magit-review)`, which returns the active value inside the menu and the
  set or saved value outside it.
- **Rationale**: Two boolean switches are how Magit menus present options
  (FR-003). Each shows its state as a highlighted argument and costs one key
  press. The installed transient (20261101) supports `remember-value`.
- **Alternatives considered**: A single `--thread=item|hand-off|off` option
  that cycles through three values. It takes two or three key presses to reach
  a value and reads worse in the menu. Rejected.

## R5. Where the thread logic lives

- **Decision**: magit-review decides *which* thread each item goes to and
  remembers the links. The agent glue in `config.org` decides *how* to fork
  and paste. They meet at `magit-review-send-function`, which gains an
  optional third argument (see
  [contracts/send-function.md](contracts/send-function.md)).
- **Rationale**: FR-013 keeps magit-review agent-agnostic. Grouping and links
  are pure review logic, and the ERT suite can test them through a stub send
  function, which is the existing seam. Forking needs Claude and
  claude-code-ide internals, which only the glue may know.
- **Alternatives considered**: A second defcustom for forking. It splits one
  hand-off across two functions, which magit-review would then have to
  sequence. Rejected.

## R6. Identifying an item for per-item links

- **Decision**:
  - A review comment carries its thread as a `:thread` key on its plist.
  - A finding's thread lives in an in-memory hash keyed by
    `(walkthrough-file . finding-id)`, because findings are re-read from
    their file on every hand-off.
  - A new direct comment reuses the thread of the most recent comment whose
    target equals its own (every key except `:text`, `:sent` and `:thread`)
    and whose thread is still live.
- **Rationale**: Comments already live in memory, and the spec's assumptions
  keep links in memory too. A finding's id is stable within its walkthrough
  file.
- **Alternatives considered**: Writing finding threads into the walkthrough
  file. A buffer handle cannot be persisted, and the links would outlive the
  Emacs session, which is out of scope. Rejected.

## R7. Excluding threads from the fork source and the default target

- **Decision**: The glue keeps a list of the thread instances it started. When
  it resolves the main instance (to fork from, or to receive a hand-off with
  threads off), it drops those instances from the project's instances and
  then applies the existing rule: the only one, the only visible one, or the
  most recently used, with the prefix argument asking.
- **Rationale**: This is the spec's "never a fork source" assumption. Without
  it, the most-recently-used rule would pick a thread right after it was used.
  The thread instances are named `review-N: <label>`, the label being the
  first `## ` heading of the prompt cut to 30 characters (just `review-N`
  without one), so the user can also tell them apart, and what each is about,
  in `claude-code-ide-list-sessions` (FR-005). N alone keeps names unique.
  The glue derives the label from TEXT, so the send-function contract is
  unchanged.
- **Consequence**: Every caller that resolves the main instance through the
  glue skips thread instances, including the beads transient's sends and
  hand-offs with threads off. This is intended.
