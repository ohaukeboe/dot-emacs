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

TMP=$(mktemp -d)
PCSCD_PID=""

cleanup() {
  rm -rf "$TMP"
  if [[ -n $PCSCD_PID ]]; then
    sudo kill "$PCSCD_PID" 2>/dev/null || true
    echo "Stopped the temporary pcscd."
  fi
}
trap cleanup EXIT

# The YubiKey is reached through pcscd. On a fresh machine it is not running:
# services.pcscd.enable lives in modules/sops, which only takes effect after the
# first nixos-rebuild — and that rebuild needs the key this script installs. So
# start the daemon here, either through systemd or as a temporary process.
ensure_pcscd() {
  [[ -e /run/pcscd/pcscd.comm ]] && return 0

  echo "pcscd is not running; the YubiKey needs it."
  sudo -v
  if sudo systemctl start pcscd.socket 2>/dev/null && [[ -e /run/pcscd/pcscd.comm ]]; then
    echo "Started pcscd.socket."
    return 0
  fi

  echo "Starting a temporary pcscd for this run."
  local ccid pcscd_bin
  ccid=$(nix-build --no-out-link '<nixpkgs>' -A ccid)
  pcscd_bin=$(nix-build --no-out-link '<nixpkgs>' -A pcsclite)/bin/pcscd
  sudo env PCSCLITE_HP_DROPDIR="$ccid/pcsc/drivers" "$pcscd_bin" --foreground &
  PCSCD_PID=$!

  for _ in {1..20}; do
    [[ -e /run/pcscd/pcscd.comm ]] && return 0
    sleep 0.5
  done

  echo "error: pcscd did not come up (no /run/pcscd/pcscd.comm)" >&2
  exit 1
}

# If the key is already installed we do not need the YubiKey at all — the shared
# host key is a recipient of its own key file.
if [[ -f $USER_KEY ]]; then
  echo "Existing identity found at $USER_KEY; using it instead of the YubiKey."
  export SOPS_AGE_KEY_FILE="$USER_KEY"
else
  ensure_pcscd
  # gpg's scdaemon can hold the card exclusively and hide it from the plugin.
  command -v gpgconf >/dev/null && gpgconf --kill scdaemon >/dev/null 2>&1 || true

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
