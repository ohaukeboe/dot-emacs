# modules.gaming.gpu.overdrive.enable: amdgpu overdrive, which game-bench's
# undervolt variants need.
# modules.gaming.gpu.undervoltMv: the GPU voltage offset at boot, set after
# the power limit: a limit above the board's own maximum resets the offset
# (ADR 0010). Lost at a driver reset until the next boot.
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
  undervolt = cfg.gpu.undervoltMv;
  priv = lib.getExe cfg.benchmark.packages.game-bench-priv;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf cfg.gpu.overdrive.enable {
        hardware.amdgpu.overdrive = {
          enable = true;
          # The kernel default (0xfff7bfff) plus PP_OVERDRIVE_MASK (0x4000).
          # nixpkgs' default 0xfffd7fff would also turn GFXOFF and stutter
          # mode off and GFX_DCS on (docs/gpu-performance-research.md).
          ppfeaturemask = "0xfff7ffff";
        };
      })
      (lib.mkIf (watts != null) {
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
            ExecStart = "${priv} gpu-cap ${toString watts}";
            ExecStop = "${priv} gpu-cap default";
          };
        };
      })
      (lib.mkIf (undervolt != null) {
        assertions = [
          {
            assertion = cfg.gpu.overdrive.enable;
            message = "modules/gaming/gpu.nix: modules.gaming.gpu.undervoltMv needs modules.gaming.gpu.overdrive.enable.";
          }
        ];

        systemd.services.gpu-undervolt = {
          description = "Lower the amdgpu voltage by ${toString undervolt} mV";
          wantedBy = [ "multi-user.target" ];
          # Restarted with the power limit, which may reset the offset.
          after = [
            "systemd-modules-load.service"
            "gpu-power-cap.service"
          ];
          partOf = [ "gpu-power-cap.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${priv} gpu-undervolt ${toString undervolt}";
            ExecStop = "${priv} gpu-undervolt 0";
          };
        };
      })
    ]
  );
}
