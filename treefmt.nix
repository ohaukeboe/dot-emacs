{ pkgs, ... }:
{
  projectRootFile = "flake.nix";
  settings.global.excludes = [
  ];

  programs.nixfmt.enable = true;
  programs.shfmt.enable = true;
  programs.toml-sort.enable = true;
}
