{ }:

{
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
      { modules.mango.enable = true; }
      {
        modules.mango.displays.setups.desktop.outputs = [
          {
            criteria = "Ancor Communications Inc ASUS PB278 D1LMTF015081";
            enable = true;
            mode = "2560x1440@59.951000";
            position = {
              x = 0;
              y = 0;
            };
            scale = 1.000000;
            transform = "270";
          }
          {
            criteria = "Samsung Electric Company Odyssey G80SD H1AK500000";
            enable = true;
            mode = "3840x2160@239.914001";
            position = {
              x = 1440;
              y = 420;
            };
            scale = 1.250000;
          }
        ];
      }
      { modules.gaming.enable = true; }
      # The GPU's overdrive power limit with a -50 mV undervolt, decided by
      # game-bench (docs/gaming-benchmarks.md).
      {
        modules.gaming.gpu.overdrive.enable = true;
        modules.gaming.gpu.powerCapWatts = 330;
        modules.gaming.gpu.undervoltMv = 50;
      }
      { modules.sshd.enable = true; }
      { modules.silent-boot.earlyKms.modules = [ "amdgpu" ]; }
      # { sops.ageKey = "tpm"; }
    ];
  };

  laptop = {
    stateVersion = "26.11";
    modules = [
      # Remove this on a work machine — see modules/attic/default.nix.
      { modules.attic.push.enable = true; }
      { modules.mango.enable = true; }
      # ROG Flow X13: the keyboard backlight is only reachable through asusd.
      { services.asusd.enable = true; }
      # Known docks: run `mango-display-setup <name>` while docked and paste
      # the printed modules.mango.displays.setups entry here.
      { modules.secure-boot.measuredBoot.enable = true; }
      { modules.silent-boot.earlyKms.modules = [ "amdgpu" ]; }
      {
        modules.sleep-then-hibernate.enable = true;
        modules.sleep-then-hibernate.swapSize = 40960; # 40 GiB (RAM = 32 GiB + headroom)
        # SMU firmware 64.44 < 64.53, so amd_pmc never arms the RTC wake from
        # s2idle and the hibernate delay cannot fire.
        modules.sleep-then-hibernate.sleepAction = "suspend";
      }
      {
        modules.mango.displays.setups.home-docked.outputs = [
          {
            criteria = "Samsung Electric Company Odyssey G80SD H1AK500000";
            enable = true;
            mode = "3840x2160@60.000000";
            position = {
              x = 1440;
              y = 361;
            };
            scale = 1.250000;
          }
          {
            criteria = "Ancor Communications Inc ASUS PB278 D1LMTF015081";
            enable = true;
            mode = "2560x1440@59.951000";
            position = {
              x = 0;
              y = 0;
            };
            scale = 1.000000;
            transform = "270";
          }
          {
            criteria = "eDP-1";
            enable = true;
            mode = "1920x1200@120.002998";
            position = {
              x = 1440;
              y = 2089;
            };
            scale = 1.000000;
          }
        ];
      }
    ];
  };

  dig-laptop = {
    stateVersion = "26.11";
    modules = [
      { modules.mango.enable = true; }
      {
        modules.mango.displays.setups.home-office.outputs = [
          {
            criteria = "Samsung Electric Company Odyssey G80SD H1AK500000";
            enable = true;
            mode = "3840x2160@59.997002";
            position = {
              x = 1440;
              y = 339;
            };
            scale = 1.250000;
          }
          {
            criteria = "Ancor Communications Inc ASUS PB278 D1LMTF015081";
            enable = true;
            mode = "2560x1440@59.951000";
            position = {
              x = 0;
              y = 0;
            };
            scale = 1.000000;
            transform = "270";
          }
          {
            criteria = "eDP-1";
            enable = true;
            mode = "1920x1200@60.002998";
            position = {
              x = 1440;
              y = 2067;
            };
            scale = 1.000000;
          }
        ];
        modules.mango.displays.setups.helsfyr.outputs = [
          {
            criteria = "LG Electronics LG ULTRAFINE 210MAJMPQR00";
            enable = true;
            mode = "3840x2160@60.000000";
            position = {
              x = 3072;
              y = 0;
            };
            scale = 1.250000;
          }
          {
            criteria = "LG Electronics LG ULTRAFINE 210MACEPQQ99";
            enable = true;
            mode = "3840x2160@60.000000";
            position = {
              x = 0;
              y = 0;
            };
            scale = 1.250000;
          }
          {
            criteria = "eDP-1";
            enable = true;
            mode = "1920x1200@60.002998";
            position = {
              x = 641;
              y = 1728;
            };
            scale = 1.000000;
          }
        ];
      }
      { modules.secure-boot.measuredBoot.enable = true; }
      { modules.silent-boot.earlyKms.modules = [ "i915" ]; }
      {
        modules.sleep-then-hibernate.enable = true;
        modules.sleep-then-hibernate.swapSize = 38912; # 38 GiB (RAM = 32 GiB + headroom)
        modules.sleep-then-hibernate.hibernateDelay = "90min";
      }
    ];
  };
}
