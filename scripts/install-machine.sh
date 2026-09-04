#!/usr/bin/env bash
# Partition, install and seed a machine that has already been scaffolded and
# registered. Run it from the NixOS installer, after `just new-machine` and
# after editing machines/machines.nix.
#
#   ./scripts/install-machine.sh <hostname> [format|mount]
#
#     format  (default) destroy, format and mount the disk, then install
#     mount             mount the existing layout and install, for retrying a
#                       failed install without losing the partitioning
#
# THIS ERASES THE DISK declared in machines/<hostname>/disk.nix. See
# docs/new-machine.md for the steps either side of this one.
set -euo pipefail

DISKO=github:nix-community/disko/latest

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <hostname> [format|mount]" >&2
  exit 1
fi

host=$1
mode=${2:-format}

case $mode in
format | mount) ;;
*)
  echo "error: mode must be 'format' or 'mount', got '$mode'" >&2
  exit 1
  ;;
esac

cd "$(git rev-parse --show-toplevel)"

as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

die() {
  echo "error: $*" >&2
  exit 1
}

########################################
# Preflight — everything that can fail must fail before the disk is touched.
########################################

[[ -d machines/$host ]] || die "no machines/$host — run 'just new-machine $host <device>' first"

# The flake only sees git-tracked files, so an unadded machine directory would
# produce a confusing "is not tracked by Git" error partway through.
if [[ -n $(git ls-files --others --exclude-standard -- "machines/$host") ]]; then
  git ls-files --others --exclude-standard -- "machines/$host" >&2
  die "the files above are untracked; run 'git add machines/$host'"
fi

echo "Evaluating .#$host ..."
nix eval --raw ".#nixosConfigurations.\"$host\".config.networking.hostName" >/dev/null ||
  die "'.#$host' does not evaluate; is $host registered in machines/machines.nix?"

device=$(nix eval --raw ".#nixosConfigurations.\"$host\".config.disko.devices.disk.main.device" 2>/dev/null) ||
  die "$host declares no disko layout. This recipe would format a disk from a
config that does not describe it. desktop, work-laptop and x13-laptop predate
disko and must be installed by hand — see docs/new-machine.md."

username=$(nix eval --raw ".#nixosConfigurations.\"$host\".config.user.username")

[[ -b $device ]] || die "$device (from machines/$host/disk.nix) is not a block device"

# The shared host key is the root of everything else. Without it the installed
# system boots with nothing decryptable, and finding that out afterwards means
# starting over.
[[ -f /var/lib/sops-nix/keys.txt ]] ||
  die "/var/lib/sops-nix/keys.txt is missing; run 'just bootstrap' first"

# Probe once, and treat an unreadable device as fatal. Letting this fail
# silently would defeat the in-use check below, which is the last thing
# standing between a wrong device in disk.nix and a formatted system disk.
mounts=$(lsblk -nro MOUNTPOINTS "$device") || die "cannot read $device with lsblk"

# Refuse to format a disk that is currently in use, which on the installer
# almost always means the wrong device was declared.
if [[ $mode == format ]] && grep -qv '^$' <<<"$mounts"; then
  lsblk "$device" >&2
  die "$device has mounted partitions; unmount them or check disk.nix"
fi

########################################
# Confirm
########################################

echo
echo "About to install $host:"
echo
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS "$device"
echo
echo "  user:   $username"
echo "  mode:   $mode"
if [[ $mode == format ]]; then
  echo
  echo "This will ERASE $device completely. Every partition and all data on it"
  echo "will be destroyed. This cannot be undone."
else
  echo
  echo "Mount mode: the existing partitioning is kept and only mounted."
fi
echo
read -rp "Type the hostname ($host) to continue: " confirm
[[ $confirm == "$host" ]] || die "aborted"

########################################
# Partition and install
########################################

if [[ $mode == format ]]; then
  echo
  echo "==> Partitioning (you will be asked for the LUKS passphrase twice)"
  as_root nix run "$DISKO" -- --mode destroy,format,mount --flake ".#$host"
else
  echo
  echo "==> Mounting (you will be asked for the LUKS passphrase)"
  as_root nix run "$DISKO" -- --mode mount --flake ".#$host"
fi

mountpoint -q /mnt || die "disko did not leave a filesystem mounted at /mnt"

echo
echo "==> Installing (this takes a while; it asks for a root password at the end)"
as_root nixos-install --flake ".#$host" --root /mnt

########################################
# Seed the new root before it is unmounted
########################################

echo
echo "==> Setting the password for $username"
# nixos-install only sets root's. Without this there is no way in as the
# ordinary user, and the cosmic greeter offers no other account.
until as_root nixos-enter --root /mnt -c "passwd $username"; do
  echo "passwd failed; try again."
done

echo
echo "==> Installing the shared host age key"
# Everything else decrypts from this one, including the user's own copy, which
# modules/sops hands over as /run/secrets/host-age-key at activation.
as_root install -m600 -D /var/lib/sops-nix/keys.txt /mnt/var/lib/sops-nix/keys.txt

echo
echo "==> Copying this checkout to /home/$username/projects/dot-emacs"
target=/mnt/home/$username/projects/dot-emacs
if [[ -e $target ]]; then
  echo "already present, leaving it alone"
else
  as_root mkdir -p "$(dirname "$target")"
  as_root cp -a --no-target-directory . "$target"
  # A build symlink into the installer's store is dead on the new system.
  as_root rm -f "$target/result"
  as_root nixos-enter --root /mnt -c \
    "chown -R $username:users /home/$username/projects"
fi

echo
echo "==> Unmounting"
as_root umount -R /mnt

cat <<EOF

Installed. Reboot, remove the installer, and unlock with the LUKS passphrase.

lanzaboote enrolls the Secure Boot keys on the first activation and reboots once
by itself, so expect two boots before you reach a login prompt.

Then, logged in as $username:

  cd ~/projects/dot-emacs
  just finish-install $host
EOF
