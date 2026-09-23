# Workstation Config Constitution

## Core Principles

### I. Evaluation-Time Verification (NON-NEGOTIABLE)

This repository has no broad runtime test suite and will not grow one; the only
cheap, always-available verifier is Nix evaluation. Therefore every class of
mistake that *can* be made to fail during `nix build` / `nix flake check` MUST
be made to fail there.

- Every configurable value MUST be declared as a typed `mkOption` with the
  narrowest type that fits (`types.enum`, `types.port`, `types.path`,
  a submodule) — never `types.str` or `types.attrs` where a narrower type
  expresses the same constraint.
- Preconditions that evaluation cannot infer MUST be written as `assertions`
  (or `lib.throwIf` / `lib.warnIf`) next to the option that needs them, with a
  message naming the file and the fix.
- Cross-cutting invariants (a machine registry entry without a matching
  directory, a module enabled without its prerequisite) MUST be asserted in the
  code that composes them, not documented in prose.
- Shell code MUST be built through `writeShellApplication` so `shellcheck` runs
  at build time; loose `.sh` files are permitted only under `scripts/` and MUST
  be pulled in by a `writeShellApplication` wrapper.
- Reference executables via `lib.getExe` / `${pkg}/bin/...` rather than bare
  names, so a missing dependency is an evaluation error instead of a
  `command not found` on a live machine.

Rationale: a mistake caught by evaluation costs seconds; the same mistake caught
after `nixos-rebuild switch` costs a broken workstation and a rollback.

### II. Determinism and Reproducibility (NON-NEGOTIABLE)

The same commit MUST evaluate to the same derivations on every machine, at any
time, for any user.

- All external sources MUST be pinned by hash: flake inputs with a committed
  `flake.lock`, or nvfetcher entries in `nvfetcher.toml` regenerated into
  `_sources/generated.nix`. Unpinned `fetchTarball`/`fetchGit` without a hash is
  forbidden.
- Evaluation MUST NOT read ambient state: no `builtins.currentTime`, no
  `builtins.getEnv`, no reading files outside the flake source tree. The single
  tolerated exception is the `default` / `oskar` `homeConfigurations` aliases
  that use `builtins.currentSystem` and therefore require `--impure`; concrete
  system attributes MUST stay pure and MUST be what CI-style checks build.
- New files MUST be `git add`ed before building — the flake sees only
  git-tracked files, and an untracked file is a build that only works locally.
- Machine-to-machine differences MUST be expressed as data in
  `machines/machines.nix` or `machines/<hostname>/`, never as untracked local
  edits, environment variables, or manual post-install steps that are not in a
  `just` recipe.
- A version bump of an nvfetcher npm package MUST also update its
  `npmDepsHash` (and lockfile) in the same change; nvfetcher hashes only the
  source tarball.

Rationale: three machines share one configuration. Any nondeterminism means the
configuration is really three configurations that happen to agree today.

### III. Fast Default Gate, Heavy Tests Opt-In

`nix flake check` is run before every commit and MUST stay fast enough that this
stays true.

- `checks.*` MUST contain only cheap, evaluation- or lint-level verification
  (formatting, shellcheck, assertion-triggering evaluations).
- Anything that builds a large closure or boots a VM MUST be exposed as a
  `packages.*` attribute, not a check, and MUST carry a comment stating the
  exact command to run it and when to run it — as `test-disk-layout` and
  `test-emacs-sops-save` already do.
- When a bug is fixed that evaluation could not have caught, the change MUST
  either add an evaluation-level guard (Principle I) or add a targeted
  `packages.*` regression test referencing the issue id. Fixing it with neither
  is not a complete fix.

Rationale: a slow gate gets skipped, and a skipped gate verifies nothing.

### IV. Single Source of Truth

Each fact lives in exactly one place, and generated artifacts are never edited.

- Emacs configuration is `workstation/emacs/config.org`. Generated `.el` output
  MUST NOT be edited.
- `_sources/generated.nix` is nvfetcher output; change `nvfetcher.toml` and run
  `just update-sources`.
- `machines/machines.nix` is the machine registry; a machine that is not there
  does not exist.
- The username MUST be read from `config.user.username`; the literal `"oskar"`
  MUST NOT appear in module or workstation code.
