{
  inputs,
  nixpkgs,
  home-manager,
  emacs-overlay,
  flatpaks,
  lanzaboote,
  nix-index-database,
  secrets,
}:

{
  hostname,
  stateVersion ? "24.11",
  hardwareModules ? [ ],
  systemModules ? [ ],
  homeImports ? [
    ../workstation/home.nix
    ../common/system/home.nix
  ],
}:

let
  homeManagerNixosModule =
    { config, ... }:
    {
      imports = [
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [ emacs-overlay.overlays.default ];
          nixpkgs.config.allowUnfreePredicate = import ../common/unfree-predicates.nix {
            inherit (nixpkgs) lib;
          };
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs.flake-inputs = inputs;
          home-manager.users.${config.user.username} = {
            imports = homeImports ++ [ flatpaks.homeManagerModules.nix-flatpak ];
            home.stateVersion = stateVersion;
          };
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {
            inherit inputs secrets;
            isNixos = true;
          };
        }
      ];
    };
in
nixpkgs.lib.nixosSystem {
  specialArgs = {
    inherit inputs;
  };
  modules = [
    {
      system.stateVersion = stateVersion;
      networking.hostName = hostname;
    }
    nix-index-database.nixosModules.nix-index
    { programs.nix-index-database.comma.enable = true; }
    ../common/nixos-default.nix
    ../modules
    lanzaboote.nixosModules.lanzaboote
    ../machines/${hostname}
    homeManagerNixosModule
  ]
  ++ hardwareModules
  ++ systemModules;
}
