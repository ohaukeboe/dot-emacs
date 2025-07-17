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

    # powerManagement.finegrained = true;
    prime = {
      # offload.enable = true;
      # offload.enableOffloadCmd = true;
      sync.enable = true;

      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  boot.kernelParams = lib.mkDefault [
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
}
