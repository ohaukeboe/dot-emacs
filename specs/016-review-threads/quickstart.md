# Quickstart: validating Review Threads

## Automated

```bash
nix build .#test-magit-review -L    # thread partition, links, options (stub send function)
nix build .#test-walkthrough -L     # only if walkthrough.el changed
nix flake check
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

The ERT suite drives the hand-off commands with a stub
`magit-review-send-function` that records `(TEXT SUBMIT THREAD)` and returns
a fresh buffer for `new`. It asserts the calls and the sent marks against
[contracts/send-function.md](contracts/send-function.md).

## Manual (needs a live Claude Code, so it cannot run in a test)

Setup: open a repo with a branch, start one Claude instance (`C-c o c`) and
exchange one message with it, for example "This branch adds X."

1. `@ -t`, comment a hunk (`c`), then `s`. A `review-1` instance opens, answers,
   and knows "X". The main instance has no new turn.
2. Quit `@` and reopen it. `-t` is still on.
3. `@ d` on the same hunk. It goes to `review-1`, and no new instance opens.
4. `@ -n`, then `@ d` on the same hunk. `review-2` opens.
5. Turn `-n` off. In a walkthrough, accept a finding and `@ s`, then reply to it
   with `@ c` and `@ s` again. The second send goes to the first send's thread,
   as a follow-up.
6. Kill `review-1`, then `@ d` on the first hunk again. A new thread opens.
7. `C-u @ d` with `-t` on. A new thread opens, the prompt is pasted but not
   submitted, and its window is selected.
8. Turn `-t` off, then `@ s`. It goes to the main instance, never to a
   `review-N`.
9. Close every Claude instance, then `@ -t` and `@ s`. You get an error, and
   the comments stay pending.
10. Send a prompt from the `#` beads menu. It is unchanged and goes to the main
    instance.
