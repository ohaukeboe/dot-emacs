{ pkgs, ... }:
{
  nix.package = pkgs.nix;
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"

      # The private cache on deepthought: everything built in this household
      # that no public cache has — the homestach system closure, folindra's
      # closure-slimming overlay, simmerly. Reachable over the tailnet only, so
      # a machine that is off it loses `connect-timeout` seconds and then builds
      # normally. See docs/adr/0012-binary-cache-on-deepthought.md in the
      # homestach repo.
      "https://attic.homestach.eu/homestach"
      "https://attic.homestach.eu/folindra"
      "https://attic.homestach.eu/simmerly"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "homestach:mPnTOuwbl4OuhmO4Q4CiS9VGHM33USIQ/1OmmQPLV5c="
      "folindra:ZsBYpLf3O59bpRvmXVPsqogp44v9zV3sWs9MYutPJdQ="
      "simmerly:ySqjMor7NtrDP2bGz0h8m+c1bsoXc+eZZPGob+DMUNY="
    ];

    # An unreachable substituter must cost seconds, not minutes — these three
    # answer only on the tailnet.
    connect-timeout = 5;
    # And one that answers but lacks the path must lead to a build, not a
    # failure.
    fallback = true;
  };
}
