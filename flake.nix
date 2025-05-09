{
  description = "Home Manager configuration of oskar";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.follows = "nixos-cosmic/nixpkgs";

    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add emacs-overlay
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks.url = "github:gmodena/nix-flatpak/?ref=latest";

    # Add nixGL for better OpenGL and vulkan support
    nixgl.url = "github:nix-community/nixGL";

    # Make apps show in spotlight
    mac-app-util.url = "github:hraban/mac-app-util";

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-cosmic,
      home-manager,
      emacs-overlay,
      flatpaks,
      nixgl,
      mac-app-util,
      treefmt-nix,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # Helper function to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      treefmtEval = forAllSystems (system: treefmt-nix.lib.evalModule nixpkgsFor.${system} ./treefmt.nix);

      defaultConfig =
        {
          "x86_64-linux" = "oskar@x86_64-linux";
          "aarch64-linux" = "oskar@aarch64-linux";
          "aarch64-darwin" = "oskar@aarch64-darwin";
        }
        ."${builtins.currentSystem}";

      # Function to create home-manager configuration for a system
      mkHomeConfiguration = import ./lib/mkHomeConfiguration.nix {
        inherit
          nixpkgs
          home-manager
          emacs-overlay
          nixgl
          mac-app-util
          flatpaks
          ;
      };
      homeManagerNixosModule =
        {
          stateVersion,
          imports ? [ ],
        }:
        {
          imports = [
            home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [ emacs-overlay.overlays.default ];
              nixpkgs.config.allowUnfreePredicate = import ./common/unfree-predicates.nix;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs.flake-inputs = inputs;
              home-manager.users.oskar = {
                imports = imports ++ [ flatpaks.homeManagerModules.nix-flatpak ];
                home.stateVersion = "${stateVersion}";
              };
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                isNixos = true;
              };
            }
          ];
        };
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      nixosConfigurations = {
        x1laptop = nixpkgs.lib.nixosSystem {
          system.stateVersion = "24.11";
          modules = [
            ./common/caches.nix
            ./common/system.nix
            ./machines/x1carbon.nix
            nixos-cosmic.nixosModules.default
            (homeManagerNixosModule {
              stateVersion = "24.11";
              imports = [ ./workstation/home.nix ];
            })

          ];
        };
      };

      homeConfigurations = {
        "oskar@x86_64-linux" = mkHomeConfiguration "x86_64-linux";
        "oskar@aarch64-linux" = mkHomeConfiguration "aarch64-linux";
        "oskar@aarch64-darwin" = mkHomeConfiguration "aarch64-darwin";
        "oskar" = self.homeConfigurations.${defaultConfig};
        "default" = self.homeConfigurations.${defaultConfig};
      };

      packages = forAllSystems (system: {
        default = self.homeConfigurations."oskar@${system}".activationPackage;
      });

      checks = forAllSystems (system: {
        formatting = treefmtEval.${system}.config.build.check self;
      });
    };
}
