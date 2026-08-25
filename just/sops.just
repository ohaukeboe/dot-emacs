# Secrets Management with SOPS, YubiKey, and TPM 2.0
#
# There is exactly one host age key, shared by every machine. Its private
# material is committed as sops/bootstrap/host-key.yaml, encrypted to the
# YubiKey (and to itself). To set up a new machine use `just bootstrap`, not the
# rotation recipe below.

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
    old_key=~/.config/sops/age/keys.txt

    # Point .sops.yaml and git-agecrypt.toml at the new public key.
    old_pub=$(grep 'public key:' "$old_key" | sed 's/.*: //')
    sed -i "s|$old_pub|$pub|g" .sops.yaml git-agecrypt.toml

    SOPS_AGE_KEY_FILE="$old_key" \
      nix-shell -p sops age age-plugin-yubikey --run "sops updatekeys -y sops/home/*"

    # Rewrite the bootstrap file itself with the new private key.
    {
      echo "# Shared host age identity, installed as ~/.config/sops/age/keys.txt and"
      echo "# /var/lib/sops-nix/keys.txt on every machine by \`just bootstrap-host-key\`."
      echo "host_age_key: |"
      sed 's/^/  /' "$tmp/keys.txt"
    } >sops/bootstrap/host-key.yaml
    nix-shell -p sops age age-plugin-yubikey --run "sops encrypt -i sops/bootstrap/host-key.yaml"

    ./scripts/agecrypt-rekey.sh

    install -m600 "$tmp/keys.txt" ~/.config/sops/age/keys.txt
    sudo install -m600 -D "$tmp/keys.txt" /var/lib/sops-nix/keys.txt
    echo ""
    echo "Rotated. Commit the result, then run 'just bootstrap-host-key' on every"
    echo "other machine."

# Re-encrypt secrets.yaml after adding new keys to .sops.yaml
sops-updatekeys identity="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/sops-identity.sh "{{ identity }}"
    nix-shell -p sops age age-plugin-yubikey age-plugin-tpm --run "sops updatekeys sops/home/*"

# Show which identity would be used (for debugging)
sops-which identity="auto":
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/sops-identity.sh "{{ identity }}"
    echo "SOPS_AGE_KEY is set (content loaded from identity file)"

# Show detailed info about SOPS keys and file status
sops-info:
    #!/usr/bin/env bash
    set -uo pipefail
    SOPS_AGE_DIR="${SOPS_AGE_DIR:-$HOME/.config/sops/age}"

    echo "=== Available Identity Files ==="
    shopt -s nullglob
    found=0
    for f in "$SOPS_AGE_DIR"/*.txt; do
      name=$(basename "$f")
      pubkey=$(grep -E "^age1|public key:|Recipient:" "$f" 2>/dev/null | head -1 | sed 's/.*: //' | tr -d ' ')
      echo "  $name: ${pubkey:0:20}..."
      found=1
    done
    [[ $found -eq 0 ]] && echo "  No identity files found in $SOPS_AGE_DIR"

    echo ""
    echo "=== Keys in .sops.yaml ==="
    if [[ -f .sops.yaml ]]; then
      grep -E "^\s*- age1|^\s*- &" .sops.yaml | head -20 || echo "  No age keys found"
    else
      echo "  .sops.yaml not found"
    fi

    echo ""
    echo "=== secrets.yaml Status ==="
    if [[ -f secrets.yaml ]]; then
      nix-shell -p sops age age-plugin-yubikey age-plugin-tpm --run "sops filestatus sops/secrets.yaml" 2>/dev/null || echo "  Could not get file status"
    else
      echo "  sops/secrets.yaml not found"
    fi

#################### YubiKey ####################

# Generate a new age identity on YubiKey (interactive setup)
yubikey-setup:
    @echo "Setting up YubiKey for age encryption..."
    @echo "This will create a new age identity on your YubiKey."
    @echo "Make sure your YubiKey is inserted."
    @echo ""
    nix-shell -p age-plugin-yubikey --run "age-plugin-yubikey"

# Generate age identity from existing YubiKey slot (non-interactive)
yubikey-identity slot="1":
    @echo "Generating age identity from YubiKey slot {{ slot }}..."
    nix-shell -p age-plugin-yubikey --run "age-plugin-yubikey --identity --slot {{ slot }}"

# List all age recipients from connected YubiKeys
yubikey-list:
    @echo "Listing age recipients from connected YubiKeys..."
    nix-shell -p age-plugin-yubikey --run "age-plugin-yubikey --list"

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

# Check if TPM 2.0 is available and working
tpm-check:
    @echo "Checking TPM 2.0 status..."
    @if [ -c /dev/tpm0 ] || [ -c /dev/tpmrm0 ]; then \
      echo "✓ TPM device found"; \
      tpm2_getcap properties-fixed 2>/dev/null | head -20 || echo "Run 'tpm2_getcap properties-fixed' for details"; \
    else \
      echo "✗ No TPM device found at /dev/tpm0 or /dev/tpmrm0"; \
      echo "  Ensure TPM is enabled in BIOS and security.tpm2.enable = true in NixOS config"; \
    fi

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

# List TPM-sealed age identities
tpm-list:
    @echo "Listing TPM-sealed age identities..."
    nix-shell -p age-plugin-tpm --run "age-plugin-tpm --list" 2>/dev/null || echo "No TPM identities found"
