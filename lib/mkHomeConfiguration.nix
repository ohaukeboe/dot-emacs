{
  nixpkgs,
  home-manager,
  emacs-overlay,
  flatpaks,
  nixgl,
  mac-app-util,
}:

system:
let
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfreePredicate = import ../common/unfree-predicates.nix { inherit (nixpkgs) lib; };
    };
    overlays = [
      emacs-overlay.overlay
      # Only add nixGL overlay for Linux
      (final: prev: if builtins.match ".*linux" system != null then (nixgl.overlay final prev) else { })
    ];
  };
  lib = nixpkgs.lib;
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  # Specify your home configuration modules here
  modules =
    [
      { home.stateVersion = "23.05"; }
      flatpaks.homeManagerModules.nix-flatpak
      ../workstation/home.nix
      ../common/caches.nix
    ]
    ++ lib.optionals (builtins.match ".*darwin" system != null) [
      mac-app-util.homeManagerModules.default
    ];
  extraSpecialArgs = {
    isNixos = false;
  };
}
