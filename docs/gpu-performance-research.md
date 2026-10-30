# GPU-limited game performance on `desktop`

Research report. Question: the GPU is usually the bottleneck in games on
`desktop`. What can still make GPU-limited games run better, preferably
system-wide, without benchmarking every game?

Verified on 2026-10-30 against these sources:

- The live system: kernel `7.3.0` (`linuxPackages_latest`), Mesa 26.2.5,
  amdgpu sysfs, the kernel log, the connector EDIDs, and `cosmic-randr`
  1.10.0.
- nixpkgs `02c087f` (`/run/current-system` is `26.11.20261020.02c087f`).
  Paths below are relative to that tree.
- Linux `v7.3` source (`torvalds/linux`).
- GE-Proton11-7 as packaged by nixpkgs (`proton-ge-bin`), which bundles
  vkd3d-proton 3.1.0.
- Upstream docs linked inline. Anything without a primary source is marked
  *unverified*.

Already measured, see `docs/gaming-benchmarks.md`: 290 W power limit
(kept), `3D_FULL_SCREEN`, `RADV_PERFTEST=nggc`, Proton Wayland vs XWayland,
and Zen vs stock kernel. They are not repeated here.

Nothing in the repo was changed except this file.

## TL;DR

1. **VRR is not working on the main monitor.** DP-1 is a Samsung Odyssey
   G80SD (4K, running at 239.9 Hz). `cosmic-randr list` reports `Adaptive
   Sync Support: false`, and the EDID the kernel holds does not meet
   amdgpu's DisplayPort VRR test. At the measured ~40–47 fps on a 240 Hz
   fixed refresh, frame pacing is uneven. VRR does not raise fps, but it
   is the largest *perceived* gain available, and it applies to every
   game. Fixing it is a monitor/cable/EDID problem, not a config problem
   (§5).
2. **Overdrive: undervolt plus a higher power limit.** The card is power
   limited, and the 290 W step already scaled (+9% power → +2.3% fps).
   Enabling overdrive unlocks a voltage offset (`OD_VDDGFX_OFFSET`) and
   raises `power1_cap_max` by the vBIOS overdrive percentage. Expected:
   a few percent, system-wide. Risk: crashes until the offset is tested,
   and the kernel is tainted (§1).
3. **Upscaler choice is the largest fps lever, but per game.** On RDNA3,
   FSR4 runs through an int8/fp16 emulation path in vkd3d-proton "at
   significant performance cost". FSR4 Performance or FSR 3.1 may beat
   FSR4 Balanced in fps (§2).
4. **Frame generation works where a game ships it** (FSR 3.1 FG through
   vkd3d-proton). AMD recommends at least 60 fps before interpolation, so
   at 40–47 fps it is a smoothness trade, not a free gain. AFMF does not
   exist on Linux; `lsfg-vk` is the driver-level alternative (§2).
5. **Mesa/RADV knobs are unlikely to matter.** `RADV_PERFTEST=rtwave64` and
   `sam` are the only untested candidates with a plausible effect on RT
   workloads (§3, §4).

ReBAR is on, the PCIe link is 4.0 x16, and junction temperature limits
are known. Clocks and temperatures under load have not been logged yet
(§6, §7).

## Current state (live)

| Item                      | Value                                         |
| ------------------------- | --------------------------------------------- |
| GPU                       | Navi 31 `1002:744c`, Sapphire `1da2:471e`     |
| VRAM / visible VRAM       | 20464 MiB / 20464 MiB, BAR 32768 MiB          |
| PCIe link (root → GPU)    | 16 GT/s x16 on every hop                      |
| `power1_cap` / max / dflt | 290 W / 290 W / 265 W                         |
| `ppfeaturemask`           | `0xfff7bfff` (kernel default, overdrive off)  |
| `pp_od_clk_voltage`       | absent (overdrive off)                        |
| `pp_dpm_sclk` levels      | 37 / 500 / 2075 MHz                           |
| `pp_dpm_mclk` at idle     | 1249 MHz (top level, two monitors)            |
| Temp crit edge/jct/mem    | 100 / 110 / 108 °C                            |
| DP-1                      | Odyssey G80SD, 3840x2160 @ 239.914 Hz         |
| DP-2                      | ASUS PB278, 2560x1440 @ 59.95 Hz              |
| VRR (`cosmic-randr`)      | not supported on either output, off           |
| Mesa layers (implicit)    | `VK_LAYER_MESA_anti_lag` present, not enabled |

