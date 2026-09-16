# Provisioning a new NixOS machine

From bare hardware to a machine that rebuilds itself from this flake. Four
commands do the work — `just bootstrap`, `just new-machine`, `just
install-machine`, `just finish-install` — but read step 1 before touching the
machine. Preparing the firmware is the one thing no recipe can do for you, and
skipping it is not recoverable in place.

`AGENTS.md` covers adding a machine *to the repo*. This covers installing it.

## What you need

- The **wallet** YubiKey. It is needed exactly once, in step 3, to unwrap the
  shared host age key. Nothing after that touches it.
- The target disk. This procedure **erases it completely** — disko formats the
  whole device, and dual-booting is not supported.
- Network on the installer.

## 1. Firmware, before booting anything

1. UEFI boot, CSM/legacy disabled.
2. TPM 2.0 enabled. `modules/sops` sets `security.tpm2.enable`, and TPM-backed
   LUKS unlock (step 8) depends on it.
3. **Put Secure Boot into Setup Mode** — the firmware menu calls it "Erase all
   Secure Boot settings", "Delete platform key (PK)", "Clear Secure Boot keys",
   or "Custom mode". Leave Secure Boot itself enabled.

Step 3 is the one that bites. `lib/mkNixosConfiguration.nix` defaults
`enableSecureBoot` to `true`, which turns on `modules/secure-boot`, which sets
`boot.lanzaboote.autoEnrollKeys` with `autoReboot`. Enrolling keys is only
possible while the platform key is absent, so a machine whose firmware still
holds the vendor PK cannot complete enrollment. See the fallback at the end of
step 7 if
your firmware has no way to clear it.

## 2. Boot the installer and get the repo

Boot the NixOS minimal or graphical ISO, get on the network, then:

```sh
sudo -i
export NIX_CONFIG='experimental-features = nix-command flakes'
nix-shell -p git just

# HTTPS, not SSH: the SSH key lives in sops, which is not readable yet.
git clone https://github.com/ohaukeboe/dot-emacs
cd dot-emacs
```

## 3. Install the shared host age key

```sh
just bootstrap        # = bootstrap-host-key + agecrypt-init
```

Insert the wallet YubiKey when prompted. This decrypts
`sops/bootstrap/host-key.yaml` into `~/.config/sops/age/keys.txt` and
`/var/lib/sops-nix/keys.txt`, then installs the git-agecrypt filters and
re-checks out `private/**` as plaintext.

The YubiKey is read through `pcscd`, which the installer image does not run and
which `services.pcscd.enable` only turns on after the first `nixos-rebuild`. The
script handles that itself: it starts `pcscd.socket` if the unit exists, else
runs a temporary `pcscd` from nixpkgs (with the `ccid` driver directory) and
stops it again on exit. If the card is still not found, something else holds it
— `gpgconf --kill scdaemon` and retry.

**This must happen before any `nix build` or `nix eval` against the flake.**
`flake.nix` reads `private/hosts.json` with `builtins.fromJSON` at evaluation
time; while that file is still ciphertext, every evaluation fails.

## 4. Scaffold the machine

```sh
lsblk                                        # pick the whole disk, not a partition
just new-machine <hostname> /dev/nvme0n1
```

This creates `machines/<hostname>/` with:

- `disk.nix` — the disko layout from `lib/disk-layouts/luks-btrfs.nix`, bound to
  that device
- `hardware-configuration.nix` — `nixos-generate-config --no-filesystems`, so
  hardware detection only. disko owns `fileSystems`, `swapDevices` and the LUKS
  mapping; leaving the generated stanzas in would collide with it.
- `default.nix` importing both

and registers the machine in `machines/machines.nix` with `cosmic-de` and
`modules.attic.push.enable` on, and `stateVersion` set to the release of the
nixpkgs this flake pins.

If `systemd-pcrlock is-supported` says `yes` on the installer, the script also
asks whether the disk should unlock with the TPM at boot. Answering yes adds
`modules.secure-boot.measuredBoot.enable` to the entry, and step 7 then enrolls
the disk — see step 8 for what that means.

`modules.attic.push.enable` makes the machine upload what it builds instead of
only pulling. **Remove that line if this is a work machine** — the push hook
uploads everything the Nix daemon builds, dependencies fetched with work
credentials included.

