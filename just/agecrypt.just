# Transparent encryption of private/** with git-agecrypt, sharing the age
# recipients declared in .sops.yaml. Unlike sops/**, these files are decrypted
# into the working tree (and therefore into the Nix store) on purpose.

# Bootstrap git-agecrypt in a fresh checkout: install filters and register identities
agecrypt-init:
    #!/usr/bin/env bash
    set -euo pipefail
    nix-shell -p git-agecrypt --run "git-agecrypt init"
    # git-agecrypt init records an absolute /nix/store path, which breaks once
    # that store path is garbage collected. Resolve the binary via PATH instead.
    git config filter.git-agecrypt.smudge "git-agecrypt smudge -f %f"
    git config filter.git-agecrypt.clean "git-agecrypt clean -f %f"
    git config diff.git-agecrypt.textconv "git-agecrypt textconv"
    # Identities live in .git/config so each checkout can point at its own keys.
    for f in ~/.config/sops/age/keys.txt ~/.config/sops/age/yubikey-*.txt ~/.config/sops/age/tpm-identity.txt; do
      [[ -f "$f" ]] || continue
      nix-shell -p git-agecrypt --run "git-agecrypt config add -i $f"
    done
    nix-shell -p git-agecrypt --run "git-agecrypt status"

# Show git-agecrypt filter state, configured identities and recipients
agecrypt-status:
    nix-shell -p git-agecrypt --run "git-agecrypt status"
    @echo ""
    @echo "=== Recipients per path (git-agecrypt.toml) ==="
    nix-shell -p git-agecrypt --run "git-agecrypt config list"

# Re-encrypt private/** after changing recipients in git-agecrypt.toml
agecrypt-updatekeys:
    #!/usr/bin/env bash
    set -euo pipefail
    # git-agecrypt caches a blake3 hash of each plaintext and reuses the stored
    # ciphertext while the hash matches, so the cache has to go for a re-encrypt.
    rm -rf .git/git-agecrypt
    nix-shell -p git-agecrypt --run "git add --renormalize private"
    git status --short -- private
