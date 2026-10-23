# Exposes pkgs.expiringOverride and pkgs.expiringSkipTests; see
# lib/expiring-override.nix.
final: prev: {
  inherit (import ../lib/expiring-override.nix { inherit (prev) lib; })
    expiringOverride
    expiringSkipTests
    ;
}
