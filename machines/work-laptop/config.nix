{
  config,
  lib,
  pkgs,
  ...
}:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];
  hardware.nvidia.open = true;
  hardware.nvidia.powerManagement.finegrained = true;
  hardware.nvidia.prime = {
    offload.enable = true;
    offload.enableOffloadCmd = true;
    # sync.enable = true;

    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };

  environment.variables = {
    VDPAU_DRIVER = lib.mkIf config.hardware.opengl.enable (lib.mkDefault "va_gl");
  };

  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver
    intel-vaapi-driver
    libvdpau-va-gl
    intel-media-driver
  ];
}
