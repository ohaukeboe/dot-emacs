{
  config,
  lib,
  pkgs,
  ...
}:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    # powerManagement.enable = true;

    # Required for the dGPU to actually reach D3cold while offloading; without
    # it offload only stops the card rendering the desktop, it stays powered.
    powerManagement.finegrained = true;
    # Offload keeps the dGPU runtime-suspended until an application asks for it
    # (run those with `nvidia-offload <cmd>`). reverseSync instead had the dGPU
    # render the whole desktop, which pinned it at ~12.7 W and P3 around the
    # clock and kept the fan audible at idle.
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      # sync.enable = true;
      # reverseSync.enable = true;

      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  boot.kernelParams = [
    "nvidia-drm.modeset=1"
  ];

  environment.variables = {
    VDPAU_DRIVER = lib.mkIf config.hardware.graphics.enable (lib.mkDefault "nvidia");
  };

  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver
    intel-vaapi-driver
    libvdpau-va-gl
    intel-media-driver
  ];

  services.btrbk = {
    instances."btrbk" = {
      onCalendar = "daily";
      settings = {
        snapshot_preserve_min = "1w";
        snapshot_preserve = "14d 4w";
        target_preserve = "14d 4w";
        volume = {
          "/" = {
            snapshot_dir = "/snapshots";
            subvolume = {
              "home/oskar/projects" = { };
              "home/oskar/knowit" = { };
            };
          };
        };
      };
    };
  };

  # Btrbk does not create snapshot directories automatically, so create one here.
  systemd.tmpfiles.rules = [
    "d /snapshots 0755 root root"
  ];
}
