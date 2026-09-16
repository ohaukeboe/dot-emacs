#!/usr/bin/env bash
# Scaffold and register a new machine in the flake.
#
# Creates machines/<hostname>/ with a disko disk layout and a hardware config
# limited to hardware detection, registers the machine in machines/machines.nix
# and git adds the result. Run it on the machine itself: the hardware config
# comes from nixos-generate-config, which probes the running system.
#
# See docs/new-machine.md for the surrounding install procedure.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <hostname> <device>" >&2
  echo "  e.g. $0 thinkpad /dev/nvme0n1" >&2
  exit 1
fi

hostname=$1
device=$2

cd "$(git rev-parse --show-toplevel)"
dir="machines/$hostname"

[[ -e $dir ]] && {
  echo "error: $dir already exists" >&2
  exit 1
}

# A partition here would silently produce a layout that eats the wrong thing at
# install time, so insist on a whole disk.
[[ -b $device ]] || {
  echo "error: $device is not a block device — see 'lsblk'" >&2
  exit 1
}

mkdir -p "$dir"
# Leave nothing half-written behind if a later step fails; the caller reruns.
# The `return 0` matters: bash takes the EXIT trap's last status as the script's
# exit status, so a false test here would report failure after a clean run.
cleanup() {
  [[ -n ${scaffolded:-} ]] && rm -rf "$dir"
  return 0
}
scaffolded=1
trap cleanup EXIT

cat >"$dir/default.nix" <<'EOF'
{ ... }:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];
}
EOF

cat >"$dir/disk.nix" <<EOF
# Partitioning for $hostname. Applied by disko at install time, and from then on
# the source of every fileSystems entry for this machine.
{
  imports = [
    (import ../../lib/disk-layouts/luks-btrfs.nix { device = "$device"; })
  ];
}
EOF

# disko owns fileSystems, swapDevices and the LUKS mapping. Keeping
# nixos-generate-config's own filesystem stanzas would collide with them, so
# take only the hardware detection.
#
# It needs root even with --no-filesystems: it still probes btrfs for subvolume
# info and fails with "Failed to retrieve subvolume info for /" as a user.
gen=(nixos-generate-config --show-hardware-config --no-filesystems)
[[ $EUID -eq 0 ]] || gen=(sudo "${gen[@]}")
"${gen[@]}" >"$dir/hardware-configuration.nix"
[[ -s $dir/hardware-configuration.nix ]] || {
  echo "error: nixos-generate-config produced nothing" >&2
  exit 1
}

# stateVersion is the release this machine is installed with, so take it from
# the nixpkgs the flake pins rather than whatever the installer image runs.
# Reading .inputs does not force the flake outputs, which keeps this cheap and
# independent of private/hosts.json being decrypted.
state_version=$(nix eval --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.nixpkgs.lib.trivial.release' 2>/dev/null || true)
source="the flake's nixpkgs"
# A flake that will not evaluate is worth falling back from rather than failing
# on: the running system's release is close enough to start from.
if [[ -z $state_version ]]; then
  state_version=$(nixos-version 2>/dev/null | cut -d. -f1,2)
  source="nixos-version — the flake would not evaluate"
fi
[[ $state_version =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  echo "error: could not determine a nixpkgs release for stateVersion" >&2
  exit 1
}
echo "stateVersion: $state_version (from $source)"

# Measured boot is what lets scripts/finish-install.sh enroll the disk for TPM
# unlock. Asked rather than defaulted: systemd-pcrlock is still experimental
# upstream and sits in the boot path. The check needs a TPM, which the installer
# can see as well as the installed system can.
measured_boot=false
pcrlock=$(command -v systemd-pcrlock 2>/dev/null || true)
for p in /run/current-system/systemd/lib/systemd/systemd-pcrlock /run/current-system/sw/lib/systemd/systemd-pcrlock; do
  if [[ -z $pcrlock && -x $p ]]; then pcrlock=$p; fi
done
supported=
if [[ -n $pcrlock ]]; then supported=$("$pcrlock" is-supported 2>/dev/null || true); fi
if [[ $supported == yes ]]; then
  read -rp "Unlock the disk with the TPM at boot (no PIN, measured boot)? [y/N] " answer
  if [[ $answer == [yY]* ]]; then measured_boot=true; fi
else
  echo "TPM unlock not offered: systemd-pcrlock is-supported says '${supported:-nothing}'"
fi

# Registering is otherwise a judgement call (which modules this machine wants),
# so write the minimum and leave the rest to the operator.
# The installer ISO has no python3, and this script runs from it — fall back to
# nix-shell, the same way scripts/agecrypt-rekey.sh does.
py=(python3 - "$hostname" "$state_version" "$measured_boot")
if ! command -v python3 >/dev/null 2>&1; then
  py=(nix-shell -p python3 --run "python3 - $(printf '%q ' "$hostname" "$state_version" "$measured_boot")")
fi

"${py[@]}" <<'PY'
import re
import sys
import pathlib

host = sys.argv[1]
state_version = sys.argv[2]
measured_boot = sys.argv[3] == "true"
path = pathlib.Path("machines/machines.nix")
src = path.read_text()

if re.search(rf"^\s*{re.escape(host)}\s*=", src, re.M):
    print(f"machines/machines.nix already lists {host}")
    raise SystemExit(0)

body = src.rstrip()
assert body.endswith("}"), "unexpected machines.nix shape; register the machine by hand"

# Pushing to the attic cache is on by default here because a machine that only
# pulls is a machine whose builds nothing else can reuse, and forgetting the
# line is easier than noticing it is missing. Drop it for a work machine: the
# hook uploads everything the daemon builds, dependencies fetched with work
# credentials included. modules/attic/default.nix has the reasoning.
entry = "\n".join([
    "",
    f"  {host} = " + "{",
    f'    stateVersion = "{state_version}";',
    "    modules = [",
    "      # Remove this on a work machine — see modules/attic/default.nix.",
    "      { modules.attic.push.enable = true; }",
    "      { modules.cosmic-de.enable = true; }",
    *(["      { modules.secure-boot.measuredBoot.enable = true; }"] if measured_boot else []),
    "    ];",
    "  };",
    "",
])
path.write_text(body[: body.rfind("}")] + entry + "}\n")
print(f"registered {host} in machines/machines.nix")
PY

# The flake only sees git-tracked files; an unadded machine directory fails the
# build with "... is not tracked by Git".
git add "$dir" machines/machines.nix
scaffolded=

cat <<EOF

Created $dir and registered $hostname.
Review machines/machines.nix for the modules this machine wants, then:
  nix fmt
  sudo nixos-rebuild switch --flake .#$hostname
EOF
