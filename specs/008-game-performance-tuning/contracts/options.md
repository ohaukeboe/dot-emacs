# Contract: `modules.gaming` options

All options live in `modules/gaming/`. Everything is inside
`mkIf cfg.enable` (Principle V). Phase 2 options are marked.

```nix
modules.gaming = {
  enable = mkEnableOption "Gaming module";

  benchmark = {
    # FR-010: only exists where gaming is enabled.
    enable = mkOption { type = types.bool; default = true; };

    variants = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description  = mkOption { type = types.str; };
          workloads    = mkOption { type = types.listOf (types.enum [ "proton" "native" ]);
                                    default = [ "proton" "native" ]; };
          gamemode     = mkOption { type = types.bool; default = false; };
          cpus         = mkOption { type = types.nullOr (types.strMatching "[0-9,-]+");
                                    default = null; };
          env          = mkOption { type = types.attrsOf types.str; default = { }; };
          cpuProfile   = mkOption { type = types.nullOr (types.enum [ "performance" ]);
                                    default = null; };
          scx          = mkOption { type = types.nullOr (types.enum [ "scx_bpfland" "scx_lavd" ]);
                                    default = null; };
          stopSystem76 = mkOption { type = types.bool; default = false; };
          zenKnobs     = mkOption { type = types.bool; default = false; };
          gpuProfile   = mkOption { type = types.nullOr (types.enum [ "3d-full-screen" ]);
                                    default = null; };
          gpuPowerCap  = mkOption { type = types.nullOr (types.oneOf [ types.ints.positive
                                      (types.strMatching "[0-9]{1,3}%") (types.enum [ "max" ]) ]);
                                    default = null; };
        };
      });
      # Defaults: the FR-008 set (see below).
    };

    workloads = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          kind         = mkOption { type = types.enum [ "proton" "native" ]; };
          appid        = mkOption { type = types.ints.positive; };
          args         = mkOption { type = types.listOf types.str; default = [ ]; };
          settingsFile = mkOption { type = types.nullOr types.str; default = null; };
          # Relative to the Proton prefix's drive_c/users/steamuser.
          settingsTarget = mkOption { type = types.nullOr types.str; default = null; };
          logDelay     = mkOption { type = types.ints.unsigned; default = 20; };
          logSeconds   = mkOption { type = types.ints.positive; default = 60; };
          ticks        = mkOption { type = types.ints.positive; default = 6000; };
          timeout      = mkOption { type = types.ints.positive; default = 900; };
        };
      });
    };

    # FR-011 / FR-013: the derivation rebuilt as background load and timed.
    loadPackage = mkOption { type = types.package; };
  };

  # FR-022: stock kernel of Zen's series as a boot entry tagged "stock".
  kernelComparison.enable = mkOption { type = types.bool; default = false; };

  # Phase 2, FR-028. null = stock limit. Range checked at runtime against
  # power1_cap_{min,max}; out of range = unit fails, cap stays stock.
  gpu.powerCapWatts = mkOption { type = types.nullOr types.ints.positive; default = null; };

  # Phase 2, FR-019: adopted per-game tunings, merged into Steam's env.
  tunings.env = mkOption { type = types.attrsOf types.str; default = { }; };
};
```

## Default variants (FR-008)

| Name                 | Settings                                                    |
| -------------------- | ----------------------------------------------------------- |
| `baseline`           | none                                                        |
| `gamemode`           | `gamemode = true`                                           |
| `ppd-performance`    | `cpuProfile = "performance"`                                |
| `ccd0`               | `cpus = "0-7,16-23"`                                        |
| `scx-bpfland`        | `scx = "scx_bpfland"`                                       |
| `scx-lavd`           | `scx = "scx_lavd"`                                          |
| `scx-bpfland-no-s76` | `scx = "scx_bpfland"; stopSystem76 = true`                  |
| `scx-lavd-no-s76`    | `scx = "scx_lavd"; stopSystem76 = true`                     |
| `zen-knobs`          | `zenKnobs = true`                                           |
| `wayland-off`        | `env.PROTON_ENABLE_WAYLAND = "0"`, proton only              |
| `nggc`               | `env.RADV_PERFTEST = "nggc"`, proton only                   |
| `gpu-3dfs`           | `gpuProfile = "3d-full-screen"`, proton only                |
| `cap-max`            | `gpuPowerCap = "max"`, proton only                          |
| `cap-95`, `cap-90`   | `gpuPowerCap = "95%"` / `"90%"`, proton only                |

`no-ntsync` from the research note is not a default: ntsync is on and
needs no decision. Users add variants by adding an attrset entry.

## Assertions

- `benchmark.variants.baseline` exists and sets nothing.
- No variant sets both `scx` and `zenKnobs`; `stopSystem76` requires `scx`.
- `kernelComparison.enable` requires the Zen kernel to be the configured
  default, and nixpkgs to have the stock series matching it (R8); the
  message names `common/system/system.nix`.
- `gpu.powerCapWatts` set requires an amdgpu GPU (`hardware.amdgpu` or the
  `amdgpu` early-KMS module present).

## Machine wiring (`machines/machines.nix`, desktop)

```nix
{ modules.gaming.enable = true; }
{ modules.gaming.kernelComparison.enable = true; }
```
