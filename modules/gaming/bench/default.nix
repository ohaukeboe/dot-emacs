# game-bench: the benchmark harness for modules.gaming.
# specs/008-game-performance-tuning, docs/adr/0009-game-benchmark-harness.md.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.gaming;
  # callPackage adds override functions to the attrset; keep the packages.
  bench = lib.filterAttrs (_: lib.isDerivation) (
    pkgs.callPackage ./packages.nix {
      benchConfig = { inherit (cfg.benchmark) variants workloads; };
      inherit (cfg.benchmark) loadPackage;
      steam = config.programs.steam.package;
    }
  );
in
{
  options.modules.gaming.benchmark.packages = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    readOnly = true;
    description = "The game-bench packages, for other parts of modules.gaming.";
  };

  config = lib.mkMerge [
    # Only a value; nothing reaches the system unless the mkIf below holds.
    { modules.gaming.benchmark.packages = bench; }

    (lib.mkIf (cfg.enable && cfg.benchmark.enable) {
      environment.systemPackages = lib.attrValues bench;

      # The one root path the harness needs: a fixed-subcommand helper that
      # validates its arguments, so it can run without a password mid-session.
      security.sudo.extraRules = [
        {
          users = [ config.user.username ];
          commands = [
            {
              command = lib.getExe bench.game-bench-priv;
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    })
  ];
}
