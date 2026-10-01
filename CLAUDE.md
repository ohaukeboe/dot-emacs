# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:46cd31e7 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Project

Personal **NixOS + Home Manager** config (flakes). Started as an Emacs config
(hence the repo name); Emacs is literate org-mode in
`workstation/emacs/config.org` (133K) — **edit the `.org`, never generated `.el`**.

See **`AGENTS.md`** for the full guide (code style, module/machine patterns, structure).

## Build & Test

```bash
nix fmt                                              # format (nixfmt/shfmt/toml-sort) — run before commit
nix flake check                                      # validate flake
nix build .#homeConfigurations.default.activationPackage  # test build, no activate
nix build .#test-disk-layout -L                      # VM test of the disko layout (slow)
```

## Deploy

```bash
sudo nixos-rebuild switch --flake .#<hostname>  # hosts: x13-laptop, work-laptop, desktop
```

## Key Paths

- `flake.nix` — entry point
- `workstation/home.nix` — main user config
- `workstation/emacs/config.org` — literate Emacs (source of truth)
- `machines/machines.nix` — machine registry
- `modules/` — optional feature modules (gaming, cosmic-de, secure-boot, sshd)
- secrets via **SOPS** (`workstation/sops.nix`, `sops/`); low-sensitivity private
  data via **git-agecrypt** (`private/`, `git-agecrypt.toml`) using the same age keys
- one shared host age key for all machines, committed encrypted as
  `sops/bootstrap/host-key.yaml`; `nix run github:ohaukeboe/dot-emacs#install`
  from the installer ISO runs the whole install; `just bootstrap` provisions a new machine (only
  step needing the YubiKey)

## Gotchas

- Flake sees only **git-tracked** files — `git add` new files before `nix build`/`nix flake check` (else `"... is not tracked by Git"`).
- `default`/`oskar` config aliases use `builtins.currentSystem` (needs `--impure`); for a clean test build a concrete attr: `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`.
- Only NixOS is tested. Standalone `homeConfigurations` still exist (build checks, future non-NixOS use) but have no setup docs — don't add any unasked.
- `nix fmt` runs treefmt across **all** files — may reformat unrelated ones; revert stray churn before committing.
- `just update-sources` regenerates nvfetcher sources (`nvfetcher.toml` → `_sources/`), consumed via the `pkgs.nvSources` overlay. npm pkgs still need a manual `npmDepsHash` bump.

## Agent skills

### Issue tracker

Issues live in **beads (bd)**, a local Dolt-backed tracker — not GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, applied as bd labels. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
