{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.silent-boot;
  mac-style-plymouth = pkgs.callPackage "${inputs.mac-style-plymouth}/package.nix" { };
in
{
  options.modules.silent-boot = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Graphical Plymouth boot splash (animated mac-style NixOS theme), quiet boot output and a hidden boot menu";
    };

    earlyKms = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Load the GPU drivers in `modules` in the initrd, so Plymouth draws
          on the native driver instead of the EFI framebuffer (simpledrm).
        '';
      };

      modules = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "amdgpu" ];
        description = ''
          Kernel modules for the GPU that drives the display. On PRIME
          laptops this is the iGPU driver only; keep nvidia out of the initrd.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = "mac-style";
      themePackages = [ mac-style-plymouth ];
    };

    # Hide kernel and systemd output behind the splash (Esc shows it).
    boot.consoleLogLevel = 3;
    boot.initrd.verbose = false;
    boot.kernelParams = [
      "quiet"
      "udev.log_level=3"
      "systemd.show_status=auto"
    ];

    boot.initrd.kernelModules = mkIf cfg.earlyKms.enable cfg.earlyKms.modules;

    # Hidden menu: hold Space during POST to show it.
    boot.loader.timeout = 0;
  };
}
