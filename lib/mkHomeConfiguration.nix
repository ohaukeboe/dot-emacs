{
  inputs,
  nixpkgs,
  home-manager,
  emacs-overlay,
  flatpaks,
  nixgl,
  mac-app-util,
  secrets,
  nix-index-database,
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
      # Only add nixGL overlay for Linux. Inline nixgl.overlay logic to avoid
      # final.system (deprecated; nixgl upstream uses it in their overlay).
      (
        final: prev:
        if builtins.match ".*linux" system != null then
          let
            isIntelX86Platform = final.stdenv.hostPlatform.system == "x86_64-linux";
          in
          {
            nixgl = import "${nixgl}/default.nix" {
              pkgs = final;
              enable32bits = isIntelX86Platform;
              enableIntelX86Extensions = isIntelX86Platform;
            };
          }
        else
          { }
      )
      # nvfetcher-managed sources (see nvfetcher.toml), exposed as pkgs.nvSources
      (final: prev: { nvSources = final.callPackage ../_sources/generated.nix { }; })
    ];
  };
  lib = nixpkgs.lib;
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  # Specify your home configuration modules here
  modules = [
    { home.stateVersion = "23.05"; }
    flatpaks.homeManagerModules.nix-flatpak
    nix-index-database.homeModules.nix-index
    { programs.nix-index-database.comma.enable = true; }
    ../workstation/home.nix
    ../common/caches.nix
    ../common/options.nix
  ]
  ++ lib.optionals (builtins.match ".*darwin" system != null) [
    mac-app-util.homeManagerModules.default
  ];
  extraSpecialArgs = {
    inherit inputs secrets;
    isNixos = false;
  };
}
