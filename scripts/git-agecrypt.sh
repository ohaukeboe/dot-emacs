#!/usr/bin/env bash
# Resolve git-agecrypt for git's filter and diff drivers.
#
# The commands land in .git/config, so they have to stay valid in two states
# `git-agecrypt init` does not handle:
#
#   - a fresh checkout, before home-manager has put git-agecrypt on PATH —
#     which is exactly when `just agecrypt-init` runs;
#   - after a nix GC, which invalidates the absolute /nix/store path that
#     `git-agecrypt init` writes.
#
# So prefer PATH and fall back to nix-shell. The fallback pays a nix-shell
# startup per file; private/** is two files, so that is fine.
set -euo pipefail

if command -v git-agecrypt >/dev/null 2>&1; then
  exec git-agecrypt "$@"
fi

exec nix-shell -p git-agecrypt --run "git-agecrypt $(printf '%q ' "$@")"
