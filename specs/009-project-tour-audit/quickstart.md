# Quickstart: Validating Project Tours and Audits

**Prerequisites**: the home configuration built and activated with the change,
Emacs restarted, a Claude Code session attached through `claude-code-ide`.

## Automated

```bash
nix build .#test-walkthrough -L
```

The ERT suite covers, for tours and audits: each R5 validation message
([contracts/walkthrough-file.md](./contracts/walkthrough-file.md)); that an
invalid draft leaves the installed file untouched; the synthetic hunks a step
renders (line numbers, merged ranges, anchors widened by 3); `RET` on an
excerpt line visiting `<commit>:<file>` at that line; `walkthrough-diff-label`
returning `code at <oid>`; the file names `:tour.json` / `:audit:<area>.json`;
and audit findings appearing in `walkthrough-accepted-findings` with
`:type` and `:patch`. Existing walkthrough tests must still pass.

## Manual

1. **Tour (US1)**: in this repository run `/project-tour`. Expect: the buffer
   opens by itself; step 1 is an overview with a diagram; `N`/`P` move between
   steps; `RET` on an excerpt line opens that file at that line; excerpts are
   syntax-highlighted.
2. **Tour of an area**: `/project-tour workstation/agents`. Expect a separate
   tour; `C-u @ t` offers both.
3. **Audit (US2)**: on a scratch branch plant an off-by-one in an old file and
   duplicate a function; commit; run `/project-audit`. Expect both reported,
   each with its code shown; the defect has a verdict and failure scenario.
4. **Hand-off (US3)**: accept one finding, dismiss one, reply to one
   (`@ c` on it); also accept a finding in a branch walkthrough; `@ s`.
   Expect one prompt with the accepted and replied audit findings (file,
   lines, excerpt, `code at <oid>`) and the walkthrough finding; the
   dismissed one absent. Restart Emacs, `@ a`: marks kept.
5. **Comments (US4)**: in a tour, select two excerpt lines, `@ d` with a
   question. Expect the prompt to name the file, lines and `code at <oid>`.
   Select a diagram's lines, `@ c`, then `@ s`: the passage is quoted under
   its step.
6. **Menu (US5)**: `@ T` sends `/project-tour` to the session; `@ a` with no
   audit offers to request one.
7. **Moved**: commit anything, reopen the tour: the intro says `HEAD` moved.
