# Quickstart: Validate Review Walkthroughs

**Feature**: [spec.md](./spec.md) | Contracts: [interfaces](./contracts/interfaces.md),
[file](./contracts/walkthrough-file.md)

## Automated

```bash
nix build .#test-walkthrough -L   # ERT: validator, hunk filter, buffer, marks, hand-off items
nix flake check
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

The ERT suite covers, against a throwaway repository:

- coverage errors: missing hunk, duplicated hunk, whole-file and range conflict,
  binary file, deleted file, pure rename (FR-005);
- the range-overlap rule including `+c,0` hunks (research R3);
- the buffer: step order, every hunk once, a step with an empty diff keeps its
  heading, review-comment decoration draws, RET visits blob `head`;
- finding placement: anchored, not placed, unanchored; the "no findings" line;
- marks: state transitions, written to the file, survive a reload; `sent` is
  final (FR-012–FR-014);
- moved and gone notices (FR-019).

## Manual, after `nixos-rebuild switch`

1. **Built-in review reachable from a skill** (research R5 risk). In a Claude
   session, run `/walkthrough` on a branch with a planted off-by-one. Expect a
   finding for it. If the skill says the review could not be invoked, stop:
   R5 needs a new decision.
2. **US1/US2**: the buffer opens by itself. `N`/`P` move between steps, `n`/`p`
   between findings, and the planted finding sits below its line.
3. **US4**: select two lines in a step, `@ c`, write a comment. Then run
   `magit-diff` on `main..HEAD`: the same comment is drawn there (research R6).
4. **US3**: `a` one finding, `x` another, `@ s`. The prompt holds the accepted
   finding and the comment only. Restart Emacs, `@ w`: the marks are kept, and
   the accepted finding is shown as sent.
5. **US5**: `@ W` sends `/walkthrough` to the session. Commit a fix, then
   `@ w`: the header says the branch head has moved.
6. **SC-001**: on a branch with about 30 changed files, the buffer appears
   within 5 seconds of the tool call.
