# Gaming performance on `desktop`: what to change and how to benchmark it

Research report. Question: is there anything in the config that can make
games perform better on `desktop`, and can each proposed change be
benchmarked automatically?

Verified on 2026-10-27 against the running system and these sources:

- nixpkgs `02c087f` (`nixpkgs_6` in `flake.lock`, matches
  `/run/current-system` `26.11.20261020.02c087f`). Module paths below are
  relative to that tree (`nixos/modules/...`).
- Linux `v7.2` (`torvalds/linux`); the running kernel is `7.2.11-zen1`.
- The Proton builds installed in Steam: Valve `proton-11.0-2e`,
  Proton Experimental `experimental-11.0-20261001`, and `GE-Proton11-1`
  (manual install). nixpkgs ships `proton-ge-bin` `GE-Proton11-7`.
- Upstream docs linked inline. Anything not checked against a primary
  source is marked *unverified*.

Nothing in the repo was changed. The Nix snippets and the script are proposals.

## TL;DR

The desktop is already in good shape. It runs the zen kernel (1000 Hz, full
preemption), RADV with Mesa 26.2.5, `vm.max_map_count = 1048576`,
ntsync, GE-Proton by default, and Steam with gamescope and extest. The gains
that are left mostly come from things that are configured but **not
actually in effect**:

1. **GameMode never runs for Steam games.** Only the `gamescope-game`
   wrapper calls `gamemoderun`. Also, `oskar` is not in the `gamemode`
   group, so GameMode's `renice` and `park_cores` would not work even if it
   did run.
2. **No sched_ext scheduler is loaded** (`/sys/kernel/sched_ext/state` =
   `disabled`), although the kernel has `CONFIG_SCHED_CLASS_EXT=y`.
   `scx_bpfland` and `scx_lavd` are built for gaming-style interactive
   loads. This is the most likely change to improve 1% lows.
3. **The 9950X has two CCDs and no V-Cache.** Pinning a game to CCD0
   (`0-7,16-23`, the cores with the higher preferred-core ranking) avoids
   cross-CCD cache misses. GameMode only does this automatically on X3D
   and hybrid CPUs.
4. **`PROTON_ENABLE_WAYLAND=1` only matters for GE-Proton.** Valve Proton
   11.0 and Experimental ship no `winewayland` driver, so for games forced
   onto them the variable does nothing. It works for the default tool
   (`GE-Proton`). Benchmark it per game rather than assuming it is faster.
5. **GPU side (opt-in, measure first):** `RADV_PERFTEST=nggc` (NGG culling
   for GFX11, which includes the 7900 XTX), and amdgpu's `3D_FULL_SCREEN`
   power profile or a raised power limit via LACT.

All of these can be switched per run without a rebuild, so one script can
benchmark them: a Steam launch-option wrapper reads the variant for each
run, Cyberpunk 2077's built-in benchmark is the workload, and MangoHud
CSV logs are summarised as average FPS, 1% low and frametime spread.

## Current state

### Hardware (live, `desktop`)

- CPU: AMD Ryzen 9 9950X, 16C/32T. There are two L3 domains:
  `cpu0` shares L3 with `0-7,16-23` and `cpu8` with `8-15,24-31`.
  `amd_pstate_prefcore_ranking` is 206–236 on cores 0–7 and 166–201 on
  cores 8–15, so the firmware ranks CCD0 as the faster CCD.
- GPU: Sapphire PULSE RX 7900 XTX (Navi 31, `1002:744c`), `amdgpu`,
  20 GiB VRAM. Two DP outputs connected.
- RAM 62 GiB, zram swap 31 GiB (unused at the time of measurement).
- Storage: NVMe ×2 (scheduler `kyber`), one SATA disk (`bfq`).

### Software and tunables (live)

