# Default benchmark variants and workloads for game-bench. The options they
# feed are declared in modules/gaming/default.nix; the reasoning behind each
# entry is in specs/008-game-performance-tuning/research.md.
let
  protonOnly = [ "proton" ];
in
{
  variants = {
    baseline.description = "Current configuration, nothing changed";
    gamemode = {
      description = "Run under gamemoderun";
      gamemode = true;
    };
    ppd-performance = {
      description = "power-profiles-daemon performance profile";
      cpuProfile = "performance";
    };
    ccd0 = {
      description = "Pin to CCD0, the higher-ranked CCD (cores 0-7,16-23)";
      cpus = "0-7,16-23";
    };
    scx-bpfland = {
      description = "sched_ext scx_bpfland";
      scx = "scx_bpfland";
    };
    scx-lavd = {
      description = "sched_ext scx_lavd";
      scx = "scx_lavd";
    };
    scx-bpfland-no-s76 = {
      description = "scx_bpfland with system76-scheduler stopped";
      scx = "scx_bpfland";
      stopSystem76 = true;
    };
    scx-lavd-no-s76 = {
      description = "scx_lavd with system76-scheduler stopped";
      scx = "scx_lavd";
      stopSystem76 = true;
    };
    zen-knobs = {
      description = "Zen's scheduler and I/O defaults on the stock kernel";
      zenKnobs = true;
    };
    wayland-off = {
      description = "Proton's Wayland driver off (XWayland)";
      workloads = protonOnly;
      env.PROTON_ENABLE_WAYLAND = "0";
    };
    nggc = {
      description = "RADV NGG culling (RADV_PERFTEST=nggc)";
      workloads = protonOnly;
      env.RADV_PERFTEST = "nggc";
    };
    gpu-3dfs = {
      description = "amdgpu 3D_FULL_SCREEN power profile";
      workloads = protonOnly;
      gpuProfile = "3d-full-screen";
    };
    cap-max = {
      description = "GPU power limit at the card's maximum";
      workloads = protonOnly;
      gpuPowerCap = "max";
    };
    cap-95 = {
      description = "GPU power limit at 95% of stock";
      workloads = protonOnly;
      gpuPowerCap = "95%";
    };
    cap-90 = {
      description = "GPU power limit at 90% of stock";
      workloads = protonOnly;
      gpuPowerCap = "90%";
    };
  };

  workloads =
    let
      cyberpunk = {
        kind = "proton";
        appid = 1091500;
        # The Phoronix test profile's arguments (pts/cyberpunk2077-1.0.1).
        args = [
          "--launcher-skip"
          "-benchmark"
          "-skipStartScreen"
        ];
      };
    in
    {
      inherit cyberpunk;
      # CPU-bound: the user exports this file once from the game at
      # 1280x720 with upscaling and frame generation off.
      cyberpunk-720p = cyberpunk // {
        settingsFile = "~/.local/share/game-bench/cyberpunk-720p.json";
        settingsTarget = "AppData/Local/CD Projekt Red/Cyberpunk 2077/UserSettings.json";
      };
      factorio = {
        kind = "native";
        appid = 427520;
      };
    };
}
