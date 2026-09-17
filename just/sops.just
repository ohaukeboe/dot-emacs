# Secrets Management with SOPS, YubiKey, and TPM 2.0
#
# There is exactly one host age key, shared by every machine. Its private
# material is committed as sops/bootstrap/host-key.yaml, encrypted to the
# YubiKey (and to itself). To set up a new machine use `just bootstrap`, not the
# rotation recipe below.
#
# The YubiKey and TPM recipes create the hardware identities behind the
# `sops.ageKey` escape hatches (common/options.nix). Those only decrypt once the
# matching public key is a recipient in .sops.yaml.

# Rotate the shared host key: new keypair, re-encrypt every secret to it
sops-rotate-host-key:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "This replaces the age key used by ALL machines. Every machine then"
    echo "needs 'just bootstrap-host-key' again, with the YubiKey present."
    read -rp "Continue? [y/N] " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    nix-shell -p age --run "age-keygen -o $tmp/keys.txt"
    pub=$(grep 'public key:' "$tmp/keys.txt" | sed 's/.*: //')
    echo "New shared host key: $pub"

    # Decrypt every secret with the *current* key before swapping recipients.
    # Resolved through sops-identity.sh: on a NixOS host that is
    # /run/secrets/host-age-key, elsewhere ~/.config/sops/age/keys.txt.
    source scripts/sops-identity.sh default
    old_key=$SOPS_AGE_KEY_FILE

    # Point .sops.yaml and git-agecrypt.toml at the new public key.
    old_pub=$(grep 'public key:' "$old_key" | sed 's/.*: //')
    sed -i "s|$old_pub|$pub|g" .sops.yaml git-agecrypt.toml

    SOPS_AGE_KEY_FILE="$old_key" \
      nix-shell -p sops age age-plugin-yubikey --run "sops updatekeys -y sops/home/* sops/system/*"

    # Rewrite the bootstrap file itself with the new private key.
    {
      echo "# Shared host age identity, installed as /var/lib/sops-nix/keys.txt on every"
      echo "# machine by \`just bootstrap-host-key\` (and as ~/.config/sops/age/keys.txt"
      echo "# where Home Manager runs standalone)."
      echo "host_age_key: |"
      sed 's/^/  /' "$tmp/keys.txt"
    } >sops/bootstrap/host-key.yaml
    nix-shell -p sops age age-plugin-yubikey --run "sops encrypt -i sops/bootstrap/host-key.yaml"

    ./scripts/agecrypt-rekey.sh

    # -D: a NixOS host has no ~/.config/sops/age/ (the old key came from
    # /run/secrets/host-age-key), and everything above is already rewritten.
    install -m600 -D "$tmp/keys.txt" ~/.config/sops/age/keys.txt
    sudo install -m600 -D "$tmp/keys.txt" /var/lib/sops-nix/keys.txt
    echo ""
    echo "Rotated. Commit the result, then run 'just bootstrap-host-key' on every"
    echo "other machine."

# Re-encrypt every sops/** file after changing recipients in .sops.yaml
sops-updatekeys identity="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/sops-identity.sh "{{ identity }}"
    nix-shell -p sops age age-plugin-yubikey age-plugin-tpm --run "sops updatekeys sops/home/* sops/system/* sops/bootstrap/*"

# Show detailed info about SOPS keys and file status
sops-info:
    #!/usr/bin/env bash
    set -uo pipefail
    SOPS_AGE_DIR="${SOPS_AGE_DIR:-$HOME/.config/sops/age}"

    echo "=== Available Identity Files ==="
    shopt -s nullglob
    found=0
    # /run/secrets/host-age-key is where a NixOS host gets the shared key
    # (modules/sops); it is the fallback sops-identity.sh uses.
    for f in "$SOPS_AGE_DIR"/*.txt /run/secrets/host-age-key; do
      [[ -r $f ]] || continue
      pubkey=$(grep -E "^age1|public key:|Recipient:" "$f" 2>/dev/null | head -1 | sed 's/.*: //' | tr -d ' ')
      echo "  $f: ${pubkey:0:20}..."
      found=1
    done
    [[ $found -eq 0 ]] && echo "  No identity files found in $SOPS_AGE_DIR or /run/secrets/host-age-key"

    echo ""
    echo "=== Keys in .sops.yaml ==="
    if [[ -f .sops.yaml ]]; then
      grep -E "^\s*- age1|^\s*- &" .sops.yaml | head -20 || echo "  No age keys found"
    else
      echo "  .sops.yaml not found"
    fi

    echo ""
    echo "=== Encrypted File Status ==="
    nix-shell -p sops --run 'for f in sops/*/*.yaml; do echo "  $f: $(sops filestatus "$f" 2>/dev/null || echo "could not get file status")"; done'

#################### YubiKey ####################

# Generate a new age identity on YubiKey (interactive setup)
yubikey-setup:
    @echo "Setting up YubiKey for age encryption..."
    @echo "This will create a new age identity on your YubiKey."
    @echo "Make sure your YubiKey is inserted."
    @echo ""
    nix-shell -p age-plugin-yubikey --run "age-plugin-yubikey"

# Save YubiKey age identity to file (name: wallet or home)
yubikey-save-identity name slot="1":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ name }}" != "wallet" && "{{ name }}" != "home" ]]; then
      echo "Error: name must be 'wallet' or 'home'"
      echo "Usage: just yubikey-save-identity <wallet|home> [slot]"
      exit 1
    fi
    echo "Saving YubiKey identity from slot {{ slot }} as '{{ name }}'..."
    echo "Make sure your '{{ name }}' YubiKey is inserted."
    mkdir -p ~/.config/sops/age
    nix-shell -p age-plugin-yubikey --run "age-plugin-yubikey --identity --slot {{ slot }} > ~/.config/sops/age/yubikey-{{ name }}.txt"
    sudo mkdir -p /var/lib/sops-nix
    sudo cp ~/.config/sops/age/yubikey-{{ name }}.txt /var/lib/sops-nix/
    echo "Identity saved to ~/.config/sops/age/yubikey-{{ name }}.txt"
    echo ""
    echo "Public key (add to .sops.yaml):"
    grep -E "Recipient:|public key:" ~/.config/sops/age/yubikey-{{ name }}.txt | head -1 | sed 's/.*: //'

#################### TPM 2.0 ####################

# Generate TPM identity and save to file for sops (use pin=false to disable PIN)
tpm-save-identity pin="true":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Generating TPM identity and saving to ~/.config/sops/age/tpm-identity.txt..."
    if [ "{{ pin }}" = "true" ]; then
      echo "PIN protection enabled - you will be prompted for a PIN."
    fi
    mkdir -p ~/.config/sops/age
    if [ "{{ pin }}" = "true" ]; then
      nix-shell -p age-plugin-tpm --run "sudo age-plugin-tpm --tpm-recipient --generate --pin > ~/.config/sops/age/tpm-identity.txt"
    else
      nix-shell -p age-plugin-tpm --run "sudo age-plugin-tpm --tpm-recipient --generate > ~/.config/sops/age/tpm-identity.txt"
    fi
    sudo mkdir -p /var/lib/sops-nix
    sudo cp ~/.config/sops/age/tpm-identity.txt /var/lib/sops-nix/
    echo "Identity saved to ~/.config/sops/age/tpm-identity.txt"
    echo ""
    echo "Public key (add this to .sops.yaml):"
    grep "# Recipient:" ~/.config/sops/age/tpm-identity.txt | cut -d: -f2 | tr -d ' ' || \
      grep "^age1tpm1" ~/.config/sops/age/tpm-identity.txt
