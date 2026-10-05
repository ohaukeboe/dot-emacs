#!/usr/bin/env bash
# Reset the TPM to its factory state with TPM2_Clear. This destroys every key
# and NV index held under the owner, endorsement and lockout hierarchies, so
# anything sealed to the TPM stops working for good.
#
#   ./scripts/tpm-clear.sh
#
# Before clearing it wipes the tpm2 keyslot of the root LUKS volume (refusing
# when no other keyslot exists) and removes the systemd-pcrlock policy, so
# nothing is left pointing at the TPM state that is about to disappear. At the
# next boot systemd-tpm2-setup creates a new SRK and lanzaboote a new policy;
# `just tpm-enroll` then restores TPM unlock.
#
# When the OS cannot clear the TPM itself (lockout auth set, or clearing
# disabled), it falls back to a Physical Presence request, which the firmware
# carries out at the next reboot after asking for confirmation.
#
# See docs/new-machine.md, step 8.
set -euo pipefail

# Fixed by the config: the mapper name by lib/disk-layouts/luks-btrfs.nix,
# the policy path by lanzaboote's measuredBoot.pcrlockPolicy default.
mapper=crypted
policy=/var/lib/systemd/pcrlock.json
pcrlock=/run/current-system/systemd/lib/systemd/systemd-pcrlock
ppi=/sys/class/tpm/tpm0/ppi

[[ -e /dev/tpmrm0 ]] || {
  echo "error: no TPM found (/dev/tpmrm0 is missing)" >&2
  exit 1
}

cat <<'MSG'
This clears the TPM. Everything sealed to it stops working for good:
  - TPM unlock of the root LUKS volume (its tpm2 keyslot is wiped first)
  - the sops TPM identity, ~/.config/sops/age/tpm-identity.txt
  - BitLocker, Windows Hello, or any other OS on this machine using the TPM
MSG
read -rp "Clear the TPM? [y/N] " ans
[[ $ans == y || $ans == Y ]] || exit 1

# The device-mapper backing device comes from sysfs: lsblk leaves PKNAME empty
# when asked about a dm device directly rather than walking down from its parent.
dev=
if [[ -e /dev/mapper/$mapper ]]; then
  dm=$(basename "$(readlink -f "/dev/mapper/$mapper")")
  slaves=("/sys/class/block/$dm/slaves/"*)
  [[ ${#slaves[@]} -eq 1 && -e ${slaves[0]} ]] && dev=/dev/$(basename "${slaves[0]}")
fi
if [[ -b $dev && $(lsblk -ndo FSTYPE "$dev") == crypto_LUKS ]]; then
  slots=$(sudo systemd-cryptenroll "$dev")
  if awk '$2 == "tpm2" { found = 1 } END { exit !found }' <<<"$slots"; then
    # Without another slot, the volume would be locked for good.
    awk 'NR > 1 && $2 != "tpm2" { found = 1 } END { exit !found }' <<<"$slots" || {
      echo "error: $dev has no keyslot besides tpm2; enroll a passphrase first" >&2
      exit 1
    }
    echo "Wiping the tpm2 keyslot of $dev."
    sudo systemd-cryptenroll --wipe-slot=tpm2 "$dev"
  fi
else
  echo "No LUKS device behind /dev/mapper/$mapper; no keyslot to wipe."
fi

# remove-policy exits non-zero when it cannot deallocate the NV index, but
# deletes the policy files anyway; the clear below frees the index regardless.
if sudo test -e "$policy"; then
  echo "Removing the systemd-pcrlock policy."
  sudo "$pcrlock" remove-policy || true
fi

# The SRK is gone after the clear. systemd-tpm2-setup recreates it at boot, and
# writes these files again only when they are absent.
sudo rm -f /var/lib/systemd/tpm2-srk-public-key.{pem,tpm2b_public}

if nix-shell -p tpm2-tools --run "sudo tpm2_clear"; then
  echo "TPM cleared. Reboot, then run 'just tpm-enroll' to restore TPM unlock."
  exit 0
fi

# Operation 5 is TPM2_Clear in the TCG Physical Presence Interface.
echo "tpm2_clear failed; asking the firmware to clear the TPM instead."
[[ -e $ppi/request ]] || {
  echo "error: no Physical Presence Interface at $ppi; clear the TPM from the firmware setup" >&2
  exit 1
}
echo 5 | sudo tee "$ppi/request" >/dev/null
echo "Reboot and confirm the TPM clear in the firmware prompt,"
echo "then run 'just tpm-enroll' to restore TPM unlock."
