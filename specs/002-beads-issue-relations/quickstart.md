# Quickstart: validating Beads Issue Relations

**Feature**: `specs/002-beads-issue-relations/` · **Date**: 2026-09-23

Two levels of validation: the ERT suite, which runs against a fake `bd` and is
what CI-style checking uses, and a manual pass in a scratch tracker, which is
what proves the marks and jumps feel right. Run both before calling the feature
done.

## Prerequisites

- This worktree, with every new file `git add`ed (the flake sees only tracked
  files).
- `bd` on `PATH` for the manual pass only; the ERT suite supplies its own fake.

## 1. Automated: the ERT suite

```bash
nix build .#test-beads -L
```

Builds an Emacs closure and runs `workstation/emacs/packages/beads-test.el`
in batch. Expected: the derivation succeeds. A failing assertion prints
`FAIL: …` and exits non-zero.

While iterating, the same suite runs without Nix:

```bash
cd workstation/emacs/packages
emacs -batch -L . -l beads-test.el -f ert-run-tests-batch-and-exit
```

The suite must still contain, unchanged, the structural invariant tests that
guard `dot-emacs-l3y` — the marks add text to the same headings that bug
mangled, so those tests are load-bearing here too.

Relation cases the suite must cover, mapped to the spec:

| Case | Covers |
|------|--------|
| Issue with a parent shows the parent mark and body line | FR-001 |
| In-progress issue with two blockers shows both | FR-002 |
| Issue whose only dependency is closed is not marked blocked | FR-003 |
| Issue with dependents shows the count | FR-004 |
| A parent's children are reachable though the listing counts none | FR-004, R11 |
| Relation-free issue's heading is unchanged from today | FR-005, SC-005 |
| Section tree stays consistent with marks present | dot-emacs-l3y |
| A blocker id that resolves to nothing renders as unknown | FR-015 |
| More blockers than `beads-relation-limit` are summarised | FR-016 |
| No listed issue has relations ⇒ fake `bd` never sees `blocked` | FR-018, SC-004a |
| A failing relation call still lists the issues | FR-015 |

## 2. Manual: a scratch tracker

Build a tracker with every shape the marks have to show. It lives in a temp
directory and touches nothing in this repository.

```bash
D=$(mktemp -d); cd "$D"
git init -q .
bd init --prefix lab

EPIC=$(bd create --title "Epic one" --type epic --priority 1 --json | jq -r .id)
CHILD=$(bd create --title "Child task" --type task --priority 2 --parent="$EPIC" --json | jq -r .id)
BLOCK=$(bd create --title "Blocker task" --type task --priority 2 --json | jq -r .id)
DONE=$(bd create --title "Closed dependency" --type task --priority 2 --json | jq -r .id)

bd dep add "$CHILD" "$BLOCK"
bd dep add "$CHILD" "$DONE"
bd close "$DONE" --reason "done"
bd update "$CHILD" --claim          # so the blocked child is actually listed

echo "$EPIC $CHILD $BLOCK $DONE"
```

Open `magit-status` in that directory and check, in order:

1. **Marks are visible without unfolding** (FR-001, FR-002, FR-004, SC-001).
   The child's heading carries `↑` and `⊘1`. The blocker carries `↳1`. The
   **epic carries no mark**: `bd list` and `bd ready` do not count children
   among an issue's dependents, only `bd show` does (research.md R11) — its
   child is still reachable with `#` `d`, which asks the question that counts
   them. Nothing carries `⊘2` — the closed dependency is not a blocker
   (FR-003).
2. **A relation-free issue is untouched** (FR-005, SC-005). Create one more
   issue with no relations; its line has no mark, no extra separator, and sits
   at the same column as before.
3. **Body lines name the relation** (FR-001, FR-002). TAB on the child shows
   `Parent:` with the epic's id and title, and `Blocked by:` with the blocker's
   id, status and title, above the description.
4. **Two keystrokes to the parent** (FR-006, SC-002). With point on the child,
   `#` then `p` lands on the epic. It is listed in the same buffer, so point
   moves there and the section is revealed rather than a new buffer opening
   (FR-009).
5. **Choosing among blockers** (FR-007). Add a second blocker
   (`bd create` + `bd dep add "$CHILD" <id>`), refresh, then `#` `b` on the
   child: a prompt offering both, annotated with status and title.
6. **Landing on an unlisted issue** (FR-010). `#` `b` and choose a blocker you
   have since closed: its `bd show` buffer opens instead.
7. **Navigating from a show buffer** (FR-011). In that buffer, `#` `p` acts on
   the issue the buffer displays.
8. **Nothing happens when there is nothing to do** (FR-012). `#` `p` on the
   epic, which has no parent: a message, and point has not moved.
9. **Unavailable entries are visible** (FR-014). Open `#` on the epic: the
   parent entry is greyed out, not missing.
10. **Going back** (FR-013, SC-003). Follow parent, then a dependent, then
    `#` `B` twice: each lands on the previous issue in reverse order, and the
    last one is where you started. Under 15 seconds.
11. **Cycles do not loop** (edge case). `bd dep add "$BLOCK" "$CHILD"`,
    refresh, then jump back and forth: each issue shows its own relations once
    and no command hangs.

## 3. Cost check (SC-004a, SC-004b, FR-018)

In a tracker whose listed issues have no relations — this repository's own
tracker today — the section must make exactly the two `bd` calls it makes now.
Confirm by watching the process list, or by pointing `bd` at a wrapper that logs
its arguments:

```bash
mkdir -p /tmp/bdlog/bin
cat > /tmp/bdlog/bin/bd <<'SH'
#!/bin/sh
echo "$@" >> /tmp/bdlog/calls
exec /run/current-system/sw/bin/bd "$@"
SH
chmod +x /tmp/bdlog/bin/bd
```

With that first on `exec-path`, refresh the status buffer of this repository and
check `/tmp/bdlog/calls`: `list --status=in_progress` and `ready` only, with no
`blocked` and no `list --id=`. That is SC-004a.

Repeat in the scratch tracker of step 2, where `blocked` and one `list --id=`
must appear once each per refresh — never per issue, and never a third and
fourth extra call. Add ten more issues to that tracker and refresh again: the
count of extra calls must not move. That is SC-004b.

## 4. Repository gates

Before committing, the loop the constitution requires:

```bash
git add -A
nix fmt                 # then revert unrelated churn
nix flake check
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
nix build .#test-beads -L
```

Deploy with `sudo nixos-rebuild switch --flake .#<hostname>` only after those
pass.
