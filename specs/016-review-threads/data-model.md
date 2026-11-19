# Data Model: Review Threads

Everything here lives in memory for the Emacs session. Nothing is written to
disk, and the walkthrough file format is unchanged.

## Thread

A forked Claude instance, as seen from magit-review: an opaque **buffer**, the
terminal buffer that the send function returned.

- A thread is live while `buffer-live-p` holds. Closing the instance kills the
  buffer, which ends the thread.
- The glue additionally knows the thread's claude-code-ide session and keeps
  it in its list of started threads (research R7).

## Thread link

Which thread a review item was last handed off in. It is used only when
`--thread` is on and `--new-thread` is off.

- **Review comment**: `:thread` on the comment plist in `magit-review-comments`,
  keyed by the comment itself (`eq`).
- **Finding**: a hash table in magit-review, keyed by
  `(walkthrough-file . finding-id)`.

Rules:

- The link is set to the buffer an item's hand-off went to, after that call
  returns (contract: send-function).
- A link to a dead buffer counts as no link (spec US3-6), and is replaced on
  the next hand-off.
- **Direct comment target match**: a new direct comment takes the link of the
  most recent comment with an equal target and a live link. The target is the
  plist minus `:text`, `:sent` and `:thread`.
- **Finding follow-up**: the finding's hash entry is used, so a reply sent
  with `@ s` or `@ d` goes back to its thread.
- With `--new-thread`, links are still written, so that switching back to per
  item continues in the latest thread.
- `magit-review-discard` drops comments and their links. Finding links stay
  until the Emacs session ends.

## Thread options

| Option         | Type    | Default | Meaning                                     |
|----------------|---------|---------|---------------------------------------------|
| `--thread`     | switch  | off     | Hand-offs go to threads.                    |
| `--new-thread` | switch  | off     | Per hand-off grouping. Off means per item.  |

## Hand-off partition (per item)

Given the items of one hand-off:

1. Group the items by live link (buffer), in first-seen order.
2. The items without a live link form one more group, sent with THREAD `new`.
3. Send each group, mark its items sent, and set their links to the returned
   buffer.
