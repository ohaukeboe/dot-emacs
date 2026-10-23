# Expiring overrides keyed on a nixpkgs issue or PR

Research report. Question: can an `expiringOverride` name a NixOS/nixpkgs
issue (e.g. `fixedBy = "NixOS/nixpkgs#123456"`) as its expiry condition, and
fire once the commit that fixes it is contained in the pinned nixpkgs?

Verified against this repo on 2026-10-23: `flake.lock` pins `nixpkgs` to the
channel tarball `nixos-26.11pre1086391.151fa4e8ddfd` (rev `151fa4e8…`,
`lastModified` 2026-10-06). GitHub API calls below were made unauthenticated
against `api.github.com`.

## TL;DR

> Note: the adopted design treats `fixedBy` as a *fix reference*, not an
> expiry condition (see "Fix reference" in CONTEXT.md and the amendment to
> ADR 0005); this report's "condition" wording predates that decision.

**Not at evaluation time.** Pure evaluation cannot reach GitHub, and nothing
in the pinned nixpkgs carries git history, so "is commit X an ancestor of the
pinned rev" is not decidable inside `nix eval`. It is cheap to decide
*outside* eval: one GitHub compare call between the fix's merge commit and the
`rev` already recorded in `flake.lock`. Recommended design: a `fixedBy`
condition that is inert at eval (the override keeps applying, no warning) plus
an out-of-eval checker (`just` recipe) that resolves each reference to a merge
commit and asks GitHub whether the pinned rev contains it. Prefer recording
the **fixing PR**, not the issue: issue to fix mapping is unreliable in
nixpkgs (see the zotero example below).

## 1. What the pinned nixpkgs exposes at eval time

- The input is a plain tarball (`type = "tarball"` in `flake.lock`), not
  `github:`. Its lock entry nevertheless has a `rev`, because the channel
  server implements the Lockable HTTP Tarball Protocol: the server returns a
  `Link: <flakeref>; rel="immutable"` header whose flakeref may carry `rev`,
  `revCount`, `narHash` and `lastModified`; "They are not checked by Nix"
  ([Nix manual, tarball fetcher protocol](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/doc/manual/source/protocols/tarball-fetcher.md)).
  So `inputs.nixpkgs.rev` and `inputs.nixpkgs.lastModified` are available;
  `revCount` is not in this lock entry.
- `github:` inputs would not help either: they "are downloaded as tarball
  archives, rather than through Git … it doesn't require fetching the entire
  history", and `revCount` is unavailable for them
  ([Nix manual, `nix flake`](https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake.html)).
