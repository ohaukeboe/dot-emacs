# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
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

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
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
```

## Deploy

```bash
home-manager switch --flake .#default --impure -b backup  # standalone home-manager
sudo nixos-rebuild switch --flake .#<hostname>            # hosts: x13-laptop, work-laptop, desktop
```

## Key Paths

- `flake.nix` — entry point
- `workstation/home.nix` — main user config
- `workstation/emacs/config.org` — literate Emacs (source of truth)
- `machines/machines.nix` — machine registry
- `modules/` — optional feature modules (gaming, cosmic-de, secure-boot, sshd)
- secrets via **SOPS** (`workstation/sops.nix`, `sops/`)

## Gotchas

- Flake sees only **git-tracked** files — `git add` new files before `nix build`/`nix flake check` (else `"... is not tracked by Git"`).
- `default`/`oskar` config aliases use `builtins.currentSystem` (needs `--impure`); for a clean test build a concrete attr: `nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'`.
- `nix fmt` runs treefmt across **all** files — may reformat unrelated ones; revert stray churn before committing.
- `just update-sources` regenerates nvfetcher sources (`nvfetcher.toml` → `_sources/`), consumed via the `pkgs.nvSources` overlay. npm pkgs still need a manual `npmDepsHash` bump.
