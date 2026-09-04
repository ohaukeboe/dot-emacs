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
   LUKS unlock in step 8 depends on it.
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

and registers the machine in `machines/machines.nix` with `cosmic-de` enabled.

Now edit `machines/machines.nix` for what this machine actually wants —
`gaming`, `sshd`, `sleep-then-hibernate`, a `nixos-hardware` profile. If you
enable `sleep-then-hibernate`, also point its swapfile at the dedicated
subvolume so no snapshot ever covers it:

```nix
modules.sleep-then-hibernate.swapFile = "/swap/swapfile";
```

Then:

```sh
nix fmt
git add -A          # the flake only sees git-tracked files
```

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
2. Shows the disk and asks you to type the hostname to confirm.
3. `disko --mode destroy,format,mount` — prompts for the LUKS passphrase twice.
4. `nixos-install` — prompts for a root password at the end. Set one; it is your
   way back in if the user account or the greeter misbehaves.
5. `passwd <user>` inside the new root. `nixos-install` only sets root's and
   `common/system/system.nix` declares no user password, so without this the
   machine boots to a login prompt you cannot get past.
6. Copies `/var/lib/sops-nix/keys.txt` onto the new root, and this checkout to
   `~/projects/dot-emacs`.
7. Unmounts.

If `nixos-install` fails partway, retry without losing the partitioning:

```sh
just install-machine <hostname> mount
```

Then reboot and remove the installer.

## 6. First boot

1. Unlock LUKS with the passphrase from the install.
2. lanzaboote enrolls the Secure Boot keys and reboots once by itself, so expect
   two boots before a login prompt.
3. Log in as the user, with the password from step 5.

## 7. Finish

```sh
cd ~/projects/dot-emacs
just finish-install <hostname>
```

Re-runnable, and nothing in it is destructive. It runs `just agecrypt-init` (the
identities live in `.git/config`, which is per-checkout and did not survive the
copy), switches `origin` from HTTPS to SSH now that a key is decryptable, joins
Tailscale, rebuilds in place, and reports `bootctl status` and `sbctl verify`.

Expect `Secure Boot: enabled (user)`. Anything else means the firmware was not
in Setup Mode — see below.

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
1Password, mail — and, optionally, TPM unlock below.

## 8. Optional: TPM-backed LUKS unlock

Only worth doing once the machine is known good, and only if you would rather
type a short PIN than the full passphrase at every boot.

Check the TPM is usable at all:

```sh
/run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported
```

If that says anything but `yes`, stop — this machine cannot do it.

Enable measured boot for the machine in `machines/machines.nix`:

```nix
{ modules.secure-boot.measuredBoot.enable = true; }
```

then `sudo nixos-rebuild boot` and reboot. That drops the generation limit from
10 to 8, which systemd-pcrlock enforces and the module handles for you.

Enroll, once:

```sh
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-with-pin=true \
  --tpm2-pcrlock=/var/lib/systemd/pcrlock.json \
  /dev/nvme0n1p2
```

`--tpm2-with-pin=true` is deliberate: upstream is explicit that an attended
machine should require a user secret alongside the TPM, or an attacker with the
powered-off laptop has the disk.

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
