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

    # Add nixGL for better OpenGL and vulkan support
    nixgl.url = "github:nix-community/nixGL";

    # Make apps show in spotlight
    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-cosmic,
      home-manager,
      emacs-overlay,
      nixgl,
      mac-app-util,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # Helper function to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      defaultConfig =
        {
          "x86_64-linux" = "oskar@x86_64-linux";
          "aarch64-linux" = "oskar@aarch64-linux";
          "aarch64-darwin" = "oskar@aarch64-darwin";
        }
        ."${builtins.currentSystem}";

      # Function to create home-manager configuration for a system
      mkHomeConfiguration =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfreePredicate = import ./common/unfree-predicates.nix { inherit (nixpkgs) lib; };
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

          # Specify your home configuration modules here, for example,
          # the path to your home.nix.
          modules =
            [
              ./home.nix
              ./common/caches.nix
            ]
            ++ lib.optionals (builtins.match ".*darwin" system != null) [
              mac-app-util.homeManagerModules.default
            ];
          extraSpecialArgs = {
            isNixos = false;
          };
        };
    in
    {
      nixosConfigurations = {
        x1laptop = nixpkgs.lib.nixosSystem {
          modules = [
            ./common/caches.nix
            nixos-cosmic.nixosModules.default
            ./configuration.nix

            home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [ emacs-overlay.overlays.default ];
              nixpkgs.config.allowUnfreePredicate = import ./common/unfree-predicates.nix;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.oskar = import ./home.nix;
              home-manager.extraSpecialArgs = {
                isNixos = true;
              };
            }
          ];
        };
      };

      homeConfigurations = {
        "oskar@x86_64-linux" = mkHomeConfiguration "x86_64-linux";
        "oskar@aarch64-linux" = mkHomeConfiguration "aarch64-linux";
        "oskar@aarch64-darwin" = mkHomeConfiguration "aarch64-darwin";
        "oskar" = self.homeConfigurations.${defaultConfig};
      };

      packages = forAllSystems (system: {
        default = self.homeConfigurations."oskar@${system}".activationPackage;
      });
    };
}
