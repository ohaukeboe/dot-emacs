#!/usr/bin/env bash
# Install the shared host age key on this machine.
#
# Every machine uses the same age identity, so a fresh checkout only needs the
# YubiKey once: this decrypts sops/bootstrap/host-key.yaml with it and writes
# the identity to the two locations sops-nix reads.
#
#   ~/.config/sops/age/keys.txt   Home Manager (workstation/sops.nix)
#   /var/lib/sops-nix/keys.txt    NixOS (modules/sops)
#
# After this, sops/** and private/** decrypt with no YubiKey present.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ENC_FILE=sops/bootstrap/host-key.yaml
USER_KEY="$HOME/.config/sops/age/keys.txt"
SYSTEM_KEY=/var/lib/sops-nix/keys.txt

[[ -f $ENC_FILE ]] || {
  echo "error: $ENC_FILE not found" >&2
  exit 1
}

# If the key is already installed we do not need the YubiKey at all — the shared
# host key is a recipient of its own key file.
if [[ -f $USER_KEY ]]; then
  echo "Existing identity found at $USER_KEY; using it instead of the YubiKey."
  export SOPS_AGE_KEY_FILE="$USER_KEY"
else
  YUBIKEY_ID="$HOME/.config/sops/age/yubikey-wallet.txt"
  if [[ ! -f $YUBIKEY_ID ]]; then
    echo "No identity file yet — deriving one from the connected YubiKey."
    echo "Insert the 'wallet' YubiKey now."
    mkdir -p "$(dirname "$YUBIKEY_ID")"
    nix-shell -p age-plugin-yubikey --run \
      "age-plugin-yubikey --identity --slot 1" >"$YUBIKEY_ID"
  fi
  export SOPS_AGE_KEY_FILE="$YUBIKEY_ID"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

nix-shell -p sops age age-plugin-yubikey --run \
  "sops decrypt --extract '[\"host_age_key\"]' $ENC_FILE" >"$TMP/keys.txt"

grep -q '^AGE-SECRET-KEY-' "$TMP/keys.txt" || {
  echo "error: decrypted material does not look like an age identity" >&2
  exit 1
}

mkdir -p "$(dirname "$USER_KEY")"
if [[ -f $USER_KEY ]] && ! cmp -s "$TMP/keys.txt" "$USER_KEY"; then
  cp "$USER_KEY" "$USER_KEY.bak.$(date +%Y%m%d%H%M%S)"
  echo "Backed up the previous $USER_KEY"
fi
install -m600 "$TMP/keys.txt" "$USER_KEY"
echo "Installed $USER_KEY"

sudo install -m600 -D "$TMP/keys.txt" "$SYSTEM_KEY"
echo "Installed $SYSTEM_KEY"

echo
echo "Public key: $(grep 'public key:' "$USER_KEY" | sed 's/.*: //')"
echo "Next: just agecrypt-init, then home-manager switch / nixos-rebuild switch."
