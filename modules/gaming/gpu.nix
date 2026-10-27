# modules.gaming.gpu.powerCapWatts: the GPU power limit at boot. null keeps
# the stock limit, so deleting the setting reverts at the next boot (FR-028).
# The card's allowed range is only known at runtime; game-bench-priv refuses
# a value outside it and the unit fails without writing anything.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.gaming;
  watts = cfg.gpu.powerCapWatts;
in
{
  config = lib.mkIf (cfg.enable && watts != null) {
    assertions = [
      {
        assertion = lib.elem "amdgpu" (config.modules.silent-boot.earlyKms.modules or [ ]);
        message = "modules/gaming/gpu.nix: modules.gaming.gpu.powerCapWatts is set, but this machine has no amdgpu GPU in modules.silent-boot.earlyKms.modules (machines/machines.nix). The cap is amdgpu-only; unset it.";
      }
    ];

    systemd.services.gpu-power-cap = {
      description = "Set the amdgpu power limit to ${toString watts} W";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe cfg.benchmark.packages.game-bench-priv} gpu-cap ${toString watts}";
        ExecStop = "${lib.getExe cfg.benchmark.packages.game-bench-priv} gpu-cap default";
      };
    };
  };
}
