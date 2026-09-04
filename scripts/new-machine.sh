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
cleanup() { [[ -n ${scaffolded:-} ]] && rm -rf "$dir"; }
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

# Registering is otherwise a judgement call (which modules this machine wants),
# so write the minimum and leave the rest to the operator.
python3 - "$hostname" <<'PY'
import re
import sys
import pathlib

host = sys.argv[1]
path = pathlib.Path("machines/machines.nix")
src = path.read_text()

if re.search(rf"^\s*{re.escape(host)}\s*=", src, re.M):
    print(f"machines/machines.nix already lists {host}")
    raise SystemExit(0)

body = src.rstrip()
assert body.endswith("}"), "unexpected machines.nix shape; register the machine by hand"

entry = "\n".join([
    "",
    f"  {host} = " + "{",
    '    stateVersion = "24.11";',
    "    modules = [",
    "      { modules.cosmic-de.enable = true; }",
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
