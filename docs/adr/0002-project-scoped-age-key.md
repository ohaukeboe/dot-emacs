# ADR 0002 — Project-scoped age key for scaffolded project secrets

**Status:** Accepted (2026-09-16), implemented 2026-09-23

## Context

`nix-init` gained an optional **secrets backend** (see `CONTEXT.md`) that any
scaffolded project can carry. Two of the three backends — `sops` and
`secretspec`, the latter driving sops underneath — encrypt a file that is
committed to the project's own repository. Every such file needs an age
recipient, and that recipient's private key must be present on each machine
that clones the project.

This repository already has age keys, declared in `workstation/sops.nix` as
`ageKeyFiles`:

- `default` — the **shared host key**, identical on every machine, installed
  from `sops/bootstrap/host-key.yaml` by `just bootstrap-host-key`.
- `tpm`, `yubikey-wallet`, `yubikey-home` — hardware escape hatches.

The root `.sops.yaml` names two recipients, the shared host key and a YubiKey
FIDO key, and its creation rules cover `sops/(home|bootstrap)/*` only. Nothing
in the existing setup contemplates encrypting files that live outside this
repository.

The shared host key is the obvious candidate, because it is already on every
machine and a scaffolded project would decrypt with zero setup. The question is
whether it *should* be.

## Decision

Scaffolded projects encrypt to a **third age key, scoped to projects**, kept
separate from both the shared host key and the hardware keys.

1. `nix-init` writes a project `.sops.yaml` naming that recipient, substituted
   from the `nix-init-sops-recipient` defcustom. When unset it writes a
   placeholder and says so, rather than falling back to another key.
2. The scaffolder **never generates key material**. It writes configuration
   that references a key and prints next steps; creating the key, and deciding
   where it lives, stays a deliberate act.
3. The private half is distributed the way the existing keys are: a `projects`
   entry in `ageKeyFiles`, stored in `sops/home/secrets.yaml`, rendered to
   `~/.config/sops/age/projects.txt`.
4. sops is told about it through `SOPS_AGE_KEY_CMD`, a second identity source
   alongside the `SOPS_AGE_KEY_FILE` that names the host key. sops unions the
   identities it finds across its sources, so a project decrypts with the
   projects key without this repository losing the host key. A justfile
   variable would not reach devenv, which resolves secretspec while direnv is
   still entering the directory.

## Consequences

- (+) A project repository never carries the key that provisions machines.
  Handing someone a project clone, or pushing it to a host you do not control,
  does not widen the host key's reach.
- (+) The two keys rotate independently. Re-keying projects does not touch
  machine bootstrap, and vice versa.
- (+) Fits the shape `workstation/sops.nix` already has — a fourth entry in a
  table of four, not a new mechanism.
- (−) A second distribution path to maintain, and a machine that has the host
  key but not the projects key fails at decryption rather than at setup.
- (−) Rotation is genuinely expensive once projects exist: every scaffolded
  repository must be re-encrypted, and this repository does not know which
  those are.
- (−) Both keys are now ambient for every sops invocation, this repository's
  included. The boundary is what a project repo *carries* and what rotates
  together, not which identity a given process could reach.

## Alternatives rejected

- **Reuse the shared host key.** Zero setup, and tempting for exactly that
  reason. Rejected because the host key's stated design is that its reach is
  every machine; extending it to every project as well removes the only
  boundary it has, and makes one compromise read both infrastructure and
  project secrets. It also makes host-key rotation touch every project ever
  scaffolded.
- **A fresh key per project.** The tightest blast radius, but every project
  becomes a manual key-generation step, and the keys accumulate with no
  inventory. Remains available: set `nix-init-sops-recipient` per project via
  directory-local variables.
- **Generate the key during scaffolding.** Rejected on the same grounds as the
  scaffolder's no-key-material rule: generated key material whose location the
  tool chose, and whose loss is unrecoverable, is not something a scaffolder
  should create as a side effect.