- Inside the source tree: no `.git`; a `.git-revision` file (the full rev) and
  `.version-suffix` (`pre1086391.151fa4e8ddfd`), checked in the store copy of
  the pin. `lib.trivial.versionSuffix` reads `.version-suffix` and
  `lib.trivial.revisionWithDefault` reads `.git-revision` when there is no
  `.git` ([lib/trivial.nix at the pinned rev](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/lib/trivial.nix#L512-L545)).
  The number in the suffix is `revCount` of the channel commit
  ([nixos/release.nix](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/nixos/release.nix#L33)).
  A smaller `revCount` on another commit does **not** imply ancestry, so it
  cannot stand in for the check.
- Conclusion: at eval time we know *which* commit is pinned and its date, but
  nothing about its ancestors.

### Can a fetch inside eval check ancestry?

- Pure evaluation restricts "network access to files specified by
  cryptographic hash"; `fetchTree`/`fetchGit` "require a locked revision" and
  a branch without a revision "is rejected"
  ([Nix source, `pure-eval` setting](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/src/libexpr/include/nix/expr/eval-settings.hh#L197-L214);
  enforced in [fetchTree.cc](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/src/libexpr/primops/fetchTree.cc#L306-L318)).
  `--impure` lifts this
  ([common-eval-args.cc](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/src/libcmd/common-eval-args.cc#L112-L117)).
  A GitHub API query is therefore impossible in a normal `nixos-rebuild`.
- `builtins.fetchGit` has `shallow`, `ref` and `allRefs`, but no ancestry
  primitive; it returns a tree plus `rev`/`revCount`/`lastModified`
  ([fetchGit docs in fetchTree.cc](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/src/libexpr/primops/fetchTree.cc#L700-L800)).
  When `rev` is given, the git fetcher fetches that object directly
  (`<rev>:refs/__nix_internal…`) and only checks that the object exists
  (`hasObject`), so a successful fetch of `rev = fix` proves nothing about
  the pinned branch
  ([git.cc](https://github.com/NixOS/nix/blob/5695a4e66039c3a3eed27576571c9c323126b059/src/libfetchers/git.cc#L870-L935)).
  Computing `revCount` also needs a non-shallow clone of all of nixpkgs at eval
  time, which is a multi-GB fetch (size not measured here).
- Import-from-derivation does not help: only fixed-output derivations get
  network access in the build sandbox
  ([Nix manual, `sandbox`](https://nix.dev/manual/nix/latest/command-ref/conf-file.html#conf-sandbox)),
  and a fixed-output derivation needs its output hash in advance, so it cannot
  return a changing answer.

## 2. Mapping an issue to the commit that fixes it

GitHub records several links, none of them reliable for nixpkgs:

- **`closed` event `commit_id`**: set only when a commit closed the issue via
  "closes/fixes" syntax
  ([issue event types](https://docs.github.com/en/rest/using-the-rest-api/issue-event-types)).
- **Closing keywords** only work when the PR targets the default branch; "if
  the pull request targets any other branch, then these keywords are ignored,
  no links are created" ([linking a PR to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue)).
  nixpkgs mass-rebuild fixes go to `staging`, so they never auto-close.
- **GraphQL** `Issue.closedByPullRequestsReferences` (open PRs by default,
  `includeClosedPrs` optional) and `ClosedEvent.closer: Closer` where
  `union Closer = Commit | ProjectV2 | PullRequest`
  ([GitHub GraphQL schema](https://docs.github.com/public/fpt/schema.docs.graphql)).
  Whether GraphQL works without a token was not verified; plan for a token.
- **`cross-referenced` / `referenced` timeline events** list every PR or
  commit that mentioned the issue, including forks and downstream configs
  (timeline only, not the events API:
  [issue event types](https://docs.github.com/en/rest/using-the-rest-api/issue-event-types)).

**Worked example from this repo** (`flake.nix`: "drop once
NixOS/nixpkgs#569006 fixes NixOS/nixpkgs#568692"):

- [#568692](https://github.com/NixOS/nixpkgs/issues/568692) was closed by hand
  on 2026-10-15 (`closed` event, `commit_id: null`). Its timeline has 20+
  `referenced` events, all commits in downstream user repos (including this
  one's), plus cross-references from unrelated PRs.
- [#569006](https://github.com/NixOS/nixpkgs/pull/569006), the PR the TODO
  names, was **closed without merging** (`merged: false`). The closing comment
  says maintainers chose
  [#572466](https://github.com/NixOS/nixpkgs/pull/572466) instead, and that
  zotero would be unbroken on unstable "Soon".
- #572466: merged 2026-10-15 into `master`, `merge_commit_sha febdeeb8…`.
  `compare/febdeeb8…...151fa4e8…` → `behind`, `behind_by 6528`: **the pinned
  nixpkgs does not contain the fix**. `compare/febdeeb8…...nixos-unstable` →
  `ahead`, `behind_by 0`: current nixos-unstable does. So `nixpkgs-zotero` can
  probably go after the next `nix flake update` (a build check is still
  needed; the fix also needs `firefox-esr-140-bin-unwrapped` permitted as
  insecure and unfree, per that comment).

A checker following the issue alone would either find nothing (no
`commit_id`) or follow the wrong PR. Closing an issue is not the same as the
fix reaching a channel.

### Has a commit reached the pinned rev?

- `GET /repos/{owner}/{repo}/compare/{base}...{head}` returns `status`
  `ahead`/`behind`/`identical`/`diverged` plus `ahead_by`/`behind_by`
  ([compare two commits](https://docs.github.com/en/rest/commits/commits#compare-two-commits)).
  With `base` = fix merge commit and `head` = pinned rev, `ahead` or
  `identical` means contained. Use `per_page=1` to keep the response small;
  large diffs "may time out" (same page).
- Get the merge commit from `GET /repos/NixOS/nixpkgs/pulls/{n}`:
  `merged`, `merge_commit_sha`, `base.ref` (checked live above).
- **pr-tracker** ([source](https://git.qyliss.net/pr-tracker), Alyssa Ross,
  AGPL-3.0-or-later; README names nixpk.gs as an instance) does the same with
  a local clone: GraphQL `pullRequest { baseRefName mergeCommit { oid } merged }`
  (`src/pr_info.graphql`), then `git branch -r --contains <merge commit>`
  (`src/nixpkgs.rs`), walking a branch table `staging → staging-next → master
  → nixos-unstable-small / nixpkgs-unstable …` (`src/branches.rs`). It answers
  "which channel has it", not "does my pin have it". The nixpk.gs instance
  itself was not fetched (blocked by the sandbox).
- Rate limits: 60 requests/hour unauthenticated, 5,000/hour with a personal
  token ([REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)).
  At about 2 calls per reference, unauthenticated is enough for a handful of
  overrides.

## 3. Options

| Option | Pure eval | Cost | Verdict |
|---|---|---|---|
| (a) Checker outside eval: reference → merge commit (GitHub) → compare with `flake.lock` rev | eval untouched | ~2 API calls per ref, no clone | **Recommended** |
| (b) Record merge SHA by hand, check ancestry with a fetch in eval | not possible (§1) | full nixpkgs clone | Rejected; (b) only works as input to (a), replacing the PR lookup with a local `git merge-base --is-ancestor` |
| (c) `fixedIn` version | yes | none | Keep as the first choice when the fix ships in a known upstream release; it fails when the fix is a nixpkgs patch with no version bump |

## 4. Recommended design

Add a fourth condition, **`fixedBy = "NixOS/nixpkgs#N"`** (prefer the PR
number; an issue number is allowed but the checker reports "closed, fix commit
unknown" when it cannot find one):

```nix
pkgs.expiringOverride {
  pkg = prev.zotero;
  fixedBy = "NixOS/nixpkgs#572466";
  reason = "zotero needs Firefox ESR 140";
} (_: zoteroFromOlderNixpkgs)
```

- **Eval:** `expired = false` always; the override applies. `resolve` checks
  the string with a regex (`^[A-Za-z0-9-]+/[A-Za-z0-9._-]+#[0-9]+$`) and
  throws on a typo, which `tests/expiring-override.nix` can cover.
- **Collection:** overrides live in many overlays and Nix has no global
  registry, so the checker extracts references from the source with
  `git grep -oE 'fixedBy = "[^"]+"'`. The same token form can live in plain
  comments (the `nixpkgs-zotero` TODO in `flake.nix`), which a Nix-eval
  registry could not see. A strict single-line format keeps the grep exact.
- **Checker** (`just check-fixes`, run by hand or after `nix flake update`):
  1. `rev=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock)`.
  2. For each ref: `GET /repos/{o}/{r}/issues/N`. If it has `pull_request`,
     `GET /pulls/N`: not merged and open → "pending"; closed unmerged →
     "closed without merge, find the replacement PR"; merged → take
     `merge_commit_sha`. If it is a plain issue: use the `closed` event's
     `commit_id` if any, else report "issue state, fix commit unknown".
  3. `GET /compare/{sha}...{rev}?per_page=1`: `ahead`/`identical` → print
     "fixed in pinned nixpkgs, remove the override"; otherwise also compare
     against `nixos-unstable` and print "fixed upstream, run `nix flake
     update`" or "not in a channel yet".
  4. Read an optional `GITHUB_TOKEN` from the environment for the higher
     limit; the user supplies it (the agent sandbox hides `~/.config/gh`).
- **Why a warning is not emitted at eval:** the eval cannot know, and a
  warning on every eval ("check this") would be noise. ADR 0005's "a nixpkgs
  bump must not block a deploy" holds since the checker never fails a build.

## Open questions

- Should `fixedBy` be allowed **together with** `brokenAt`, so eval still
  nudges on a version change while the checker tracks the PR? This breaks the
  current "exactly one condition" rule.
- Wire the checker into `nix flake check`? It needs network, so only as a
  flake `app`, not a `checks` derivation.
- Backports to release branches are cherry-picks with new SHAs, so the
  ancestry test is only valid for nixos-unstable pins. Fine today; revisit if a
  host moves to a stable channel.
- PRs merged with "squash" or "rebase" report `merge_commit_sha` as the
  resulting commit on the base branch; assumed (not verified here) to be the
  commit that later reaches the channel unchanged.
- Unverified: whether GitHub GraphQL accepts unauthenticated calls (the test
  call was blocked). The design above uses REST only.