Now edit `machines/machines.nix` for what this machine actually wants —
`gaming`, `sshd`, `sleep-then-hibernate`, a `nixos-hardware` profile.

Then:

```sh
nix fmt
git add -A          # the flake only sees git-tracked files
```

### Join the tailnet first

Optional, and worth the two minutes. The private attic cache holds everything
this household has already built — the Emacs overlay, the nvfetcher npm
packages, every patched derivation — and it answers on the tailnet only. Off
the tailnet, the installer builds all of it from source.

```sh
just tailnet-up
```

The installer runs no `tailscaled`: `services.tailscale.enable` is part of the
system config, which is what the install is about to produce. So the recipe
starts a temporary one from nixpkgs and leaves it running for the rest of the
install; it ends at the next reboot. `just tailnet-status` reports without
joining.

Skipping this costs nothing but build time — step 5 probes each cache and uses
the ones that answer.

## 5. Install

```sh
just install-machine <hostname>
```

One command for what used to be steps 5 through 7. It reads the target device
from `machines/<hostname>/disk.nix` — you never retype it, so it cannot
disagree with the config — then:

1. Refuses unless the machine has a disko layout, its files are git-tracked, the
   config evaluates, and `/var/lib/sops-nix/keys.txt` exists. It also refuses to
   format a disk with mounted partitions, which is what a wrong device in
   `disk.nix` looks like. Everything that can fail, fails before the disk is
   touched.
2. Probes every substituter the machine is configured with — the list comes from
   its own `nix.settings`, so `common/caches.nix` stays the one place they are
   written — and prints which answered. The reachable ones are passed to
   `nixos-install`, which otherwise builds with the installer's own Nix
   settings and so would use cache.nixos.org alone. If the private one is listed
   as `skipped`, abort at the confirmation prompt, run `just tailnet-up`, and
   start again.
3. Shows the disk, asks you to type the hostname to confirm, then collects the
   LUKS passphrase, the root password and the user password. Nothing after this
   point prompts, so the long part of the install runs unattended.
4. `disko --mode destroy,format,mount`, with the passphrase handed over through
   the layout's `passwordFile` (removed again when the script exits).
5. `nixos-install --no-root-passwd`.
6. Sets both passwords inside the new root. Root's is your way back in if the
   user account or the greeter misbehaves; without the user's the machine boots
   to a login prompt you cannot get past, since `common/system/system.nix`
   declares no password.
7. Copies `/var/lib/sops-nix/keys.txt` onto the new root, and this checkout to
   `~/projects/dot-emacs`.
8. Unmounts.

If `nixos-install` fails partway, retry without losing the partitioning:

```sh
just install-machine <hostname> mount
```

Then reboot and remove the installer.

## 6. First boot

1. Unlock LUKS with the passphrase from the install.
2. lanzaboote enrolls the Secure Boot keys and reboots once by itself, so expect
   two boots before a login prompt.
3. Log in as the user, with the password you set during the install.

## 7. Finish

```sh
cd ~/projects/dot-emacs
just finish-install <hostname>
```

Re-runnable, and nothing in it is destructive. It runs `just agecrypt-init`
(the identities live in `.git/config`, and the copy carried over the
installer's root-owned paths, which this user cannot read; the recipe drops
those and registers `/run/secrets/host-age-key` instead), switches `origin`
from HTTPS to SSH now that a key is decryptable, joins
Tailscale, rebuilds in place, enrolls the disk for TPM unlock (step 8), and
reports `bootctl status` and `sbctl verify`.

Expect `Secure Boot: enabled (user)`. Anything else means the firmware was not
in Setup Mode — see below.

From here on the machine rebuilds itself with a bare `sudo nixos-rebuild switch`
(or the `nrs` alias) from any directory: `/etc/nixos/flake.nix` points at this
checkout and the attribute comes from the hostname.

**If Secure Boot enrollment failed**, the firmware was not in Setup Mode.
Register the machine with

```nix
<hostname> = {
  stateVersion = "24.11";
  enableSecureBoot = false;
  modules = [ ... ];
};
```

install that, then clear the platform key from firmware, drop the line, and
`nixos-rebuild switch`. `enableSecureBoot` is a parameter of
`lib/mkNixosConfiguration.nix`, so it goes alongside `stateVersion` rather than
inside `modules`.

What is left is restoring whatever this flake does not manage — Nextcloud,
1Password, mail.