| Item                      | Value                         | Set by                   |
| ------------------------- | ----------------------------- | ------------------------ |
| Kernel                    | 7.2.11-zen1, HZ=1000, PREEMPT | `common/system`          |
| cpufreq driver / gov      | amd-pstate-epp / powersave    | kernel default, PPD      |
| EPP                       | `balance_performance`         | PPD "balanced"           |
| power-profiles-daemon     | active, `balanced`            | `modules/cosmic-de`      |
| system76-scheduler        | active                        | `modules/cosmic-de`      |
| sched_ext                 | `disabled`                    | not configured           |
| `vm.max_map_count`        | 1048576                       | nixpkgs `sysctl.nix`     |
| `split_lock_mitigate`     | 0                             | *unverified* (see below) |
| THP enabled / defrag      | madvise / defer+madvise       | kernel config            |
| `sched_autogroup_enabled` | 0                             | *unverified*             |
| ntsync                    | `=y`, device present          | kernel                   |
| amdgpu level / profile    | auto / BOOTUP_DEFAULT         | defaults                 |
| amdgpu `ppfeaturemask`    | 0xfff7bfff (no overdrive)     | defaults                 |
| Mesa                      | 26.2.5                        | nixpkgs                  |
| Default compat tool       | GE-Proton (nixpkgs 11-7)      | Steam `config.vdf`       |

### Gaming module (`modules/gaming/default.nix`)

- `programs.steam` sets `extraEnv.PROTON_ENABLE_WAYLAND = "1"` (commit
  `54900b2`), `extraCompatPackages = [ proton-ge-bin ]`,
  `gamescopeSession.enable`, `extest.enable` and the firewall openings.
- `programs.gamemode.enable = true` with **no `settings`**, so
  `/etc/gamemode.ini` is empty and upstream defaults apply.
- `programs.gamescope.enable = true`, `capSysNice = false`.
- `gamescope-game` wrapper: `gamemoderun gamescope --adaptive-sync -f
  --hdr-enabled -w W -h H --force-grab-cursor --mouse-sensitivity 1.5 -g`.
  It calls `${pkgs.gamescope}` directly, so it would bypass the
  `capSysNice` security wrapper even if that were turned on
  (`programs/gamescope.nix` L71–80).
- Installed games include Cyberpunk 2077 (1091500), Expedition 33,
  Ghostrunner, Guild Wars 2, NieR:Automata, Satisfactory, Subnautica 2,
  Wuthering Waves (pinned to `GE-Proton11-1`) and X4.

Only `desktop` enables `modules.gaming` (`machines/machines.nix`).

## Ranked recommendations

Impact is a prior estimate, not a measurement; the benchmark plan below is
how to replace it with numbers.

| #   | Change                                      | Expected impact     | Risk   |
| --- | ------------------------------------------- | ------------------- | ------ |
| 1   | Actually run GameMode for Steam games       | low–med (CPU-bound) | low    |
| 2   | sched_ext: `scx_bpfland` (or `scx_lavd`)    | med on 1% lows      | low    |
| 3   | Pin games to CCD0 (`0-7,16-23`)             | low–med, per game   | low    |
| 4   | Benchmark `PROTON_ENABLE_WAYLAND` per game  | ± per game          | low    |
| 5   | `RADV_PERFTEST=nggc`                        | ± small, GPU-bound  | low    |
| 6   | amdgpu `3D_FULL_SCREEN` / LACT power limit  | small–med, GPU      | medium |
| 7   | Add user to `gamemode` group, set renice    | small               | low    |
| 8   | gamescope only when needed; `--hdr` opt-in  | small               | low    |

Already done or not applicable (details at the end): kernel choice,
`vm.max_map_count`, ntsync, split-lock mitigation, THP, zram, I/O scheduler,
`hardware.graphics.enable32Bit`, NVIDIA/PRIME.

## 1. GameMode for Steam games