The earlier report calls the card a 7900 XTX. 20 GiB of VRAM means a
7900 **XT**; the XTX has 24 GB. Both share the PCI ID `744c`.

## 1. Overdrive: undervolt, power limit, clocks, fan

**What it unlocks on Navi 31 (SMU 13.0.0):**

- `OD_SCLK` (min/max GFX clock), `OD_MCLK` (min/max memory clock) and
  `OD_VDDGFX_OFFSET` (one voltage offset for the whole V/F curve)
  ([smu_v13_0_0_ppt.c L1263–1293](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/pm/swsmu/smu13/smu_v13_0_0_ppt.c#L1263-L1293)).
  The kernel docs give the model: "voltage = voltage calculated from v/f
  curve + overdrive vddgfx offset", set with `vo -10` and committed with
  `c`; `r` resets
  ([amdgpu thermal docs](https://docs.kernel.org/gpu/amdgpu/thermal.html)).
- A higher power limit. Without overdrive the cap range is the vBIOS
  range (here 290 W). With overdrive it becomes `max × (100 + OD power
  percentage) / 100`
  ([smu_v13_0_0_ppt.c L2429–2452](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/pm/swsmu/smu13/smu_v13_0_0_ppt.c#L2429-L2452),
  used when `od_enabled` in
  [amdgpu_smu.c L2999–3004, L3031–3032](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c#L2999-L3004)).
  The percentage is board-specific. Read `power1_cap_max` after enabling.
- Fan control on RDNA3 needs overdrive (`gpu_od/fan_ctrl/fan_curve`,
  `fan_zero_rpm_enable`, `acoustic_limit_rpm_threshold`;
  [thermal docs](https://docs.kernel.org/gpu/amdgpu/thermal.html),
  [LACT docs](https://github.com/ilya-zlobintsev/LACT/blob/master/docs/Overclocking-(AMD).md)).

**Why an undervolt helps here.** The 4K RT run sits at the power limit
(264 W of 265 W). Lower voltage at each clock lowers power at that clock,
so the SMU can hold higher clocks inside the same cap. The measured
scaling (+9% power → +2.3% p1/avg) is the best available estimate: an
offset that saves ~10% power at the same clock should give a similar
2–3%, and it adds to a higher cap. *Unverified*: the size of a stable
offset on this card. Community reports for Navi 31 are commonly in the
tens of mV, but no primary source gives numbers.

**Memory clock.** `OD_MCLK` exists. *Unverified*: whether VRAM
bandwidth limits this 4K RT workload. Test it last.

**Risk.**

- An offset too deep gives driver resets or game crashes, often only in
  some games. Every value needs a soak test, not just one benchmark.
- Enabling the overdrive bit taints the kernel (`TAINT_CPU_OUT_OF_SPEC`)
  and logs "Overdrive is enabled, please disable it before reporting any
  bugs unrelated to overdrive"
  ([amdgpu_drv.c L3213–3217](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c#L3213-L3217)).
  Enabling the bit alone changes no clocks or voltages.
- Settings written to sysfs are lost on reboot or driver reset, which is
  the recovery path for a bad value.

**How on NixOS (options checked in nixpkgs `02c087f`):**

- `hardware.amdgpu.overdrive.enable = true;` adds
  `amdgpu.ppfeaturemask=<hardware.amdgpu.overdrive.ppfeaturemask>`
  ([amdgpu.nix L25–57](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/nixos/modules/services/hardware/amdgpu.nix#L25-L57)).
  Its default is `0xfffd7fff`, not the kernel default plus the
  overdrive bit. Compared with today's `0xfff7bfff` it also turns
  **off** GFXOFF (`0x8000`) and stutter mode (`0x20000`) and turns **on**
  `PP_GFX_DCS` (`0x80000`)
  ([amd_shared.h L216–235](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/include/amd_shared.h#L216-L235),
  default at
  [amdgpu_drv.c L202](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c#L202)).
  To change only the overdrive bit, set
  `hardware.amdgpu.overdrive.ppfeaturemask = "0xfff7ffff";`.
- `programs.corectrl.gpuOverclock.*` is a renamed alias of the same
  options
  ([corectrl.nix L18–25](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/nixos/modules/hardware/corectrl.nix#L18-L25)).
- `services.lact.enable` runs `lactd` (LACT 0.10.1). `services.lact.settings`
  writes `/etc/lact/config.yaml` and restarts the daemon when it changes,
  so settings apply at boot declaratively. The module says to build the
  settings by configuring in the GUI and copying the generated file
  ([lact.nix L21, L55–64](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/nixos/modules/services/hardware/lact.nix#L55-L64)).
  With `settings` set the GUI cannot save changes.
- Alternative without LACT: extend the existing `gpu-power-cap` unit
  (`modules/gaming/gpu.nix`) to write `vo <mV>` and `c` to
  `pp_od_clk_voltage`. Do not run both: LACT and the unit would both set
  the power cap.

**Already in place:** no. Only the 290 W cap, which needs no overdrive.

## 2. Upscaling and frame generation

| Option                | Works here         | Gain              | Cost                |
| --------------------- | ------------------ | ----------------- | ------------------- |
| FSR4 (in use)         | yes, emulated      | < on RDNA4        | slower than FSR 3.1 |
| FSR 3.1 upscaling     | yes                | baseline          | worse image         |
| FSR 3.1 frame gen     | if the game has it | ~2x shown fps     | latency, artifacts  |
| `lsfg-vk`             | yes, Vulkan layer  | multiplier        | latency, paid app   |
| `WINE_FULLSCREEN_FSR` | winex11 (unverif.) | no-upscaler games | FSR1 quality        |
| AFMF / AFMF 2         | no, Windows only   | n/a               | n/a                 |

- **FSR4 on RDNA3.** vkd3d-proton 3.0 implements FSR4's AGS WMMA ops with
  `VK_KHR_cooperative_matrix` and `VK_KHR_shader_float8`. The default
  build exposes it only "when the native `VK_KHR_shader_float8` is properly
  supported, i.e. RDNA4+ only". An "emulation path … which relies on
  int8 and float16 cooperative matrix support … can run on older GPUs at
  significant performance cost"
  ([vkd3d-proton v3.0](https://github.com/HansKristian-Work/vkd3d-proton/releases/tag/v3.0)).
  GE-Proton enables it for RDNA3 through `PROTON_FSR4_UPGRADE` ("including
  on RDNA3"; `PROTON_FSR4_RDNA3_UPGRADE` is obsolete;
  [GE README](https://github.com/GloriousEggroll/proton-ge-custom/blob/master/README.md)).
  It downloads `amdxcffx64.dll` (`protonfixes/upscalers.py`, GE-Proton11-7).
  Practical consequence: at the same internal resolution, FSR4 costs more
  GPU time than FSR 3.1 on this card. FSR4 Performance often still looks
  better than FSR 3.1 Quality (*unverified*). Benchmark the upscaler
  presets once in Cyberpunk; the result transfers to other FSR4 games.
- **OptiScaler.** GE-Proton downloads and enables it with
  `PROTON_USE_OPTISCALER` (`proton` and `protonfixes/upscalers.py`,
  GE-Proton11-7), so DLSS/XeSS-only games can use FSR. Per game.
- **FSR 3.1 frame generation** runs through vkd3d-proton like any D3D12
  code. AMD: it "runs best when interpolating from a minimum of 60 fps
  pre-interpolation"
  ([GPUOpen](https://gpuopen.com/amd-fsr-framegeneration/)). The 4K RT
  baseline is 46 fps average, so FG here trades latency and artifacts for
  smoothness. vkd3d-proton's anti-lag support "does not take frame-gen into
  account" (v3.0 notes).
- **lsfg-vk** (nixpkgs `lsfg-vk` 2.0.0 and `lsfg-vk-ui`) is a Vulkan layer
  that "generates additional frames" with Lossless Scaling FG
  ([lsfg-vk.dev](https://lsfg-vk.dev/)). It needs a purchased copy of
  Lossless Scaling ("Requires owning Lossless Scaling",
  `pkgs/by-name/ls/lsfg-vk/package.nix`). Being driver-level, it has no
  motion vectors and interpolates the HUD too (*unverified*). Per game.
- **AFMF** is part of AMD Software: Adrenalin for "Windows 10 and 11"
  ([AMD](https://www.amd.com/en/products/software/adrenalin/afmf.html)).
  There is no Linux version.
- **Proton FSR1** (`WINE_FULLSCREEN_FSR=1`) belongs to the "fullscreen
  hack" (GE README). *Unverified*: whether it works with
  `PROTON_ENABLE_WAYLAND=1`. It only helps games without their own
  upscaler.

## 3. Mesa/RADV, vkd3d-proton and DXVK options

From the current Mesa docs ([envvars](https://docs.mesa3d.org/envvars.html)):

| `RADV_PERFTEST=` | Meaning                                 | Verdict            |
| ---------------- | --------------------------------------- | ------------------ |
| `rtwave64`       | wave64 for ray tracing shaders (GFX10+) | candidate (RT)     |
| `sam`            | more driver-internal objects in VRAM    | candidate, small   |
| `pswave32`       | wave32 pixel shaders                    | low prior          |
| `gewave32`       | wave32 vertex/geometry shaders          | low prior          |
| `cswave32`       | wave32 compute shaders                  | low prior          |
| `rtcps`          | CPS lowering instead of function calls  | experimental, skip |
| `nggc`           | NGG culling                             | measured, no gain  |
| `dmashaders`     | shaders to invisible VRAM (no ReBAR)    | n/a, ReBAR on      |

- **ACO vs LLVM:** ACO is the only choice on release builds
  (`RADV_DEBUG=llvm` works "only in debug builds", envvars). Nothing to do.
- **Shader cache size:** `MESA_SHADER_CACHE_MAX_SIZE` (default 1 GB) does
  not apply to Steam games. Steam keeps a per-game single-file cache
  (`steamapps/shadercache/1091500/mesa_shader_cache_sf`), and the
  single-file implementation "doesn't support" the size limit (envvars).
  The cache only affects compile stutter, not GPU-bound throughput.
- **Newer Mesa (mesa-git):** Chaotic-Nyx, the usual NixOS source, was
  archived on 2025-12-08 and later revived
  ([nyx.chaotic.cx](https://www.nyx.chaotic.cx/)). No primary source shows
  a measured RDNA3 RT gain between 26.2 and main. Mesa main moved
  `VK_AMD_anti_lag` into RADV itself (Oct 2026, reported by
  [Phoronix](https://www.phoronix.com/news/Mesa-26.3-RADV-VK_AMD_anti_lag)).
  Not worth a git driver for GPU-bound fps.
- **vkd3d-proton:** none of the documented `VKD3D_CONFIG` flags raises
  GPU-bound performance on AMD. `no_upload_hvv` *lowers* it, and
  `force_static_cbv` is an "unsafe speed hack on NVIDIA"
  ([README](https://github.com/HansKristian-Work/vkd3d-proton/blob/master/README.md)).
  vkd3d-proton 3.1 (in GE-Proton11-7) batches RTAS builds, which
  "massively increases RT performance in some cases"
  ([releases](https://github.com/HansKristian-Work/vkd3d-proton/releases)).
  Already in place.
- **DXVK:** the frame limiter and latency options are listed in §5. The
  README says GPL makes shaders compile "at the time the game loads its
  D3D shaders", which reduces stutter, not GPU time
  ([README](https://github.com/doitsujin/dxvk/blob/master/README.md)).

## 4. Ray tracing on RDNA3

- **RADV vs Windows:** no primary source measures it for this card on
  Mesa 26.2. The work that has landed is visible in release notes (for
  example vkd3d-proton 3.1's RTAS batching) but not quantified for
  RDNA3.
- **What costs most:** RDNA3 has no dedicated BVH traversal hardware;
  RDNA4 added BVH8 (`bvh4` is a RADV option only "on GPUs that support
  bvh8", envvars). *Unverified* for Cyberpunk: path tracing and RT
  Lighting at Psycho cost far more than RT reflections or shadows.
- **Practical advice:** keep RT reflections, lower RT lighting one step,
  avoid path tracing, and let the upscaler absorb the rest. Measure
  `rtwave64` once, because it is a driver-wide switch for all RT games.

## 5. Display path: VRR, tearing, limiters, latency

### VRR is not available on the G80SD

`cosmic-randr list` shows `Adaptive Sync Support: false` for DP-1 and
DP-2, and `vrr: false` in `~/.local/state/cosmic-comp/outputs.ron`.

Why amdgpu says no, from the kernel source:

- On DisplayPort, amdgpu sets `freesync_capable` only from the EDID
  monitor range, and only if the sink allows ignoring MSA timing
  ([amdgpu_dm_connector.c L3906–3913](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm_connector.c#L3906-L3913)).
  The AMD vendor block (VSDB) range is used for HDMI, not native DP.
- DRM fills that range only if the EDID sets the "continuous frequency"
  feature bit and the range descriptor is the "range limits only"
  variant
  ([drm_edid.c L6552–6593](https://github.com/torvalds/linux/blob/v7.3/drivers/gpu/drm/drm_edid.c#L6552-L6593)).

The DP-1 EDID now in `/sys/class/drm/card1-DP-1/edid` (decoded with
`edid-decode`) fails both: feature byte `0x3a` (continuous bit 0), and the
range descriptor is "Monitor ranges (GTF): 30-120 Hz". Its AMD VSDB says
48–120 Hz. It also lists no 240 Hz mode, yet COSMIC drives the panel at
239.914 Hz and the kernel's mode list has no such mode. The EDID the
kernel holds is therefore not the one the 240 Hz mode came from.
*Unverified* cause: the monitor's Adaptive-Sync/FreeSync or DisplayPort
version OSD setting, or a fallback EDID after a hotplug or standby.

What to do (no config change):

1. In the monitor OSD, turn on Adaptive-Sync (FreeSync Premium Pro) and
   set the highest DisplayPort version.
2. Power-cycle the monitor or re-plug DP, then run `cosmic-randr list`
   and look for `Adaptive Sync Support: true`.
3. Turn VRR on in COSMIC Settings → Displays, or
   `cosmic-randr mode DP-1 3840 2160 --refresh 239.914 --adaptive-sync
   automatic` (`true`, `automatic` and `false` are the allowed values,
   from `cosmic-randr mode --help`). An upstream report says changes take
   effect only after restarting cosmic-comp
   ([cosmic-comp #2674](https://github.com/pop-os/cosmic-comp/issues/2674)).

### Tearing and present modes

cosmic-comp does not implement the Wayland tearing-control protocol yet
([cosmic-comp #248](https://github.com/pop-os/cosmic-comp/issues/248),
open). Games under COSMIC cannot tear, with or without the Proton Wayland
driver. With VRR working, this costs little; without it, "vsync off" at
46 fps on 240 Hz gives uneven frame times.

### Frame limiters

- **MangoHud** `fps_limit=<n>`, `fps_limit_method=late` ("lowest latency",
  the default) ([README](https://github.com/flightlessmango/MangoHud/blob/master/README.md)).
  System-wide through `MANGOHUD_CONFIG` or `~/.config/MangoHud`.
- **DXVK** `dxgi.maxFrameRate` (env `DXVK_FRAME_RATE`, which GE-Proton
  maps to `DXVK_CONFIG` in `proton`) says "DO NOT USE THIS IF EXTERNAL
  LIMITERS ARE AVAILABLE. Limiters from Mangohud or Gamescope WILL provide
  a significantly better experience"
  ([dxvk.conf](https://github.com/doitsujin/dxvk/blob/master/dxvk.conf)).
  vkd3d-proton has `VKD3D_FRAME_RATE`.
- A cap a little below the lowest sustained fps gives flat frame times
  and keeps the GPU off its power limit in light scenes. It only makes
  sense once VRR works, or at an integer divisor of the refresh rate
  (60 or 80 Hz on a 240 Hz panel).

### Anti-lag

- Mesa 26.2.5 ships `VK_LAYER_MESA_anti_lag` as an implicit layer
  (nixpkgs builds it: `vulkanLayers ? [ "anti-lag" ]`,
  `pkgs/development/libraries/mesa/default.nix` L107–108). Its manifest
  has `enable_environment: ENABLE_LAYER_MESA_ANTI_LAG=1`, so it is off
  unless that is set
  ([Vulkan loader](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderLayerInterface.md)).
- vkd3d-proton uses `VK_AMD_anti_lag` "when exposed" (v3.0); DXVK uses
  `VK_NV_low_latency2` for Reflex games.
- GE-Proton's `LOW_LATENCY_LAYER=1` loads Korthos `low_latency_layer`,
  which exposes `VK_NV_low_latency2` and `VK_AMD_anti_lag`. Its README
  says Anti-Lag 2 "appears broken in Cyberpunk 2077" on Linux (use its
  Reflex mode there) and that Mesa's layer "appeared to be a no-op" in
  the author's tests
  ([README](https://github.com/Korthos-Software/low_latency_layer)).
- Anti-lag lowers latency, not GPU time. It may cost a little fps.
  Low priority for fps; worth a try for feel at 40–50 fps.

## 6. Resizable BAR

**Enabled.** The boot log says `Detected VRAM RAM=20464M, BAR=32768M`,
and `mem_info_vis_vram_total` equals `mem_info_vram_total` (both
21458059264 bytes). A BAR at least as large as VRAM means the whole VRAM
is CPU-visible. RADV then applies its "all VRAM is CPU-visible"
optimisations by default (they can be turned off with `nosam`, envvars),
and vkd3d-proton uses host-visible VRAM for the UPLOAD heap unless
`no_upload_hvv` is set (README). Nothing to do.

## 7. PCIe link, clocks and thermals

- **PCIe:** every hop from root port `00:01.1` to the GPU runs at
  16 GT/s x16 (PCIe 4.0, the card's maximum; the root port could do
  32 GT/s). Nothing to do.
- **Memory clock at idle** stays at 1249 MHz, the top level, with two
  monitors at different timings. That costs idle power, not game fps.
- **Clocks under load are not logged.** `game-bench` records frame times
  and power (`power.csv`) only. The idle `pp_dpm_sclk` top level is
  2075 MHz. *Unverified*: how close the 4K RT run gets to it. Add
  `freq1_input` (sclk), `temp2_input` (junction) and `fan1_input` to the
  harness's power sampler.
- **Throttling:** junction critical is 110 °C, memory 108 °C
  (`temp2_crit`, `temp3_crit`). MangoHud's `throttling_status` shows "if
  GPU is throttling based on Power, current, temp or other" (README).
  Expect `Power` in the 4K run. Temperature throttling would show up as
  clocks falling over a long run; a steeper fan curve (needs overdrive,
  §1) is the fix.

## 8. Other levers

- **Settings that scale with power:** the 290 W cap result shows the card
  converts power into fps at about 1:4. Anything that lowers power at a
  given clock (undervolt, lower junction temperature through leakage)
  is worth roughly the same. *Unverified* for leakage.
- **Second monitor:** DP-2 is composited while a game runs. *Unverified*:
  the cost is likely well under 1% for a static 60 Hz desktop.
- **`power_dpm_force_performance_level=high`:** on a power-limited card
  this pins clocks and can remove boost headroom (earlier report, §6).
  Not recommended.

## Candidates to benchmark next

All run with the existing `cyberpunk` workload (4K, RT, FSR4 Balanced).
The overdrive variants need `hardware.amdgpu.overdrive.enable = true`
with `ppfeaturemask = "0xfff7ffff"` on the booted system; after that,
each one is a runtime sysfs write the harness can reset with `r`.

| Variant       | Sets                                     | Expected     | Risk   |
| ------------- | ---------------------------------------- | ------------ | ------ |
| `od-baseline` | overdrive bit on, nothing written        | = baseline   | none   |
| `cap-od-max`  | `power1_cap` = new `power1_cap_max`      | +1–3%        | low    |
| `uv-50`       | `vo -50`, `c` to `pp_od_clk_voltage`     | +2–3%        | medium |
| `uv-80`       | `vo -80`, `c`                            | +3–4%        | high   |
| `uv-50-cap`   | `uv-50` + `cap-od-max`                   | +3–5%        | medium |
| `mclk-oc`     | `OD_MCLK` max +100 MHz (`m 1 <max+100>`) | 0–2%         | medium |
| `rtwave64`    | env `RADV_PERFTEST=rtwave64`             | ±, RT only   | low    |
| `sam`         | env `RADV_PERFTEST=sam`                  | 0–1%         | low    |
| `fsr4-perf`   | settings file: FSR4 Performance          | +10–20% fps  | none   |
| `fsr31-qual`  | settings file: FSR 3.1 Quality           | compare FSR4 | none   |

Sources: §1 (kernel `smu_v13_0_0_ppt.c`, `amdgpu_smu.c`, thermal docs),
§3 (Mesa envvars), §2 (vkd3d-proton v3.0 notes). The expected gains are
estimates from the measured power scaling, not measurements. Notes:

- `od-baseline` checks that flipping the mask alone changes nothing.
- An undervolt that passes the benchmark still needs a soak (an hour of
  play in two or three games) before it goes into `services.lact` or the
  `gpu-power-cap` unit. A failure shows up as a game crash or an amdgpu
  ring timeout in `journalctl -k`.
- `fsr4-perf` and `fsr31-qual` are per-game choices, but measuring them
  once tells whether FSR4's emulation cost on RDNA3 is worth its image
  quality in general.
- Log `freq1_input` and `temp2_input` alongside power for every variant.

## Checks the user can run now

```bash
# VRR: want "Adaptive Sync Support: true" on DP-1, and the current mode
cosmic-randr list
# EDID the kernel holds for DP-1 (continuous-frequency bit, range limits)
nix-shell -p edid-decode --run 'edid-decode /sys/class/drm/card1-DP-1/edid'

# ReBAR: BAR >= VRAM, and visible VRAM == VRAM
journalctl -k -b | grep 'Detected VRAM'
cat /sys/class/drm/card1/device/mem_info_{vram,vis_vram}_total
sudo lspci -vv -s 03:00.0 | grep -A3 'Resizable BAR'

# PCIe link, root port to GPU
for d in 0000:00:01.1 0000:01:00.0 0000:03:00.0; do
  echo "$d $(cat /sys/bus/pci/devices/$d/current_link_{speed,width})"; done

# Clocks, power and temperatures while a game runs (1 s interval)
h=$(echo /sys/class/drm/card1/device/hwmon/hwmon*)
watch -n1 "cat $h/freq1_input $h/power1_average $h/temp2_input $h/fan1_input"
# Or in the game: MANGOHUD_CONFIG=gpu_core_clock,gpu_junction_temp,gpu_power,throttling_status

# Overdrive state and limits (after enabling it)
cat /sys/module/amdgpu/parameters/ppfeaturemask
cat /sys/class/drm/card1/device/pp_od_clk_voltage
cat $h/power1_cap_max
```

If VRR turns out to be available, it changes the ranking. With VRR on,
a frame cap and anti-lag become cheap smoothness gains, and
undervolting matters a little less for perceived smoothness. If the new
`power1_cap_max` after enabling overdrive is not above 290 W, only the
undervolt variants remain in §1.
