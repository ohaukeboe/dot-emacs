{
  description = "Home Manager configuration of oskar";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add emacs-overlay
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks.url = "github:gmodena/nix-flatpak/?ref=latest";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # for list of hardware modules: https://github.com/NixOS/nixos-hardware#list-of-profiles
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    calibre-plugins.url = "github:ohaukeboe/calibre-plugins";

    # Add nixGL for better OpenGL and vulkan support
    nixgl.url = "github:nix-community/nixGL";

    # Make apps show in spotlight
    mac-app-util.url = "github:hraban/mac-app-util";

    treefmt-nix.url = "github:numtide/treefmt-nix";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kotlin-lsp = {
      url = "github:ohaukeboe/kotlin-lsp-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zotra-server = {
      url = "github:ohaukeboe/zotra-server-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    humanizer-skill = {
      url = "github:blader/humanizer";
      flake = false;
    };

    anthropics-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    caveman = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };

    cavekit = {
      url = "github:JuliusBrussee/cavekit";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    llm-skills = {
      url = "github:descoped/llm-skills";
      flake = false;
    };

    understand-anything = {
      url = "github:Lum1104/Understand-Anything";
      flake = false;
    };

    codebase-memory-mcp = {
      url = "github:DeusData/codebase-memory-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kagimcp = {
      url = "github:kagisearch/kagimcp";
      flake = false;
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

      # Function to create NixOS configuration for a machine
      mkNixosConfiguration = import ./lib/mkNixosConfiguration.nix {
        inherit
          inputs
          nixpkgs
          home-manager
          emacs-overlay
          flatpaks
          lanzaboote
          nix-index-database
          secrets
          ;
      };

      # Machine definitions
      machines = import ./machines/machines.nix { inherit nixos-hardware; };
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      nixosConfigurations = nixpkgs.lib.mapAttrs (
        hostname: config: mkNixosConfiguration (config // { inherit hostname; })
      ) machines;

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
