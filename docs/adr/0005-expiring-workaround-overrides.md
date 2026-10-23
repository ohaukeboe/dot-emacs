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
