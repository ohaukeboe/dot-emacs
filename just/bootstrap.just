# Provisioning a new machine. Every machine shares one age identity, so the
# YubiKey is only needed for this first step.

# Install the shared host age key (needs the 'wallet' YubiKey on a new machine)
bootstrap-host-key:
    ./scripts/bootstrap-host-key.sh

# Full first-run setup for a fresh checkout: host key, then git-agecrypt
bootstrap: bootstrap-host-key agecrypt-init
    @echo ""
    @echo "Bootstrap done. Now run:"
    @echo "  home-manager switch --flake .#default --impure -b backup"
    @echo "  sudo nixos-rebuild switch --flake .#$(hostname)"
