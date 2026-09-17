{ nixos-hardware }:

{
  x13-laptop = {
    stateVersion = "24.11";
    modules = [
      { modules.attic.push.enable = true; }
      { modules.cosmic-de.enable = true; }
      {
        modules.sleep-then-hibernate.enable = true;
        modules.sleep-then-hibernate.swapSize = 40960; # 40 GiB (RAM = 32 GiB + headroom)
      }
      { modules.silent-boot.earlyKms.modules = [ "amdgpu" ]; }
      nixos-hardware.nixosModules.asus-flow-gv302x-nvidia
    ];
  };

  work-laptop = {
    stateVersion = "24.11";
    modules = [
      { modules.cosmic-de.enable = true; }
      { modules.sshd.enable = true; }
      # Display runs on the Intel iGPU; nvidia stays out of the initrd.
      { modules.silent-boot.earlyKms.modules = [ "i915" ]; }
    ];
  };

  desktop = {
    stateVersion = "24.11";
    modules = [
      { modules.attic.push.enable = true; }
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
      { modules.silent-boot.earlyKms.modules = [ "amdgpu" ]; }
      # { sops.ageKey = "tpm"; }
    ];
  };
}
