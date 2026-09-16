# Imported two ways: as a NixOS module (common/nixos-default.nix), where it
# lands in /etc/nix/nix.conf and the root daemon honours all of it, and as a
# Home Manager module (lib/mkHomeConfiguration.nix), where it lands in
# ~/.config/nix/nix.conf instead. A daemon takes `substituters` and
# `trusted-public-keys` from a client only if that client is a trusted user, so
# the second form needs `trusted-users` in the host's own /etc/nix/nix.conf to
# have any effect. AGENTS.md says so under "Home Manager (Standalone)".
{ pkgs, ... }:
{
  nix.package = pkgs.nix;
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"

      # The private cache on deepthought: what these machines and the homestach
      # repo build and no public cache has. Reachable over the tailnet only, so
      # a machine that is off it loses `connect-timeout` seconds and then builds
      # normally. Other projects have their own namespaces on the same server;
      # they are not listed here because nothing on these machines pulls from
      # them. See docs/adr/0012-binary-cache-on-deepthought.md in the homestach
      # repo.
      "https://attic.homestach.eu/homestach"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "homestach:mPnTOuwbl4OuhmO4Q4CiS9VGHM33USIQ/1OmmQPLV5c="
    ];

    # An unreachable substituter must cost seconds, not minutes — that one
    # answers only on the tailnet.
    connect-timeout = 5;
    # And one that answers but lacks the path must lead to a build, not a
    # failure.
    fallback = true;
  };
}
