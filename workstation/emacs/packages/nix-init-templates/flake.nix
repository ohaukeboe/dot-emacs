{
  description = "A basic flake with a shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = inputs: {
    # Mapping over legacyPackages covers every system nixpkgs supports:
    # no hardcoded system list, no flake-utils input, and one shared
    # nixpkgs instance. Attributes are lazy, and `nix flake check`/`show`
    # skip systems this machine cannot build unless given --all-systems.
    devShells = builtins.mapAttrs (_: pkgs: {
      default = pkgs.mkShell { packages = [ pkgs.bashInteractive ]; };
    }) inputs.nixpkgs.legacyPackages;
  };
}
