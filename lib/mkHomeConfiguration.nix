{
  inputs,
  nixpkgs,
  home-manager,
  emacs-overlay,
  flatpaks,
  nixgl,
  mac-app-util,
  private,
  nix-index-database,
}:

system:
let
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfreePredicate = import ../common/unfree-predicates.nix { inherit (nixpkgs) lib; };
      permittedInsecurePackages = import ../common/insecure-packages.nix;
    };
    overlays = [
      emacs-overlay.overlay
      # Fix sops.el hanging on save (see the file for the why).
      (import ../common/emacs-sops-fix-overlay.nix)
      # pkgs.expiringOverride / pkgs.expiringSkipTests (see lib/expiring-override.nix)
      (import ../common/expiring-override-overlay.nix)
      # Only add nixGL overlay for Linux. Inline nixgl.overlay logic to avoid
      # final.system (deprecated; nixgl upstream uses it in their overlay).
      (
        final: prev:
        if builtins.match ".*linux" system != null then
          let
            isIntelX86Platform = final.stdenv.hostPlatform.system == "x86_64-linux";
          in
          {
            # What nixgl's default.nix does, plus an xorg argument.
            # shortcut: nixGL.nix still reads the deprecated xorg.libX11/libxcb/
            # libxshmfence (master, 2026-11-13); hand it the renamed packages
            # under the old names. Drop the xorg argument once upstream renames them.
            nixgl = final.callPackage "${nixgl}/nixGL.nix" (
              {
                enable32bits = isIntelX86Platform;
                xorg = {
                  libX11 = final.libx11;
                  inherit (final) libxcb libxshmfence;
                };
              }
              // final.lib.optionalAttrs (!isIntelX86Platform) { intel-media-driver = null; }
            );
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
    inherit inputs private;
    isNixos = false;
  };
}