**What:** GameMode switches the CPU governor to `performance` and can
renice the game, raise its I/O priority, turn off split-lock mitigation,
pin or park cores, and set the AMD GPU performance level
([example gamemode.ini](https://github.com/FeralInteractive/gamemode/blob/master/example/gamemode.ini)).

**Why it is not in effect now:** Steam games start through the Steam
client, and nothing in that path calls `gamemoderun` or preloads
`libgamemodeauto`. Only the `gamescope-game` wrapper does.

**What it changes on this CPU:** with `amd-pstate-epp`, switching the
governor to `performance` also forces EPP to `performance`:
`amd-pstate.c` refuses any other EPP under the performance policy
([L1384–1386, L1425–1427](https://github.com/torvalds/linux/blob/v7.2/drivers/cpufreq/amd-pstate.c#L1425-L1427)),
and for that policy it raises MinPerf to nominal
([L704–710](https://github.com/torvalds/linux/blob/v7.2/drivers/cpufreq/amd-pstate.c#L704-L710)).
Today PPD's "balanced" profile writes governor `powersave` + EPP
`balance_performance`
([ppd-driver-amd-pstate.c](https://gitlab.freedesktop.org/upower/power-profiles-daemon/-/blob/main/src/ppd-driver-amd-pstate.c)).
On a desktop with no battery the difference is mainly how fast the
cores ramp up and how low they drop between frames. Expect it to matter
in CPU-bound titles (X4, Satisfactory), not GPU-bound ones.

**How:**

- Per game, no rebuild: Steam launch option `gamemoderun %command%`.
- Globally: the Steam package already sets `LD_PRELOAD` for extest
  (`programs/steam.nix` L63–65), and the module's own `extraEnv`
  (`prev.extraEnv`) overrides it. A global `LD_PRELOAD` for
  `libgamemodeauto` would therefore have to include the extest path too,
  or extest breaks. Per-game launch options are simpler and avoid this.
- Equivalent without GameMode: `powerprofilesctl set performance` (same
  governor + EPP writes, by the PPD source above). The setting is global
  rather than tied to the game.

Suggested settings, all from the example ini:

```nix
programs.gamemode.settings = {
  general = {
    renice = 10;          # needs the gamemode group, see #7
    ioprio = 0;
    softrealtime = "off"; # SCHED_ISO only exists on patched kernels
  };
  cpu = {
    # pin_cores = "0-7,16-23";  # see #3; benchmark first
    park_cores = "no";
  };
};
```

GameMode's `desiredprof` writes `/sys/firmware/acpi/platform_profile`,
which this desktop does not have, so it is a no-op here.

## 2. sched_ext scheduler

**What:** `CONFIG_SCHED_CLASS_EXT=y` is set in the zen kernel, but no
BPF scheduler is loaded.

- `scx_bpfland` is aimed at "Interactive workloads, such as gaming, live
  streaming, multimedia, real-time audio encoding/decoding". Upstream says
  it "can be considered ready for production use"
  ([README](https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_bpfland/README.md)).
- `scx_lavd` was "initially motivated by gaming workloads" and aims to
  "reduce stuttering while playing games on Linux". However, it "mainly
  targets single CCX / single-socket systems" and is "new and still
  evolving"
  ([README](https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md)).
  The 9950X has two CCDs, so `scx_bpfland` is the better first candidate.
  Benchmark both.

nixpkgs ships scx `1.1.4` with `scx_bpfland`, `scx_lavd`, `scx_cosmos`
and `scx_flash` (`pkgs/os-specific/linux/scx/scx_rustscheds.nix`).

**NixOS:** `services.scx` (`nixos/modules/services/scheduling/scx.nix`):

```nix
services.scx = {
  enable = true;
  scheduler = "scx_bpfland";  # default is scx_rustland
  # extraArgs = [ ];
};
```

The unit reads `SCX_SCHEDULER_OVERRIDE` / `SCX_FLAGS_OVERRIDE` before the
configured values (scx.nix L80–82), so a scheduler can be switched without
a rebuild. `services.scx-loader` is the alternative if the DBus loader
(for example a GUI switcher) is wanted.

**Risk and interaction:** if the BPF scheduler exits or fails, the
kernel falls back to the default scheduler. The service also has
`Restart = on-failure`. system76-scheduler (from `modules/cosmic-de`) tunes CFS/EEVDF
parameters and process nice values. *Unverified*: how its tunables and
nice-based foreground boost interact with a sched_ext scheduler. The
benchmark should include "scx on, system76-scheduler stopped" as its own
variant before keeping both.

## 3. Pin games to CCD0

The two CCDs have separate L3 caches (`index3/shared_cpu_list` above).
A game whose threads move between CCDs pays cross-CCD latency.
GameMode's `pin_cores` autodetects only "Ryzen 7900X3D/7950X3D and
Intel E/P-core CPUs"
([example ini](https://github.com/FeralInteractive/gamemode/blob/master/example/gamemode.ini)),
so on a 9950X it must be given an explicit list:
`pin_cores = "0-7,16-23"`. Without GameMode, use the Steam launch option
`taskset -c 0-7,16-23 %command%`.

Tradeoff: games that scale past 8 cores / 16 threads lose throughput.
Results will differ per game, which is why this should be benchmarked
rather than enabled globally. `scx_bpfland`/`scx_lavd` may also make it
unnecessary, since they consider the LLC topology (lavd README:
"per-LLC" domains).

## 4. `PROTON_ENABLE_WAYLAND`

Checked against the installed builds:

| Proton build                  | `winewayland` files | `PROTON_ENABLE_WAYLAND` handled |
| ----------------------------- | ------------------- | ------------------------------- |
| Valve Proton 11.0             | 0                   | no                              |
| Proton Experimental (11.0)    | 0                   | no                              |
| GE-Proton11-1 (and nixpkgs)   | 6                   | yes (`proton` L1920)            |

The Valve Proton 11.0 README options table has no `PROTON_ENABLE_WAYLAND`
([README](https://github.com/ValveSoftware/Proton/blob/proton_11.0/README.md)).
GE-Proton describes it as "Enables the Wayland driver" and recommends it for HDR "when using a
native Wayland desktop outside Gamescope"
([README](https://github.com/GloriousEggroll/proton-ge-custom/blob/master/README.md)).
Its `check_environment` reads `0` as off (`proton` L1750–1757), so a
per-game launch option `PROTON_ENABLE_WAYLAND=0 %command%` overrides the
global setting.

The GE README documents no performance claim and no caveats.
*Unverified*: Steam overlay, IME and window-management regressions under
winewayland. Keep the global setting if the per-game benchmark shows no
regression, and set it to `0` for games that misbehave.

## 5. `RADV_PERFTEST=nggc`

Mesa documents `nggc` as "enable NGG culling for GFX11+"
([envvars](https://docs.mesa3d.org/envvars.html)). The 7900 XTX is GFX11,
and because the flag is under `RADV_PERFTEST` it is opt-in. Geometry-heavy
games may gain, and others may lose a little. Apply it per game or globally via
`programs.steam.package = pkgs.steam.override { extraEnv = { ...;
RADV_PERFTEST = "nggc"; }; }` only if the benchmark shows a gain.
`RADV_PERFTEST=sam` ("move more driver internal objects to VRAM") is a
second low-risk candidate.

## 6. amdgpu power profile and power limit

- `power_dpm_force_performance_level` is `auto`. `high` forces the
  highest clocks. `manual` allows writing a profile index to
  `pp_power_profile_mode`, for example `1` = `3D_FULL_SCREEN`
  ([amdgpu thermal docs](https://docs.kernel.org/gpu/amdgpu/thermal.html)).
  On a power-limited card, forcing `high` can remove boost headroom
  instead of adding it. Measure before adopting.
- GameMode can set `gpu.amd_performance_level = "high"` with
  `apply_gpu_optimisations = "accept-responsibility"` (example ini, and
  the nixpkgs module example warns these "have the potential to damage
  hardware").
- `services.lact` (nixpkgs) manages profiles, power limit and
  undervolt. A power limit above stock or an undervolt needs
  `hardware.amdgpu.overdrive.enable = true`
  (`nixos/modules/services/hardware/amdgpu.nix` L26). Today's
  `ppfeaturemask` `0xfff7bfff` has the overdrive bit (`0x4000`) off.
  On RDNA3 an undervolt is often the largest single GPU gain. This is
  community knowledge, *unverified* against a primary source, and needs a
  stability test per card.

## 7. `gamemode` group and renice

`renice` and `park_cores` "require membership in the `gamemode` group"
(example ini). The nixpkgs module creates the group
(`programs/gamemode.nix`, `users.groups.gamemode`) but adds no users,
and `getent group gamemode` shows it empty. Fix:

```nix
users.users.${config.user.username}.extraGroups = [ "gamemode" ];
```

(inside `modules/gaming/default.nix`, next to the home-manager block).

## 8. gamescope

> **Superseded**: gamescope was removed from the configuration
> (`specs/008-game-performance-tuning/spec.md`, ADR 0009).

`gamescope-game` always nests gamescope with `--hdr-enabled`. Nesting
gives the game its own Xwayland "sandbox"
([gamescope README](https://github.com/ValveSoftware/gamescope/blob/master/README.md)),
but adds a compositing step. Benchmark the same game in three ways: native
with Proton Wayland, native with XWayland, and in `gamescope-game`. Use the wrapper only where it
helps (scaling, frame limiting, HDR). `programs.gamescope.capSysNice`
does not affect this wrapper (see Current state). *Unverified*: whether
`capSysNice` works inside Steam's pressure-vessel container. Leave it off.

## Already set or not applicable

- **Kernel:** zen with HZ=1000 and full preemption. There is no reason to
  change it. `laptop` uses `linuxPackages_latest` because of a hibernate
  bug, which does not affect `desktop`.
- **`vm.max_map_count`:** nixpkgs already defaults it to 1048576
  (`nixos/modules/config/sysctl.nix` L118).
- **ntsync:** `CONFIG_NTSYNC=y`, and the misc device is created with
  `.mode = 0666`
  ([ntsync.c](https://github.com/torvalds/linux/blob/v7.2/drivers/misc/ntsync.c)).
  It needs no udev rule. GE-Proton sets `WINENTSYNC=1` unless
  `PROTON_NO_NTSYNC` is set (`proton` L1937–1943). Valve Proton 11's
  wineserver has `/dev/ntsync` and `PROTON_NO_NTSYNC` built in, and its
  README lists `PROTON_NO_NTSYNC` "Do not use ntsync". Nothing to add. To
  confirm, run one game with `PROTON_LOG=1` and look for
  `ntsync: up and running.` (a string in both wineservers). `/dev` is
  hidden inside the agent sandbox, so this was not checked live.
- **Split-lock mitigation:** `kernel.split_lock_mitigate` is a penalty
  for split locks on x86 ([kernel sysctl docs](https://docs.kernel.org/admin-guide/sysctl/kernel.html)).
  The 9950X exposes only `bus_lock_detect`, not `split_lock_detect`, in
  `/proc/cpuinfo`, and the sysctl is already 0. *Unverified*: what sets it to 0
  (zen config or a default). It does not apply here either way.
- **THP:** `madvise` is the kernel default here. Changing it to `always`
  is not supported by any primary source as a gaming gain. Skip it.
- **zram / swappiness:** 62 GiB RAM and 0 B swap used. It does not apply.
- **I/O scheduler:** affects load times at most, not frame times. Skip it.
- **`hardware.graphics.enable32Bit`:** already forced by `programs.steam`
  (`programs/steam.nix` "glXChooseVisual" block).
- **NVIDIA / PRIME:** `desktop` is all-AMD.
- **VRR:** gamescope-game passes `--adaptive-sync`. *Unverified*: whether
  COSMIC (cosmic-comp 1.10) has adaptive sync enabled for both DP outputs.
  Connector `vrr_capable` is a DRM property, not sysfs, so it could not be
  read from here. Check COSMIC Settings → Displays.

## Benchmark plan

### Workload

- **Primary: Cyberpunk 2077 built-in benchmark** (installed, appid
  1091500). The game arguments are
  `--launcher-skip --intro-skip -benchmark`. Results are written to
  `<prefix>/drive_c/users/steamuser/Documents/CD Projekt Red/Cyberpunk 2077/benchmarkResults/benchmark_<date>/summary.json`
  with `.Data.averageFps`
  ([dolpa.me write-up](https://www.dolpa.me/running-the-cyberpunk-2077-benchmark-from-the-ubuntu-terminal-with-proton-my-journey/),
  a blog rather than CDPR documentation, so *unverified*). *Unverified*: that
  `steam -applaunch 1091500 <args>` passes the args through and that the
  game exits by itself when the run ends. The script below handles both
  cases with a timeout.
- **CPU-bound check:** a fixed save in X4 or Satisfactory, or any game
  with a repeatable scene. Log a fixed window with MangoHud.
- **Synthetic GPU-only (for #5, #6):** `vkmark` and `unigine-superposition`
  are in nixpkgs (`pkgs/by-name/vk/vkmark`,
  `pkgs/by-name/un/unigine-superposition`). They are useful for driver and
  power variants, not for Proton or scheduler ones. `phoronix-test-suite`
  10.8.4 is also packaged. *Unverified*: whether its Steam game profiles
  work on NixOS.

### Measurement: MangoHud

Options from the [MangoHud README](https://github.com/flightlessmango/MangoHud/blob/master/README.md):
`autostart_log=<s>`, `log_duration=<s>`, `log_interval=<ms>` (0 = every
frame), and `output_folder=` ("Required for logging"), passed through
`MANGOHUD_CONFIG`. `MANGOHUD=1` enables the Vulkan layer, so it covers
DXVK/VKD3D under Proton. From
[`src/logging.cpp`](https://github.com/flightlessmango/MangoHud/blob/master/src/logging.cpp),
the file is `<output_folder>/<program>_YYYY-MM-DD_HH-MM-SS.csv`:

- line 1: `os,cpu,gpu,ram,kernel,driver,cpuscheduler`;
- line 2: the values for those fields (with `log_versioning` a
  `----SYSTEM INFO----` separator comes first);
- line 3: `fps,frametime,cpu_load,cpu_power,gpu_load,cpu_temp,gpu_temp,
  gpu_core_clock,gpu_mem_clock,gpu_vram_used,gpu_power,ram_used,
  swap_used,process_rss,cpu_mhz,elapsed`;
- one row per frame after that.

It also writes `<same>_summary.csv` with `0.1% Min FPS`, `1% Min FPS` and
`97% Percentile FPS`. For visual comparison, MangoHud ships `mangoplot`
and offers upload to flightlessmango.com. FlightlessSomething is not
mentioned in the README (*unverified*).

Because the `cpuscheduler` field is logged, each CSV records the governor
or scheduler state, which works as a cross-check that the variant really
applied.

### Toggling each change per run

| Variant          | Toggle (no rebuild)                                           |
| ---------------- | ------------------------------------------------------------- |
| `base`           | nothing (current config)                                      |
| `gamemode`       | prefix `gamemoderun`                                          |
| `ppd-perf`       | `powerprofilesctl set performance`, restore after             |
| `ccd0`           | prefix `taskset -c 0-7,16-23`                                 |
| `scx-bpfland`    | `sudo scx_bpfland &` for the run (unloads on exit)            |
| `scx-lavd`       | `sudo scx_lavd &`                                             |
| `scx-no-s76`     | stop `system76-scheduler`, run `scx_bpfland`                  |
| `x11`            | env `PROTON_ENABLE_WAYLAND=0`                                 |
| `nggc`           | env `RADV_PERFTEST=nggc`                                      |
| `gpu-3dfs`       | sysfs perf level `manual`, profile `1`; restore `auto`        |
| `gamescope`      | prefix `gamescope -f -w W -h H --`                            |
| `no-ntsync`      | env `PROTON_NO_NTSYNC=1` (measures ntsync's own effect)       |

Env vars and prefixes cannot be passed through `steam -applaunch`,
because the running Steam client starts the game, not the caller. So the
game's launch options are set **once** to `bench-wrap %command%`. The
wrapper reads a per-run file in `$XDG_RUNTIME_DIR`. Without that file it
just runs `%command%`, so normal play is unaffected.

Changes that need a rebuild (the `gamemode` group, `services.scx`
permanently) can be tested afterwards with `nixos-rebuild test`. This
activates without adding a boot entry. Use the same script.

### Confounders

- **Shader cache:** do one discarded warm-up run per game, and after any
  Mesa/Proton update. Do not clear `steamapps/shadercache` between runs.
- **Order effects / thermals:** interleave variants (round-robin, not all
  runs of A then B), sleep 60 s between runs, and log `gpu_temp`/`cpu_temp`.
- **Repeats:** N ≥ 5 per variant. Report the median of each run's average FPS
  and 1% low, plus the spread (min–max). Treat differences smaller than the
  spread as noise.
- **Background load:** close the browser and Emacs builds, and stop
  `attic` push jobs.
- **Fixed settings:** same resolution, preset and upscaler for every
  variant. Turn VRR and frame caps off for the benchmark, so the FPS is
  uncapped.

### Proposed script (not added to the repo)

`bench-wrap` (installed into `environment.systemPackages` via
`writeShellScriptBin`, or kept in `~/.local/bin`):

```bash
#!/usr/bin/env bash
# Steam launch options: bench-wrap %command%
f="${XDG_RUNTIME_DIR}/bench-variant.env"
[ -r "$f" ] || exec "$@"
# shellcheck disable=SC1090
. "$f"   # sets BENCH_PREFIX (array-safe string) and exports env vars
export MANGOHUD=1
export MANGOHUD_CONFIG="no_display,autostart_log=${BENCH_DELAY:-20},log_duration=${BENCH_SECS:-60},log_interval=0,output_folder=${BENCH_OUT}"
eval "exec ${BENCH_PREFIX:-} \"\$@\""
```

`just/bench.just` (in the style of the existing `just/*.just` imports):

```just
# Benchmark gaming variants: just bench-game "base gamemode scx-bpfland" 5
bench-game variants="base gamemode ppd-perf ccd0 scx-bpfland x11 nggc" runs="5" appid="1091500" args="--launcher-skip --intro-skip -benchmark" secs="60":
    #!/usr/bin/env bash
    set -euo pipefail
    out="$HOME/bench/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$out"
    envf="$XDG_RUNTIME_DIR/bench-variant.env"
    trap 'rm -f "$envf"; sudo pkill -x "scx_.*" || true; powerprofilesctl set balanced' EXIT
    apply() {   # $1 = variant; writes env file, applies system state
      local p="" e=""
      case "$1" in
        gamemode)   p="gamemoderun" ;;
        ppd-perf)   powerprofilesctl set performance ;;
        ccd0)       p="taskset -c 0-7,16-23" ;;
        scx-*)      sudo "scx_${1#scx-}" >/dev/null 2>&1 & sleep 3 ;;
        x11)        e="export PROTON_ENABLE_WAYLAND=0" ;;
        nggc)       e="export RADV_PERFTEST=nggc" ;;
        no-ntsync)  e="export PROTON_NO_NTSYNC=1" ;;
        gpu-3dfs)   d=/sys/class/drm/card1/device
                    echo manual | sudo tee $d/power_dpm_force_performance_level
                    echo 1 | sudo tee $d/pp_power_profile_mode ;;
      esac
      mkdir -p "$out/$1"
      printf 'BENCH_PREFIX=%q\nBENCH_OUT=%q\nBENCH_SECS=%s\n%s\n' \
        "$p" "$out/$1" "{{secs}}" "$e" > "$envf"
    }
    reset() {
      sudo pkill -x "scx_.*" || true
      powerprofilesctl set balanced
      echo auto | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level >/dev/null
    }
    run_once() {
      steam -applaunch {{appid}} {{args}}
      sleep 15
      # wait for the game to exit, max secs+180 s, then kill it
      timeout $(( {{secs}} + 180 )) bash -c \
        'while pgrep -f "steamapps/common" >/dev/null; do sleep 2; done' \
        || pkill -f "steamapps/common/.*\.exe" || true
      sleep 60   # cool down
    }
    apply base; run_once; rm -rf "$out/base"   # warm-up, discarded
    for i in $(seq {{runs}}); do
      for v in {{variants}}; do
        reset; apply "$v"; run_once
      done
    done
    python3 -I {{justfile_directory()}}/just/bench-summary.py "$out"
```

`just/bench-summary.py`:

```python
import csv, statistics as st, sys
from pathlib import Path

root = Path(sys.argv[1])
print(f"{'variant':<14}{'runs':>5}{'avg fps':>10}{'1% low':>10}{'p99 ms':>9}{'spread':>9}")
for vdir in sorted(p for p in root.iterdir() if p.is_dir()):
    avgs, lows, p99s = [], [], []
    for f in sorted(vdir.glob("*.csv")):
        if f.name.endswith("_summary.csv"):
            continue
        lines = f.read_text().splitlines()
        hdr = next(i for i, l in enumerate(lines) if l.startswith("fps,frametime"))
        ft = [float(r["frametime"]) for r in csv.DictReader(lines[hdr:])
              if r["frametime"]]
        if len(ft) < 100:
            continue
        ft.sort()
        p99 = ft[int(len(ft) * 0.99) - 1]           # ms
        avgs.append(1000 * len(ft) / sum(ft))       # time-weighted avg fps
        lows.append(1000 / p99)                     # 1% low as fps
        p99s.append(p99)
    if avgs:
        print(f"{vdir.name:<14}{len(avgs):>5}{st.median(avgs):>10.1f}"
              f"{st.median(lows):>10.1f}{st.median(p99s):>9.2f}"
              f"{max(avgs) - min(avgs):>9.1f}")
```

Notes on the script:

- The `sudo` steps (scx, amdgpu sysfs) prompt for a password at the start
  of each run. Run it from a terminal, not from Steam. In the agent
  sandbox it cannot run at all, because the sandbox has no access to the
  Steam session.
- The 1% low here is the FPS at the 99th-percentile frametime. MangoHud's
  own `_summary.csv` uses its own definition. Report one method
  consistently.
- If the Cyberpunk `summary.json` exists, it can be added as a second
  column (`jq .Data.averageFps`). *Unverified*: the key names beyond
  `averageFps`.

## Open questions

- Does `steam -applaunch 1091500 --launcher-skip --intro-skip -benchmark`
  start the benchmark directly and exit afterwards? Test it once by hand.
- Is VRR enabled in COSMIC for both outputs, and which output does
  Cyberpunk use?
- Do system76-scheduler and a sched_ext scheduler work together, or
  should system76-scheduler be turned off when `services.scx` is on?
- Which games are CPU-bound on this machine? GameMode, CCD pinning and
  scx only matter there. GPU-bound titles at 4K will show nothing.
- Is a LACT undervolt or power-limit change worth the stability risk?
  Synthetic runs (Superposition) would need a separate soak test.
