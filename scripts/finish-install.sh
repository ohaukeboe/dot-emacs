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
# workstation/ssh.nix is useless until this machine has joined — and so is the
# attic cache the rebuild below wants to pull from.
./scripts/tailnet-up.sh

echo
echo "==> Rebuilding in place"
sudo nixos-rebuild switch --flake ".#$host"

echo
echo "==> Seeding the attic cache with this machine's closure"
# The install built into the /mnt store with the installer's Nix daemon, which
# has no post-build hook, so nothing it produced locally ever reached the cache.
# The rebuild above only covers what changed since. Push the whole closure once,
# now that the machine is up and modules/attic has put the token in place.
#
# Cheap when there is nothing to do: attic asks the server which paths are
# missing and skips everything signed by an upstream cache key, so a machine
# that substituted its closure uploads nothing.
if [[ $(nix eval --json ".#nixosConfigurations.\"$host\".config.modules.attic.push.enable") == true ]]; then
  cache=$(nix eval --raw ".#nixosConfigurations.\"$host\".config.modules.attic.cacheName")
  # As root: the token lives in /root/.config/attic/config.toml, which is where
  # the attic client looks and nowhere else.
  sudo attic push "$cache" /run/current-system ||
    echo "warning: the push failed; the machine is fine, the cache just missed this closure"
else
  echo "pull-only machine (modules.attic.push.enable is off); nothing to push"
fi

echo
echo "==> TPM unlock"
# After the rebuild on purpose: that is what regenerates the pcrlock policy on
# this boot, with the Secure Boot keys lanzaboote enrolled on the first one.
./scripts/tpm-enroll.sh "$host" ||
  echo "warning: TPM enrollment failed; the passphrase still unlocks the disk. Retry with: just tpm-enroll"

echo
echo "==> Verification"
# Expect "Secure Boot: enabled (user)". Anything else means the firmware was
# not in Setup Mode when lanzaboote tried to enroll — see docs/new-machine.md.
bootctl status | grep -i 'secure boot' || true
sudo sbctl verify || true

cat <<EOF

Done. What is left:

  Restore anything not covered by this flake (Nextcloud, 1Password, mail).
EOF

# A machine scaffolded on the installer exists only in this checkout until it
# is committed; another machine's rebuild or a fresh clone would not know it.
if [[ -n $(git status --porcelain -- machines/) ]]; then
  cat <<EOF

  Commit and push the machine registration, which is not in git history yet:
    git status -- machines/
EOF
fi
