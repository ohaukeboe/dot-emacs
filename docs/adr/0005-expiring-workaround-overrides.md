# ADR 0005 — Workaround overrides carry an expiry condition

**Status:** Accepted (2026-10-23)

## Context

Several overrides in this configuration exist only because a package in the
pinned nixpkgs is broken, flaky or lagging upstream: test suites disabled on
`anyio`, `cyclopts`, `python-lsp-ruff` and others, a `postPatch` on `sops.el`,
a newer tree-sitter-kotlin grammar, a relaxed pydantic pin for kagimcp. Each
had a "remove when nixpkgs ships a fix" comment, and nothing ever prompted
anyone to check. Such overrides outlive their reason, mask regressions (a test
suite skipped for one flake hides the next real failure) and keep building
derivations nobody else uses.

[Nix overrides that expire themselves](https://jezenthomas.com/2026/07/nix-overrides-that-expire-themselves/)
describes the fix: compare the package in nixpkgs against a condition at
evaluation time and emit a warning with `lib.warnIf`. Its examples are
`lib.versionAtLeast` against a known fix release, and checking whether
`meta.broken` is still set.

## Decision

**Every workaround override goes through `pkgs.expiringOverride` (or the
`pkgs.expiringSkipTests` shorthand) and states exactly one expiry condition.**
Preference overrides (`LSP_USE_PLISTS`, Lutris `extraPkgs`) stay plain; they
never expire. The terms are defined under "Package overrides" in `CONTEXT.md`.

Three conditions, because the blog's version check alone fits almost none of
the existing overrides:

- **fixed-in** — the blog's case. When nixpkgs reaches the release, the
  override is dropped and a warning says to delete it.
- **broken-at** — the default. Records the version observed broken; any other
  version in nixpkgs warns, but the override keeps applying. Flaky tests and
  unreleased fixes have no fix version to name in advance, and dropping the
  override on a guess would turn a nagging warning into a broken rebuild.
- **while-marked-broken** — the blog's `meta.broken` case. When nixpkgs drops
  the flag, the override is dropped.

**Expiry is a warning, never a `throw`.** A nixpkgs bump must not block a
deploy; the warning shows in `nixos-rebuild` and `nix flake check`, where it is
seen.

Workarounds that are not an override of a nixpkgs package, such as kagimcp's
`pythonRelaxDeps`, use a hand-written `lib.warnIf` in the same wording, keyed
on the narrowest fact available (here, the pin in upstream's `pyproject.toml`).

## Consequences

- broken-at warns on every version bump of the package, including bumps that
  fix nothing. That is the intended cost: each warning means one build without
  the override, then either deleting it or bumping `brokenAt`.
- MELPA packages version by date, so broken-at on `sops` warns on every
  upstream commit. Its `--replace-fail` still fails the build if the patched
  line itself changes.
- The check is only as good as the pinned evaluation: an override applied to a
  package outside this flake's nixpkgs (another overlay's version) compares
  against that version, not nixpkgs'.
- `tests/expiring-override.nix` tests the expiry decision through `resolve`,
  which returns the decision and message without emitting the warning, so
  `nix flake check` stays quiet while it passes.

## Amendment (2026-10-23): fix references are checked outside evaluation

A workaround can now carry a **fix reference** (`CONTEXT.md`): the nixpkgs PR
or issue whose change should make it obsolete, written `owner/repo#N`. On an
override it is the `fixedBy` field, alone or next to one expiry condition;
elsewhere, such as the pinned `nixpkgs-zotero` input in `flake.nix`, it is a
`# fixedBy:` comment. Evaluation only validates its format and names it in
expiry warnings. An override with only a fix reference always applies.

This reverses the Decision's "exactly one expiry condition": an override now
states at most one expiry condition and at least one of an expiry condition or
a fix reference.

Whether the fix has landed is decided by `just check-fixes` (also
`nix run .#check-fixes`), run by hand after `nix flake update`. It asks GitHub
for the fixing commit and whether the `rev` pinned in `flake.lock`, or else
nixos-unstable, contains it, and reports without ever failing a build. This
cannot happen at evaluation time: pure evaluation has no network, and the
pinned channel tarball carries no git history, so commit ancestry is not
decidable there (`docs/nixpkgs-issue-expiry-research.md`).

Prefer the fixing PR over the issue. In nixpkgs an issue often does not lead
to the commit that fixed it: zotero's comment named PR #569006, which was
closed unmerged, and issue #568692, which was closed by hand, while the fix
that landed was #572466. A closed issue with no linked commit is reported as
unknown.
