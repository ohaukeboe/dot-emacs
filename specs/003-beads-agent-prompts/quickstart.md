# Quickstart: validating the agent prompts

## 1. Automated suite

```bash
git add -A workstation/emacs/packages specs/003-beads-agent-prompts
nix build .#test-beads -L
```

Expected: all tests pass, including the new `beads-agent-*` cases, which cover:
quick prompt from a section, from a region of several issues and from a show
buffer; explore from a section and a show buffer; the `%i`-less fallback; the
default prompt's required phrases ([contracts/explore-prompt.md](./contracts/explore-prompt.md));
and zero send calls for no issue, no agent and explore-on-a-region.

## 2. Configuration builds

```bash
nix fmt   # then revert unrelated churn
nix flake check
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

## 3. Manual, with a real Claude Code session (this repository)

1. Open Magit status. With **no** Claude session, press `#`: `Prompt` and
   `Explore` are shown greyed out.
2. Start a session (`C-c o c`), return to Magit status, put point on a ready
   issue, `# i`. Expected: the session is focused, its input reads
   `Beads issue dot-emacs-xxx: `, nothing is submitted. Type a word, submit,
   confirm the agent received id + word.
3. Type some text in the session's input without submitting, go back, `# i` on
   another issue. Expected: the earlier text is still there, the reference
   follows it.
4. Select two issues with the region, `# i`. Expected: both ids, listing order.
5. `RET` on an issue to open its detail buffer, `# e`. Expected: the window
   layout is unchanged, the echo area names the session buffer, and the agent
   starts exploring that issue.
6. With two sessions for the repository, `# C-u i`: asked which session.

## 4. SC-003 measurement (manual)

On 10 open issues, run `# e` in a fresh session each. After each reply:

```bash
git status --porcelain          # expect: empty (or unchanged from before)
bd show <id>                    # expect: status, assignee, comments as before the run
```

and check the transcript for a skill or workflow invocation. Record the count of
runs that end with summary + questions (or an explicit "nothing to decide") and
the count that changed anything. Target: 10 and 0.