## 8. Optional: TPM-backed LUKS unlock

The disk unlocks at boot with no input, from a TPM policy that
systemd-pcrlock maintains. There is **no PIN**: whoever holds the powered-off
machine gets as far as the login screen, so disk encryption then protects only
a removed disk, not a stolen laptop.

A machine opts in with `modules.secure-boot.measuredBoot.enable` in
`machines/machines.nix`. `just new-machine` asks, and adds the line if you
answer yes. Enabling it lowers the generation limit from 10 to 8, which
systemd-pcrlock enforces and the module handles for you.

Enrollment is `just tpm-enroll` (`scripts/tpm-enroll.sh`), which
`just finish-install` runs after its rebuild. It skips, without failing, when:

- measured boot is off for the machine,
- `systemd-pcrlock is-supported` says anything but `yes`,
- `bootctl status` does not show `Secure Boot: enabled (user)` — PCR 7 measures
  the Secure Boot keys, so enrolling before lanzaboote's keys are in place would
  lock to the wrong state,
- `/var/lib/systemd/pcrlock.json` does not exist yet, or
- the LUKS device behind `/dev/mapper/crypted` already has a `tpm2` slot.

Otherwise it runs, asking once for the LUKS passphrase:

```sh
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrlock=/var/lib/systemd/pcrlock.json \
  /dev/<luks partition>
```

To opt in an existing machine: add the line, `sudo nixos-rebuild switch`, reboot,
then `just tpm-enroll`.

**Keep the passphrase.** systemd-pcrlock is still experimental upstream, and if
its policy ever fails to validate the passphrase is the only way back in.

You should not have to enroll again. lanzaboote regenerates the measurements and
updates the TPM policy on every `nixos-rebuild`, which is the whole point of
using a pcrlock policy rather than binding to static PCR values — those change
on firmware updates and Secure Boot key changes, and would mean re-enrolling by
hand each time.

## Where the age keys come from

Neither sops module generates a key — `workstation/sops.nix` sets
`sops.age.generateKey = false` and both set `sops.age.sshKeyPaths = [ ]`. They
only point at a path that must already exist. So exactly one key is seeded by
hand, by `just install-machine`:

    /var/lib/sops-nix/keys.txt          the shared host key, copied from the installer

Everything else follows from it. `sops/bootstrap/host-key.yaml` lists that key
as a recipient of itself (see the comment in `.sops.yaml`), so the system can
decrypt its own key material and hand a user-readable copy over as a secret:

    /run/secrets/host-age-key           owner oskar, mode 0400

`modules/sops` points `home-manager.users.<user>.sops.age.keyFile` at that,
which is why a NixOS machine needs no age key in the home directory at all.
The CLI side follows the same path: `workstation/sops.nix` exports
`SOPS_AGE_KEY_FILE` from that option for bare `sops` invocations, and
`scripts/sops-identity.sh` (behind the `just sops-*` recipes) falls back to
`/run/secrets/host-age-key` when `~/.config/sops/age/keys.txt` is absent. So on
an installed machine `just bootstrap-host-key` is only needed again after
`just sops-rotate-host-key`, when `/var/lib/sops-nix/keys.txt` still holds the
old key; otherwise re-running it is harmless but pointless.

Two cases keep the older home-directory layout:

- **Standalone Home Manager** (non-NixOS) — no `/run/secrets`, so it reads
  `~/.config/sops/age/keys.txt` as installed by `just bootstrap-host-key`.
- **`sops.ageKey` set to `tpm` or a `yubikey-*` value** — the bootstrap file is
  encrypted to the wallet YubiKey and the shared host key only, so a TPM-keyed
  machine cannot decrypt it. Under those settings the secret is not declared and
  Home Manager falls back to `~/.config/sops/age/keys.txt`.

## Notes on the existing machines

`desktop`, `work-laptop` and `x13-laptop` predate disko and keep their generated
`hardware-configuration.nix`, whose `fileSystems` entries are matched by UUID.
Adding a `disk.nix` to one of them would define those same options twice and
fail to evaluate. Migrating a machine means removing the filesystem, LUKS and
swap stanzas from its `hardware-configuration.nix` in the same change — and the
subvolume names must already match `lib/disk-layouts/luks-btrfs.nix`, which
`work-laptop` and `x13-laptop` (flat btrfs, no subvolumes) do not.