- Domain terms are defined once in `CONTEXT.md`; decisions with lasting
  consequences are recorded as an ADR under `docs/adr/`. A change that
  contradicts an ADR MUST supersede it in the same change.
- Secrets are SOPS (`sops/**`), private-but-not-secret data is git-agecrypt
  (`private/**`). Anything whose disclosure is harmful MUST NOT go through
  git-agecrypt, because `private/**` lands world-readable in the Nix store.

Rationale: duplicated facts diverge silently, and a divergence in a machine
configuration is discovered at boot.

### V. Toggleable Modules, Declarative Machines

Optional functionality is a module; machines are compositions of toggles.

- A feature module lives at `modules/<name>/default.nix`, declares
  `mkEnableOption`, wraps **all** of its config in `mkIf cfg.enable`, and is
  imported through `modules/default.nix`.
- A disabled module MUST contribute nothing: no packages, no services, no files,
  no assertions that fire when it is off.
- Machine-specific behaviour that is not a module toggle belongs in
  `machines/<hostname>/config.nix`; forking a shared module for one machine is
  forbidden.
- Modules MUST NOT depend on another module's internals — only on its declared
  options, guarded by an assertion when the dependency is required.

Rationale: every machine evaluates every module. Inert-when-disabled is what
makes adding a module safe for the two machines that do not want it.

## Additional Constraints

- **Formatting**: `nix fmt` (treefmt: nixfmt, shfmt, toml-sort) MUST be clean
  before commit. `nix fmt` touches the whole tree — unrelated reformatting MUST
  be reverted out of the change rather than committed along with it.
- **Commits**: Conventional Commits, as specified in `AGENTS.md`.
- **Destructive operations**: any script that partitions, formats, rotates keys
  or writes outside the Nix store MUST be re-runnable, MUST refuse rather than
  guess when its preconditions are unmet, and MUST state what it will destroy
  before doing it.
- **Documentation parity**: `AGENTS.md` and `CLAUDE.md` are independent files.
  A substantive edit to one MUST be mirrored in the other.
- **Issue tracking**: work is tracked in beads (`bd`). Markdown TODO lists and
  ad-hoc task files MUST NOT be used for tracking.
- **Platform scope**: NixOS is the only tested target. Standalone
  `homeConfigurations` exist as build checks and MUST keep evaluating, but
  setup documentation for non-NixOS hosts MUST NOT be added unasked.

## Development Workflow

Required loop for any change to Nix, shell, or Emacs configuration:

1. `git add` every new file (the flake sees only tracked files).
2. `nix fmt`, then revert unrelated formatting churn.
3. `nix flake check` — MUST pass.
4. Build the affected configuration without activating, for example
   `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`
   or `nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'`.
5. Run the targeted heavy test when the change touches its area:
   `nix build .#test-disk-layout -L` for `lib/disk-layouts/`,
   `nix build .#test-emacs-sops-save -L` for the sops/Emacs overlay.
6. Deploy with `sudo nixos-rebuild switch --flake .#<hostname>` only after
   steps 3 and 4 pass.

A change that cannot complete steps 3 and 4 is not ready, regardless of how it
behaves on the machine it was written on.

## Governance

This constitution supersedes conflicting guidance in `AGENTS.md`, `CLAUDE.md`,
and skill definitions. Where those files give more detail, they MUST remain
consistent with the principles here; where they conflict, this file wins and the
other file MUST be corrected.

**Amendment procedure**: amendments are made by editing this file in a commit
that states the version bump and its rationale. An amendment that removes or
weakens a principle MUST record why the previously governed failure mode is no
longer a risk.

**Versioning policy**: semantic versioning.
- MAJOR — a principle is removed, or redefined in a way that makes previously
  compliant configuration non-compliant.
- MINOR — a principle or section is added, or its guidance is materially
  expanded.
- PATCH — clarification, wording, or typo fixes with no change in obligation.

**Compliance review**: every change is reviewed against Principles I–V before
commit. The two questions that MUST be answered for any non-trivial change are:
*could evaluation have caught this class of error, and does it now?* and *does
this evaluate identically on the other two machines?* Complexity that violates a
principle is permitted only with an ADR under `docs/adr/` recording the
trade-off.

**Version**: 1.0.0 | **Ratified**: 2026-09-23 | **Last Amended**: 2026-09-23
