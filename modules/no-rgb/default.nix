{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.no-rgb;

  no-rgb = pkgs.writeScriptBin "no-rgb" ''
    #!/bin/sh
    NUM_DEVICES=$(${pkgs.openrgb}/bin/openrgb --noautoconnect --list-devices | grep -E '^[0-9]+: ' | wc -l)

    for i in $(seq 0 $(($NUM_DEVICES - 1))); do
      ${pkgs.openrgb}/bin/openrgb --noautoconnect --device $i --mode static --color 000000
    done
  '';
in
{
  options.modules.no-rgb = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic RGB light disabling on boot";
    };
  };

  config = mkIf cfg.enable {
    # OpenRGB udev rules and kernel modules
    services.udev.packages = [ pkgs.openrgb ];
    boot.kernelModules = [ "i2c-dev" ];
    hardware.i2c.enable = true;

    # Install no-rgb script
    environment.systemPackages = [ no-rgb ];

    # Systemd service to disable RGB on boot
    systemd.services.no-rgb = {
      description = "Disable RGB lighting on boot";
      serviceConfig = {
        ExecStart = "${no-rgb}/bin/no-rgb";
        Type = "oneshot";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
