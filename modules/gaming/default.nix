{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.gaming;
  defaults = import ./bench/variants.nix;

  variantType = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "One line, shown by `game-bench list` and in summaries.";
      };
      workloads = mkOption {
        type = types.listOf (
          types.enum [
            "proton"
            "native"
          ]
        );
        default = [
          "proton"
          "native"
        ];
        description = "Workload kinds this variant can affect; others report it as n/a.";
      };
      gamemode = mkOption {
        type = types.bool;
        default = false;
        description = "Run the game under gamemoderun for this run.";
      };
      cpus = mkOption {
        type = types.nullOr (types.strMatching "[0-9,-]+");
        default = null;
        description = "CPU list to pin the game to with taskset.";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Extra environment variables for the game.";
      };
      cpuProfile = mkOption {
        type = types.nullOr (types.enum [ "performance" ]);
        default = null;
        description = "power-profiles-daemon profile for the run.";
      };
      scx = mkOption {
        type = types.nullOr (
          types.enum [
            "scx_bpfland"
            "scx_lavd"
          ]
        );
        default = null;
        description = "sched_ext scheduler to load for the run.";
      };
      stopSystem76 = mkOption {
        type = types.bool;
        default = false;
        description = "Stop system76-scheduler for the run.";
      };
      zenKnobs = mkOption {
        type = types.bool;
        default = false;
        description = "Apply the Zen kernel's runtime scheduler defaults (stock kernel only).";
      };
      gpuProfile = mkOption {
        type = types.nullOr (types.enum [ "3d-full-screen" ]);
        default = null;
        description = "amdgpu power profile for the run.";
      };
      gpuPowerCap = mkOption {
        type = types.nullOr (
          types.oneOf [
            types.ints.positive
            (types.strMatching "[0-9]{1,3}%")
            (types.enum [ "max" ])
          ]
        );
        default = null;
        description = "GPU power limit for the run: watts, a percentage of stock, or the card's maximum.";
      };
      gpuUndervoltMv = mkOption {
        type = types.nullOr (types.ints.between 1 200);
        default = null;
        description = "Lower the GPU voltage by this many mV for the run (overdrive `vo`). Needs modules.gaming.gpu.overdrive.enable; n/a without it.";
      };
    };
  };

  workloadType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "proton"
          "native"
        ];
        description = "`proton`: launched through Steam; frames from the game's own log, else MangoHud. `native`: Factorio's headless benchmark.";
      };
      appid = mkOption {
        type = types.ints.positive;
        description = "Steam app id.";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Game arguments.";
      };
      settingsFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path (`~` allowed) of a settings file swapped in for the session.";
      };
      settingsTarget = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Where `settingsFile` goes, relative to the Proton prefix's `drive_c/users/steamuser`.";
      };
      logDelay = mkOption {
        type = types.ints.unsigned;
        default = 20;
        description = "Seconds after start before MangoHud logs.";
      };
      logSeconds = mkOption {
        type = types.ints.positive;
        default = 60;
        description = "Seconds MangoHud logs.";
      };
      ticks = mkOption {
        type = types.ints.positive;
        default = 6000;
        description = "Factorio ticks to simulate.";
      };
      timeout = mkOption {
        type = types.ints.positive;
        default = 900;
        description = "Hard per-run limit in seconds.";
      };
    };
  };

  badVariants = pred: attrNames (filterAttrs (_: pred) cfg.benchmark.variants);
