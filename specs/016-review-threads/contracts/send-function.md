# Contract: `magit-review-send-function` with threads

The only seam between magit-review (agent-agnostic) and the agent glue in
`workstation/emacs/config.org`.

## Signature

```elisp
(funcall magit-review-send-function TEXT SUBMIT &optional THREAD) ⇒ BUFFER
```

| Arg    | Meaning                                                             |
|--------|---------------------------------------------------------------------|
| TEXT   | The prompt, exactly as without threads (FR-007).                    |
| SUBMIT | Non-nil: submit. Nil: paste only (`@ p`, `C-u @ d`).                |
| THREAD | `nil`: the main instance, as today (FR-012).                        |
|        | `new`: fork the main instance into a new thread and deliver there.  |
|        | A buffer: a thread this function returned before; deliver there.   |

**Returns**: the terminal buffer that received TEXT. When THREAD is `new` or a
buffer, magit-review stores this buffer as the thread of each item it sent.

## Obligations of the implementation (the glue)

- It signals an error, and delivers nothing, when the text could not be
  delivered: no main instance, no conversation id to fork (research R2), the
  fork failed to start, or a no-submit paste timed out (R3). magit-review marks
  items sent only after a normal return (FR-011).
- A THREAD buffer that is no longer live is never passed: magit-review checks
  `buffer-live-p` first and passes `new` instead (spec US3-6).
- The main instance is never a thread it started (R7).
- A forked thread is displayed in a Claude side window and named
  `review-N: <label>`, the label taken from TEXT's first `## ` heading
  (FR-005, research R7).
- When called with two arguments, it behaves exactly as before. The beads
  transient (`beads-agent-send-function`) keeps calling it that way.

## Obligations of magit-review

- It passes THREAD only when the `--thread` option is on.
- With `--new-thread`, it makes exactly one call per hand-off, with THREAD
  `new` (FR-010).
- Without it (per item), it makes one call per live thread among the items,
  with that buffer, and at most one call with `new` for all the items that
  have no live thread (FR-009). All calls use the same SUBMIT. Each call's
  TEXT is `magit-review-format` of that call's items, with the same intro.
- It marks items sent per call, right after that call returns. So when a
  later call fails, the earlier groups stay sent and the rest stay pending.
