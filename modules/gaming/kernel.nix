# A second boot entry, tagged "stock", with the stock kernel of the Zen
# kernel's series, so the two can be benchmarked against each other
# (specs/008-game-performance-tuning, research.md R8). The series is derived
# from Zen's version, so the pair stays matched across `nix flake update`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.gaming;
  zen = pkgs.linuxPackages_zen.kernel;
  series = "linux_${lib.versions.major zen.version}_${lib.versions.minor zen.version}";
  haveSeries = pkgs.linuxKernel.packages ? ${series};
  bootsZen = lib.hasInfix "zen" config.boot.kernelPackages.kernel.modDirVersion;
in
{
  config = lib.mkIf (cfg.enable && cfg.kernelComparison.enable) {
    assertions = [
      {
        assertion = bootsZen;
        message = "modules/gaming/kernel.nix: kernelComparison compares Zen against stock, but the default kernel (${config.boot.kernelPackages.kernel.modDirVersion}) is not Zen. Set boot.kernelPackages to pkgs.linuxPackages_zen (common/system/system.nix) or turn modules.gaming.kernelComparison.enable off.";
      }
      {
        assertion = haveSeries;
        message = "modules/gaming/kernel.nix: nixpkgs has no pkgs.linuxKernel.packages.${series} to match Zen ${zen.version}; wait for it or turn modules.gaming.kernelComparison.enable off.";
      }
    ];

    specialisation = lib.mkIf haveSeries {
      stock.configuration = {
        system.nixos.tags = [ "stock" ];
        # The entry itself is the comparison; no nested specialisation.
        modules.gaming.kernelComparison.enable = lib.mkForce false;
        boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.${series};
      };
    };
  };
}