in
{
  imports = [
    ./bench
    ./kernel.nix
    ./gpu.nix
  ];

  options.modules.gaming = {
    enable = mkEnableOption "Gaming module";

    benchmark = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Install the game-bench harness (only where gaming is enabled).";
      };
      variants = mkOption {
        type = types.attrsOf variantType;
        default = defaults.variants;
        description = "Benchmark variants. See specs/008-game-performance-tuning/contracts/options.md.";
      };
      workloads = mkOption {
        type = types.attrsOf workloadType;
        default = defaults.workloads;
        description = "Benchmark workloads.";
      };
      loadPackage = mkOption {
        type = types.package;
        # The bare package behind the repo's Emacs (workstation/home.nix);
        # emacs-overlay is applied to the system pkgs (useGlobalPkgs).
        default = pkgs.emacs-unstable-pgtk;
        defaultText = literalExpression "pkgs.emacs-unstable-pgtk";
        description = "Derivation rebuilt as background load (`--load`) and timed by `game-bench build-time`.";
      };
    };

    kernelComparison.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Add a boot entry tagged `stock` with the stock kernel of the Zen kernel's series.";
    };

    gpu.overdrive.enable = mkEnableOption ''
      amdgpu overdrive (voltage offset, clocks, higher power limit). Only the
      overdrive bit of ppfeaturemask changes; enabling it taints the kernel
      and changes no clock or voltage by itself'';

    gpu.undervoltMv = mkOption {
      type = types.nullOr (types.ints.between 1 200);
      default = null;
      description = "GPU voltage offset below stock, in mV, set at boot after the power limit. Needs gpu.overdrive.enable. null keeps stock voltage.";
    };

    gpu.powerCapWatts = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "GPU power limit set at boot. null keeps the stock limit.";
    };

    tunings.env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Adopted per-game tunings, added to every Steam game's environment.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.benchmark.variants ? baseline
          && (
            let
              b = cfg.benchmark.variants.baseline;
            in
            !b.gamemode
            && b.cpus == null
            && b.env == { }
            && b.cpuProfile == null
            && b.scx == null
            && !b.stopSystem76
            && !b.zenKnobs
            && b.gpuProfile == null
            && b.gpuPowerCap == null
            && b.gpuUndervoltMv == null
          );
        message = "modules/gaming/default.nix: modules.gaming.benchmark.variants.baseline must exist and set nothing; every variant is measured against it.";
      }
      {
        assertion = badVariants (v: v.scx != null && v.zenKnobs) == [ ];
        message = "modules/gaming/default.nix: variants ${
          toString (badVariants (v: v.scx != null && v.zenKnobs))
        } set both `scx` and `zenKnobs`; the Zen knobs tune EEVDF, which a sched_ext scheduler replaces. Split them.";
      }
      {
        assertion = badVariants (v: v.stopSystem76 && v.scx == null) == [ ];
        message = "modules/gaming/default.nix: variants ${
          toString (badVariants (v: v.stopSystem76 && v.scx == null))
        } set `stopSystem76` without `scx`; it only exists to isolate a sched_ext scheduler.";
      }
      {
        assertion = all (w: (w.settingsFile == null) == (w.settingsTarget == null)) (
          attrValues cfg.benchmark.workloads
        );
        message = "modules/gaming/default.nix: a workload sets only one of `settingsFile` and `settingsTarget`; set both or neither.";
      }
    ];

    # Enable Steam
    programs = {
      steam = {
        enable = true;
        package = pkgs.steam.override {
          extraEnv = {
            # Equivalent to `PROTON_ENABLE_WAYLAND=1 %command%` on every game
            PROTON_ENABLE_WAYLAND = "1";
          }
          // cfg.tunings.env;
        };
        # GameMode is per game (`gamemoderun %command%`), not preloaded for
        # all of Steam: libgamemodeauto in the Steam client aborts it on a
        # D-Bus assertion and the UI shows "Unexpected Transport Error".
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
        # Steam Input under Wayland.
        extest.enable = true;
        extraPackages = [ pkgs.mangohud ];
      };
      gamemode = {
        enable = true;
        settings = {
          general = {
            renice = 10;
            ioprio = 0;
            # SCHED_ISO only exists on patched kernels.
            softrealtime = "off";
          };
          cpu.park_cores = "no";
        };
      };
    };

    # Proton uses ntsync when /dev/ntsync exists, else the slower fsync.
    # Zen builds it in; stock kernels build it as a module nothing loads
    # (docs/zen-kernel-nobara-research.md).
    boot.kernelModules = [ "ntsync" ];

    # renice and core parking need the group (gamemode example.ini).
    users.users.${config.user.username}.extraGroups = [ "gamemode" ];

    environment.sessionVariables = {
      # Steam's UI scaling under Wayland.
      STEAM_FORCE_DESKTOPUI_SCALING = "1";
    };

    environment.systemPackages = with pkgs; [
      prismlauncher

      # Lutris with extra dependencies for Wine-GE runner support
      (lutris.override {
        extraPkgs = pkgs: [
          wineWow64Packages.stable
          wineWow64Packages.staging
          wineWow64Packages.waylandFull
          winetricks
        ];
        extraLibraries = pkgs: [
          # Additional libraries for better compatibility
          jansson
        ];
      })
      steam-run
    ];

    # Home-manager configuration
    home-manager.users.${config.user.username} = {
      # XDG autostart entry for Steam
      xdg.configFile."autostart/steam.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Steam
        Exec=steam -silent
        X-GNOME-Autostart-enabled=true
        NoDisplay=true
      '';
    };
  };
}
