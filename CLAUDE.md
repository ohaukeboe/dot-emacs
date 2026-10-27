# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Project

Personal **NixOS + Home Manager** config (flakes). Started as an Emacs config
(hence the repo name); Emacs is literate org-mode in
`workstation/emacs/config.org` — **edit the `.org`, never generated `.el`**.

See **`AGENTS.md`** for the full guide (code style, module/machine patterns, structure).

## Build & Test

```bash
nix fmt                                              # format (nixfmt/shfmt/toml-sort) — run before commit
nix flake check                                      # validate flake
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'  # test build, no activate
nix build .#test-disk-layout -L                      # VM test of the disko layout (slow)
```

## Deploy

```bash
sudo nixos-rebuild switch --flake .#<hostname>  # hosts: attribute names in machines/machines.nix
```

## Key Paths

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
- Claude Code's shell commands run in its sandbox (`workstation/agents/sandbox.nix`, `docs/adr/0004-agent-sandbox-policy.md`): credentials and the docker/libvirt/keyring/session-bus sockets (plus the main ssh-agent once `agents.sandbox.signing` is on) are hidden and `$HOME` is read-only except `~/.cache/nix`. Widen per project in `.claude/settings.local.json`; `agent-sandbox-probe`, run by the agent, verifies it.

## Agent skills

### Issue tracker

Issues live in **beads (bd)**, a local Dolt-backed tracker — not GitHub Issues. See `docs/agents/issue-tracker.md`.

Task tracking and memory: `bd` (rules come from `bd prime` at session start; built-in task tools are denied).

### Triage labels

Default five-role vocabulary, applied as bd labels. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
