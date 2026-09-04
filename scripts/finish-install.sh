#!/usr/bin/env bash
# Post-boot setup for a freshly installed machine. Nothing here is destructive;
# it is safe to re-run.
#
#   ./scripts/finish-install.sh [hostname]
#
# See docs/new-machine.md.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

host=${1:-$(hostname)}

echo "==> git-agecrypt"
# The identities live in .git/config, which is per-checkout: a clone or a copy
# from the installer arrives without them, leaving private/** as ciphertext.
just agecrypt-init

# The installer clones over HTTPS because no SSH key is readable yet. By now
# sops has decrypted one, so push can work.
if git remote get-url origin | grep -q '^https://github.com/'; then
  git remote set-url origin git@github.com:ohaukeboe/dot-emacs.git
  echo "origin switched to SSH"
fi

echo
echo "==> Tailscale"
# private/hosts.json addresses the other machines by tailnet name, so
# workstation/ssh.nix is useless until this machine has joined.
if tailscale status >/dev/null 2>&1; then
  echo "already up: $(tailscale status --json | grep -m1 '"DNSName"' | cut -d'"' -f4)"
else
  sudo tailscale up
fi

echo
echo "==> Rebuilding in place"
sudo nixos-rebuild switch --flake ".#$host"

echo
echo "==> Verification"
# Expect "Secure Boot: enabled (user)". Anything else means the firmware was
# not in Setup Mode when lanzaboote tried to enroll — see docs/new-machine.md.
bootctl status | grep -i 'secure boot' || true
sudo sbctl verify || true

cat <<EOF

Done. What is left:

  Restore anything not covered by this flake (Nextcloud, 1Password, mail).

  Optionally, TPM-backed LUKS unlock. That means enabling
  modules.secure-boot.measuredBoot for this machine and enrolling once with
  systemd-cryptenroll --tpm2-pcrlock; step 8 of docs/new-machine.md has the
  details. Not scripted here on purpose: it is a one-time decision per machine,
  it needs a reboot in the middle, and it wants a PIN you have to choose.
EOF
