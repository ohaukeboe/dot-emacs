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
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # Helper function to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      defaultConfig =
        if builtins.match ".*darwin" builtins.currentSystem != null then "oskar-darwin" else "oskar";

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
              {
                nix.package = pkgs.nix;
                nix.settings = {
                  substituters = [
                    "https://cache.nixos.org"
                    "https://nix-community.cachix.org"
                  ];
                  trusted-public-keys = [
                    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                  ];
                };
              }
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
            {
              nix.settings = {
                substituters = [
                  "https://cache.nixos.org"
                  "https://cosmic.cachix.org/"
                  "https://nix-community.cachix.org"
                ];
                trusted-public-keys = [
                  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                  "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
                  "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                ];
              };
            }
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
        "oskar" = mkHomeConfiguration "x86_64-linux";
        "oskar-darwin" = mkHomeConfiguration "aarch64-darwin";
        "default" = self.homeConfigurations.${defaultConfig};
      };

      packages = forAllSystems (system: {
        default = self.homeConfigurations."oskar".activationPackage;
      });

      # For convenience, you can also add apps
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/activate";
        };
      });
    };
}
