# Contract: commands, options and the agent seam

Everything below is added to `workstation/emacs/packages/beads.el` unless marked
*config.org*.

## Commands

### `beads-agent-prompt` — transient `i` "Prompt"

| Situation | Behaviour |
|-----------|-----------|
| No issue at point / in region | `user-error "No beads issue at point"`; nothing sent |
| `beads-agent-send-function` nil, or available-function returns nil | `user-error "No agent session for this repository"`; nothing sent |
| One or more ids | send `(format beads-agent-quick-prompt-format (string-join ids ", "))` with SUBMIT nil; then select the returned buffer's window, or `pop-to-buffer` it |
| Send function signals (no session chosen, buffer died) | error propagates; nothing else happens |

Ids come from `beads--issues-at-point`: the region's issues in listing order, or
the issue at point, or the issue a `beads-show-mode` buffer displays. The command
never reads an issue with completion (research R6).

Limitation: the reference is pasted at the terminal's cursor. Unsent input is
kept (FR-003); if the developer had moved the cursor into the middle of it, the
reference lands there.

### `beads-agent-explore` — transient `e` "Explore"

| Situation | Behaviour |
|-----------|-----------|
| No issue at point | `user-error "No beads issue at point"`; nothing sent |
| More than one id | `user-error "Explore works on one issue; the region covers %d"`; nothing sent |
| No agent | as above |
| One id | send the expanded explore prompt with SUBMIT t; leave windows unchanged; `message "Sent explore prompt for %s to %s" id (buffer-name returned)` |

Both commands honour a prefix argument only through the send function (in the
adapter: ask which session).

## Options (`defcustom`, group `beads`)

| Name | Type | Default |
|------|------|---------|
| `beads-agent-quick-prompt-format` | `string` | `"Beads issue %s: "` |
| `beads-agent-explore-prompt` | `string` | see [explore-prompt.md](./explore-prompt.md) |
| `beads-agent-available-function` | `(choice (const nil) function)` | `nil` |
| `beads-agent-send-function` | `(choice (const nil) function)` | `nil` |

## The agent seam

```text
beads-agent-available-function : () -> non-nil iff a session exists for
                                 default-directory's project. Must be cheap and
                                 must not prompt: the transient calls it while
                                 drawing.
beads-agent-send-function      : (TEXT SUBMIT) -> BUFFER
                                 Deliver TEXT to the chosen session's input as
                                 one paste; press return iff SUBMIT. May prompt
                                 to choose a session. Signal user-error when no
                                 session can be chosen. Return the session's
                                 buffer.
```

Called with `default-directory` bound to the repository root (`beads-toplevel`).

## Transient

`beads-dispatch` gains a column after "Relations":

```elisp
["Agent"
 ("i" "Prompt" beads-agent-prompt :inapt-if-not beads--agent-available-p)
 ("e" "Explore" beads-agent-explore :inapt-if-not beads--agent-available-p)]
```

`beads--agent-available-p` is nil when either variable is nil, else the result
of the available function.

## *config.org* adapters

In the `** Claude Code` section, outside the `use-package` `:config` so they are
defined before `claude-code-ide` loads:

- `my/claude-code-ide-paste (text submit)` — the body of today's
  `my/magit-review--paste`, moved and renamed; `my/magit-review-send` calls it.
- `my/claude-code-ide-session-p ()` — `(and (featurep 'claude-code-ide)
  (claude-code-ide-mcp--sessions-for-project (claude-code-ide--get-working-directory)) t)`.

The `use-package beads` block sets `beads-agent-available-function` and
`beads-agent-send-function` to these two, and its prose paragraph gains a
sentence on `i` and `e`.
