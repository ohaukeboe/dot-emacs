{ nixos-hardware }:

{
  x13-laptop = {
    hostname = "x13-laptop";
    stateVersion = "24.11";
    hardwareModules = [
      nixos-hardware.nixosModules.asus-flow-gv302x-nvidia
    ];
    systemModules = [
      { modules.cosmic-de.enable = true; }
    ];
  };

  work-laptop = {
    hostname = "work-laptop";
    stateVersion = "24.11";
    systemModules = [
      { modules.cosmic-de.enable = true; }
      { modules.sshd.enable = true; }
    ];
  };

  desktop = {
    hostname = "desktop";
    stateVersion = "24.11";
    systemModules = [
      {
        system.audio.allowedSampleRates = [
          32000
          44100
          48000
          88200
          96000
          192000
        ];
      }
      { modules.cosmic-de.enable = true; }
      { modules.gaming.enable = true; }
      { modules.sshd.enable = true; }
    ];
  };
}
