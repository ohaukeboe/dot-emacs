{
  description = "Home Manager configuration of oskar";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # for list of hardware modules: https://github.com/NixOS/nixos-hardware#list-of-profiles
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add nixGL for better OpenGL and vulkan support
    nixgl.url = "github:nix-community/nixGL";

    # Make apps show in spotlight
    mac-app-util.url = "github:hraban/mac-app-util";

    treefmt-nix.url = "github:numtide/treefmt-nix";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      emacs-overlay,
      flatpaks,
      nixgl,
      mac-app-util,
      treefmt-nix,
      lanzaboote,
      nixos-hardware,
      zen-browser,
      nix-index-database,
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

      secrets = builtins.fromJSON (builtins.readFile "${self}/secrets/secrets.json");

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
          inputs
          nixpkgs
          home-manager
          emacs-overlay
          nixgl
          mac-app-util
          flatpaks
          secrets
          nix-index-database
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
                inherit inputs secrets;
                isNixos = true;
              };
            }
          ];
        };
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      nixosConfigurations = {
        x13-laptop = nixpkgs.lib.nixosSystem {
          modules = [
            ({
              system.stateVersion = "24.11";
              networking.hostName = "x13-laptop";
            })
            nixos-hardware.nixosModules.asus-flow-gv302x-nvidia
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
            ./common/caches.nix
            ./system/.
            ./common/secure-boot.nix
            lanzaboote.nixosModules.lanzaboote
            ./machines/x13-laptop.nix
            (homeManagerNixosModule {
              stateVersion = "24.11";
              imports = [
                ./workstation/home.nix
                ./system/home.nix
              ];
            })
          ];
        };
        work-laptop = nixpkgs.lib.nixosSystem {
          modules = [
            ({
              system.stateVersion = "24.11";
              networking.hostName = "work-laptop";
            })
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
            ./common/caches.nix
            ./system/.
            ./common/secure-boot.nix
            lanzaboote.nixosModules.lanzaboote
            ./machines/work-laptop.nix
            ./machines/work-laptop/config.nix
            (homeManagerNixosModule {
              stateVersion = "24.11";
              imports = [
                ./workstation/home.nix
                ./system/home.nix
              ];
            })
          ];
        };
        x1laptop = nixpkgs.lib.nixosSystem {
          modules = [
            ({
              system.stateVersion = "24.11";
              networking.hostName = "x1laptop";
            })
            nix-index-database.nixosModules.nix-index
            { programs.nix-index-database.comma.enable = true; }
            ./common/caches.nix
            ./system/.
            ./common/secure-boot.nix
            ./machines/x1carbon.nix
            (homeManagerNixosModule {
              stateVersion = "24.11";
              imports = [
                ./workstation/home.nix
                ./system/home.nix
              ];
            })
            lanzaboote.nixosModules.lanzaboote
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
