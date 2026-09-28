#!/usr/bin/env bash
# Enroll the root LUKS volume for TPM unlock, bound to the systemd-pcrlock
# policy lanzaboote maintains. Skips, rather than fails, on a machine that
# cannot or should not do it, and on one that is already enrolled, so it is
# safe to re-run and to call from scripts/finish-install.sh.
#
#   ./scripts/tpm-enroll.sh [hostname]
#
# See docs/new-machine.md, step 8.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

host=${1:-$(hostname)}
# Both fixed by the config: the mapper name by lib/disk-layouts/luks-btrfs.nix,
# the policy path by lanzaboote's measuredBoot.pcrlockPolicy default.
mapper=crypted
policy=/var/lib/systemd/pcrlock.json
pcrlock=/run/current-system/systemd/lib/systemd/systemd-pcrlock

skip() {
  echo "skipping TPM enrollment: $*"
  exit 0
}

# Opting in is modules.secure-boot.measuredBoot.enable. Without it nothing
# refreshes the policy on rebuild, and the enrollment would break on the first
# update that changes the boot chain.
[[ $(nix eval --json ".#nixosConfigurations.\"$host\".config.modules.secure-boot.measuredBoot.enable") == true ]] ||
  skip "modules.secure-boot.measuredBoot is off for $host"

[[ $host == "$(hostname)" ]] ||
  skip "$host is not this machine ($(hostname))"

supported=$("$pcrlock" is-supported 2>/dev/null || true)
[[ $supported == yes ]] ||
  skip "systemd-pcrlock is-supported says '${supported:-nothing}'"

# PCR 7 measures the Secure Boot keys. Enrolling before lanzaboote has put its
# own keys in place would lock the volume to state that is about to change.
# Captured rather than piped: run unprivileged, bootctl exits 1 because it
# cannot read /boot, and pipefail would turn that into a failed match even
# though the Secure Boot line is printed.
secureboot=$(bootctl status 2>/dev/null || true)
grep -q 'Secure Boot: enabled (user)' <<<"$secureboot" ||
  skip "Secure Boot is not enabled with user keys yet (see bootctl status)"

sudo test -f "$policy" ||
  skip "$policy does not exist; run nixos-rebuild switch first"

# The device-mapper backing device comes from sysfs: lsblk leaves PKNAME empty
# when asked about a dm device directly rather than walking down from its parent.
dm=$(basename "$(readlink -f "/dev/mapper/$mapper")")
slaves=("/sys/class/block/$dm/slaves/"*)
dev=
[[ ${#slaves[@]} -eq 1 && -e ${slaves[0]} ]] && dev=/dev/$(basename "${slaves[0]}")
[[ -b $dev && $(lsblk -ndo FSTYPE "$dev") == crypto_LUKS ]] ||
  skip "could not find the LUKS device behind /dev/mapper/$mapper"

slots=$(sudo systemd-cryptenroll "$dev")
if awk '$2 == "tpm2" { found = 1 } END { exit !found }' <<<"$slots"; then
  skip "$dev already has a tpm2 slot"
fi

# No --tpm2-with-pin: the disk unlocks at boot without any input, so anyone
# holding the powered-off machine gets as far as the login screen. The
# passphrase slot stays, and is the way back in if the policy ever fails to
# validate -- systemd-pcrlock is still experimental upstream.
echo "Enrolling $dev for TPM unlock; systemd-cryptenroll asks for the current LUKS passphrase."
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrlock="$policy" \
  "$dev"

echo "Enrolled. The next boot should unlock without the passphrase."
