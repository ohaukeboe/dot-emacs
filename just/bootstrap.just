# Provisioning a new machine. Every machine shares one age identity, so the
# YubiKey is only needed for this first step.

# Install the shared host age key (needs the 'wallet' YubiKey on a new machine)
bootstrap-host-key:
    ./scripts/bootstrap-host-key.sh

# Full first-run setup for a fresh checkout: host key, then git-agecrypt
bootstrap: bootstrap-host-key agecrypt-init
    #!/usr/bin/env bash
    set -euo pipefail
    host=$(hostname)
    echo ""
    echo "Bootstrap done."
    # A host that is not in the registry has no flake attribute to rebuild. That
    # is the installer ISO, where the hostname is `nixos` and the machine has
    # not been scaffolded yet, so the next step is the rest of the install.
    if ! grep -qE "^[[:space:]]*$host = \{" machines/machines.nix; then
      echo "$host is not in machines/machines.nix — continue with docs/new-machine.md:"
      echo "  lsblk                                     # pick the whole disk"
      echo "  just new-machine <hostname> /dev/<disk>"
      echo "  just install-machine <hostname>           # ERASES that disk"
      exit 0
    fi
    echo "Now run:"
    echo "  sudo nixos-rebuild switch --flake .#$host"
