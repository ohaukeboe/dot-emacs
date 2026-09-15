# Transparent encryption of private/** with git-agecrypt, sharing the age
# recipients declared in .sops.yaml. Unlike sops/**, these files are decrypted
# into the working tree (and therefore into the Nix store) on purpose.

# Bootstrap git-agecrypt in a fresh checkout: install filters and register identities
agecrypt-init:
    #!/usr/bin/env bash
    set -euo pipefail
    nix-shell -p git-agecrypt --run "git-agecrypt init"
    # git-agecrypt init records an absolute /nix/store path, which breaks once
    # that store path is garbage collected. Point at a wrapper instead, which
    # also covers the bootstrap case where git-agecrypt is not yet on PATH.
    # Git runs filter and textconv commands from the top of the worktree, so a
    # relative path here survives the repo being moved.
    git config filter.git-agecrypt.smudge "./scripts/git-agecrypt.sh smudge -f %f"
    git config filter.git-agecrypt.clean "./scripts/git-agecrypt.sh clean -f %f"
    git config diff.git-agecrypt.textconv "./scripts/git-agecrypt.sh textconv"
    # Identities live in .git/config so each checkout can point at its own keys.
    # `scripts/install-machine.sh` copies the checkout with `cp -a`, so a fresh
    # machine inherits whatever the installer registered — typically
    # /root/.config/sops/age/*, which the new user cannot read. git-agecrypt
    # aborts on the first unreadable identity, so drop those before adding.
    while IFS= read -r f; do
      [[ -n "$f" && ! -r "$f" ]] || continue
      echo "dropping unreadable identity: $f"
      nix-shell -p git-agecrypt age-plugin-yubikey --run "git-agecrypt config remove -i $f"
    done < <(git config --get-all git-agecrypt.config.identity || true)
    # The shared host key comes first so decryption never touches the YubiKey.
    # On an installed NixOS machine there is no key in the home directory:
    # modules/sops hands the shared key over as /run/secrets/host-age-key.
    # `git-agecrypt config add` errors on an already-registered identity, so this
    # stays re-runnable by checking .git/config first.
    registered=$(git config --get-all git-agecrypt.config.identity || true)
    for f in ~/.config/sops/age/keys.txt /run/secrets/host-age-key ~/.config/sops/age/yubikey-*.txt ~/.config/sops/age/tpm-identity.txt; do
      [[ -r "$f" ]] || continue
      if grep -qxF "$f" <<<"$registered"; then
        echo "already registered: $f"
        continue
      fi
      # age-plugin-yubikey is needed to parse the yubikey-*.txt identities, and
      # it only reaches PATH once home-manager has run — which is after this.
      nix-shell -p git-agecrypt age-plugin-yubikey --run "git-agecrypt config add -i $f"
    done
    # Without an identity the re-checkout below fails inside the smudge filter,
    # where the error says nothing about the missing key.
    if [[ -z "$(git config --get-all git-agecrypt.config.identity || true)" ]]; then
      echo "no age identity is readable; run 'just bootstrap-host-key' first." >&2
      exit 1
    fi
    # A fresh clone checked private/** out before the filters existed, so the
    # working tree still holds ciphertext. Force a re-checkout through smudge.
    # Refuse if that would throw away uncommitted plaintext edits. Deletions are
    # excluded (--diff-filter=d): they hold no content to lose, and a run that
    # died between the rm and the checkout below would otherwise be unrepeatable.
    #
    # `git diff` alone cannot tell the two apart: with the filters now installed
    # it runs clean over the untouched ciphertext and so reports every file as
    # modified. A file whose bytes still equal its blob in HEAD was never
    # smudged and holds no plaintext to lose; only the rest counts as dirty.
    dirty=()
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      cmp -s "$f" <(git cat-file blob "HEAD:$f" 2>/dev/null) && continue
      dirty+=("$f")
    done < <(git diff --name-only --diff-filter=d -- private)
    if [[ ${#dirty[@]} -gt 0 ]]; then
      echo "private/** has unstaged changes; refusing to re-checkout." >&2
      printf '  %s\n' "${dirty[@]}" >&2
      echo "Commit or stash them, then re-run." >&2
      exit 1
    fi
    rm -f private/*
    git checkout -- private
    nix-shell -p git-agecrypt age-plugin-yubikey --run "git-agecrypt status"

# Show git-agecrypt filter state, configured identities and recipients
agecrypt-status:
    nix-shell -p git-agecrypt age-plugin-yubikey --run "git-agecrypt status"

# Bypasses the clean filter on purpose: git-agecrypt reuses the ciphertext in
# HEAD whenever a configured identity can still decrypt it, which silently
# ignores recipient changes. See scripts/agecrypt-rekey.sh. Commit right after.

# Re-encrypt private/** after changing recipients in git-agecrypt.toml
agecrypt-updatekeys:
    ./scripts/agecrypt-rekey.sh
