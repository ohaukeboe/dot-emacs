{
  description = "Home Manager configuration of oskar";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
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
      home-manager,
      emacs-overlay,
      nixgl,
      mac-app-util,
      ...
    }:
    let
      defaultConfig =
        if builtins.match ".*darwin" builtins.currentSystem != null then "oskar-darwin" else "oskar";

      # Function to create home-manager configuration for a system
      mkHomeConfiguration =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
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
            ]
            ++ lib.optionals (builtins.match ".*darwin" system != null) [
              mac-app-util.homeManagerModules.default
            ];

          # Optionally use extraSpecialArgs
          # to pass through arguments to home.nix
          extraSpecialArgs = {
            isLinux = builtins.match ".*linux" system != null;
            isDarwin = builtins.match ".*darwin" system != null;
          };
        };
    in
    {
      homeConfigurations = {
        "oskar" = mkHomeConfiguration "x86_64-linux";
        "oskar-darwin" = mkHomeConfiguration "aarch64-darwin";
        "default" = self.homeConfigurations.${defaultConfig};
      };
    };
}
