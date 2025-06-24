{ config, ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];
  hardware.nvidia.open = true;

  hardware.nvidia.prime = {
    # offload.enable = true;
    # offload.enableOffloadCmd = true;
    sync.enable = true;

    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
}
