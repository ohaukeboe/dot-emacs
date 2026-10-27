# Research: Game Performance Tuning and Benchmarking

Phase 0 output for [plan.md](plan.md). Each entry gives the decision, the
rationale and the alternatives considered. Sources are cited inline. "P"
means the pinned nixpkgs tree (`nixpkgs_6`, rev `02c087f`). `[U]` marks a
claim not verified against a primary source; each one has a check in
[quickstart.md](quickstart.md).

Background research: `docs/gaming-performance-research.md` and the Zen
kernel report referenced in the spec.

## R1. Hardware facts that change the spec

- The card is a **Radeon RX 7900 XT** (Navi 31, `1002:744c` rev `0xcc`,
  Sapphire `1da2:471e`, `mem_info_vram_total` = 20 GiB). The XTX has 24 GiB.
  The spec was corrected.
- Live hwmon values (`card1`, `hwmon2`, label `PPT`, µW): `power1_cap`
  265000000, `power1_cap_default` 265000000, `power1_cap_min` 238000000,
  `power1_cap_max` 290000000. `power1_average` exists; `power1_input` does
  not. `ppfeaturemask` = `0xfff7bfff` (overdrive bit `0x4000` off).

## R2. GPU power limit

**Decision**: write `power1_cap` through hwmon, located by the hwmon `name`
`amdgpu`, never by a fixed `hwmonN`. Accept watts in
`[power1_cap_min, power1_cap_max]`, read at runtime. Restore by writing
`power1_cap_default`. Persist an adopted value with a root systemd oneshot
behind one option. Overdrive stays off.

**Rationale**:

- `smu_v13_0_0_set_power_limit` accepts any value up to the `MsgLimits`
  limit without overdrive; only values above it need `od_enabled`. With
  overdrive off, `power1_cap_max` = max(default, `MsgLimits`)
  ([smu_v13_0_0_ppt.c, v7.2](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/amd/pm/swsmu/smu13/smu_v13_0_0_ppt.c?h=v7.2)).
  So 238–290 W needs no kernel parameter.
- Writes are truncated to whole watts; out-of-range writes return `EINVAL`;
  writing `0` keeps the current limit rather than restoring the default
  ([amdgpu_pm.c, v7.2](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/amd/pm/amdgpu_pm.c?h=v7.2)).
  Hence the explicit write of `power1_cap_default` on restore.
- `smu_restore_dpm_user_profile` reapplies the user limit on resume, so a
  suspend during a session does not silently revert the variant.
- A reboot resets the cap to default, which covers the "crash during a
  session" edge case without extra code.

**Alternatives**:

- `services.lact`: declarative `gpus.<pci-id>.power_cap`, but it symlinks
  `/etc/lact/config.yaml` read-only and runs a daemon. Its CLI cannot set the
  cap at runtime, so the harness would need sysfs anyway
  ([lact.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/hardware/lact.nix),
  [LACT README](https://github.com/ilya-zlobintsev/LACT/blob/master/README.md)).
  Rejected as heavier with no gain.
- `hardware.amdgpu.overdrive.enable`: only needed above `power1_cap_max`,
  which FR-029 forbids. Rejected.
- Zen's `ignore_min_pcap`: only lowers the floor below 238 W. Out of scope.

`[U]`: whether the cap survives a GPU reset (not a resume); whether `PPT` is
GPU-only rather than total board power.

## R3. Recording GPU and frame data

**Decision**: MangoHud per-frame CSV logging for Proton workloads, with
`mangohud` added to `programs.steam.extraPackages` so it is inside Steam's
FHS environment. Configure by `MANGOHUD_CONFIG` only:
`no_display,autostart_log=<s>,log_duration=<s>,log_interval=0,output_folder=<dir>`.

**Rationale**: the per-frame CSV has `fps,frametime,...,gpu_core_clock,
gpu_mem_clock,...,gpu_power,...,elapsed` columns, and MangoHud reads amdgpu
`gpu_metrics` (`average_socket_power`, `current_gfxclk`,
`temperature_edge`), which covers FR-027 without a second sampler
([README](https://github.com/flightlessmango/MangoHud/blob/master/README.md),
`src/logging.cpp`, `src/amdgpu.cpp`). `extraPackages` feeds the FHS env's
target packages (P `nixos/modules/programs/steam.nix:91`).

**Alternatives**: `environment.systemPackages` only (`[U]` whether
pressure-vessel sees it); a separate sysfs sampler (duplicate of what
MangoHud already logs). Factorio does not render under `--benchmark`, so
its GPU columns are irrelevant; R6 covers its timing.

The Zen report warns that MangoHud logging can itself cause hitches. Every
variant, including the baseline, is logged the same way.

**Revised after the first desktop run (2026-10-27)**: MangoHud loaded in
Cyberpunk but wrote no CSV, cause unknown. Cyberpunk writes its own
per-frame `frames.csv` beside `summary.json`, covering exactly the
benchmark pass (2056 frames, average matching `averageFps`). That log is
now preferred, and MangoHud is the fallback for a game without one. GPU
power comes from `game-bench` sampling hwmon `power1_average` once a
second, limited to the benchmark pass, so it no longer depends on
MangoHud.

## R4. Workload: Cyberpunk 2077, unattended

**Decision**: follow the Phoronix test profile
([pts/cyberpunk2077-1.0.1 install.sh](https://github.com/phoronix-test-suite/test-profiles/tree/master/pts/cyberpunk2077-1.0.1)):

- launch `steam -applaunch 1091500 --launcher-skip -benchmark
  -skipStartScreen`;
- for the 720p workload, back up the prefix's
  `.../AppData/Local/CD Projekt Red/Cyberpunk 2077/UserSettings.json`,
  install a prepared copy, and restore the original in the session's
  restore journal;
- results also land in `.../Documents/CD Projekt Red/Cyberpunk 2077/
  benchmarkResults/*/summary.json` (`averageFps`, `minFps`, `maxFps`),
  recorded alongside MangoHud as a cross-check. Its sibling `frames.csv`
  became the primary frame log; see the revision under R3.

**Rationale**: the only documented unattended recipe; PTS and the dolpa.me
manual agree on the result path.

`[U]`: that the game exits by itself after the run (PTS waits on
`pgrep -x GameThread`; the harness also has a hard timeout, FR-007); the
UserSettings keys for upscaling and frame generation. The prepared 720p file
is therefore exported from the game by the user once (quickstart step), not
written by hand.

**Probed 2026-10-27 (quickstart step 6)**: the game exits by itself after
the pass. Steam starts a short-lived setup reaper before the game's own,
so the harness treats the game as gone only after 20 s without a reaper.
Under Proton's Wayland driver, fullscreen renders at the monitor's
resolution whatever `UserSettings.json` says; the 720p file must use
Windowed mode (then `renderWidth` 1280, about 204 fps, 100 W).

**Alternatives**: menu-driven start (breaks SC-001).

## R5. Launching and detecting Steam games

**Decision**: `steam -applaunch <appid> <args>` forwards to the running
client. A run is "in progress" while a process whose command line contains
`reaper` and exactly `SteamLaunch AppId=<appid>` exists. Hard timeout per
run, then kill the reaper's process group.

**Rationale**: Steam's `reaper` lives for the game's whole lifetime; Lutris
uses the same test
([lutris steam.py](https://github.com/lutris/lutris/blob/master/lutris/runners/steam.py)).
`[U]`: no Valve doc for `-applaunch` forwarding (pages returned 403); PTS
and Lutris both rely on it.

**Per-run settings reach the game** only through its launch options, since
the Steam client, not the caller, starts the game. Each benchmarked game's
launch options are set once to `game-bench-wrap %command%` (contract:
[contracts/game-bench-wrap.md](contracts/game-bench-wrap.md)).

## R6. Workload: Factorio

**Decision**: run the Steam-installed native binary
(`~/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio`) through
`steam-run`, without the Steam client:

```text
factorio --mod-directory <empty dir> --disable-audio \
  --benchmark <save> --benchmark-ticks <N> --benchmark-runs 1 \
  --benchmark-verbose all --benchmark-sanitize
```

The save is a fixed-output `fetchurl` of the factoriobench.com "flame_Sla
10k" map, pinned by its SHA-256 (the hash is also the file name):
`https://assets.factoriobench.com/maps/4c5f65003d84370f16d6950f639be1d6f92984f24c0240de6335d3e161705504.zip`.

**Rationale**:

- Flags from the [wiki](https://wiki.factorio.com/Command_line_parameters).
  `--benchmark` does no rendering, so the result is pure simulation time.
  The summary line is `Performed N updates in T ms avg: … min: … max: …`
  ([forum](https://forums.factorio.com/viewtopic.php?t=103895)), and
  `--benchmark-verbose all` prints per-tick nanosecond timings, which give
  the p99 and p99.9 tick times FR-008a needs.
- The empty mod directory keeps the user's mods out of the measurement, as
  the community script does
  ([benchmark.sh](https://factoriobench.com/scripts/benchmark.sh)).
- `fetchurl` with a hash satisfies Principle II and keeps the save out of
  the repository.
- nixpkgs' `factorio` needs account credentials to build; the Steam copy is
  already installed. Rejected.

`[U]`: the per-tick CSV header names (the parser reads the header from the
first real run; the quickstart captures one as a test fixture); whether the
binary starts with no display and without the Steam client; how a 1.0 save
migrates in 2.0 (results are only compared within this harness, so
cross-version comparability does not matter). Fallback map: Klonan's 2.0
10k SPM map from the same site.

**Probed 2026-10-27**: the header is `tick,timestamp,wholeUpdate,...` with
rows `t0,...`; `wholeUpdate` is in ns and matches Factorio's own average.
The binary runs under `steam-run` with no display. Two catches: steam-run
gives the game a private `/tmp`, and Factorio loads every zip in
`--mod-directory` as a mod, so the save sits outside it.

## R7. GameMode for every Steam game

**Outcome (deploy, 2026-10-27)**: the global preload broke Steam. The client
logged `gamemodeauto:` then `dbus_pending_call_block() ... assertion
"pending != NULL" failed`, and the web UI could not connect
(`WebUITransport: Connection rejected`, UI: "Unexpected Transport Error").
The blacklist cannot help: it filters registration in `gamemoded`, but the
library still runs inside every Steam process. Reverted to the fallback
below (per-game `gamemoderun`).

**Decision**: preload `libgamemodeauto.so.0` for the whole Steam
environment, together with the extest library the module already preloads,
and keep Steam's own processes from registering with a GameMode
`[filter] blacklist`. A game opts out with the launch option
`game-bench-nogamemode %command%`, which strips the library from
`LD_PRELOAD`. Verification is a quickstart step; if the blacklist cannot
keep GameMode inactive while Steam is idle, the fallback is per-game
`gamemoderun %command%` and FR-016 is reported as not met.

**Rationale**:

- The client library starts GameMode from a constructor and ends it from a
  destructor (gamemode `lib/gamemode_client.h:248,277`), so a global preload
  registers every process in the environment, including `steam`,
  `steamwebhelper` and `reaper`.
- `programs.steam.package`'s `apply` builds `extraEnv = compat //
  { LD_PRELOAD = <i686 extest>; } // prev.extraEnv` (P `steam.nix:57-67`),
  so a `LD_PRELOAD` in our override *replaces* extest. Our value must list
  extest too.
- `gamemoderun` puts both the 64-bit and 32-bit `gamemode-lib` paths on
  `LD_LIBRARY_PATH` and preloads by bare name (nixpkgs
  `preload-nix-workaround.patch`); the global preload reuses that scheme.
- GameMode's ini supports `[filter] blacklist=` by executable name (upstream
  `example/gamemode.ini:45-50`).

**Alternatives**: per-game `gamemoderun %command%` only (fails FR-016; kept
as the fallback); PPD `performance` profile while Steam runs (governor only,
no renice, and on for the whole Steam session).

`[U]`: whether Steam passes its environment's `LD_PRELOAD` on to games
(it appends its overlay library, so it is expected to); whether
pressure-vessel resolves a bare-name preload.

**Group**: add the user to `gamemode`. The module creates the group
(P `gamemode.nix:107`); `enableRenice` (default true) gives `gamemoded`
`cap_sys_nice`; upstream's polkit rule lets the group run `cpugovctl` and
`gpuclockctl` without a password. `renice` is set to `10`, `softrealtime`
`off`, `ioprio` `0`.

## R8. Kernel A/B

**Decision**:

- Add `specialisation.stock` on `desktop`, tagged `stock`, with the stock
  kernel of the **same series as Zen**, chosen at evaluation time as
  `pkgs.linuxKernel.packages."linux_<major>_<minor>"` from
  `linuxPackages_zen.kernel.version`. Evaluation throws if nixpkgs no longer
  has that series.
- The booted kernel is identified at runtime by `readlink
  /run/booted-system` (contains the tag) plus `uname -r`.
- Phase 2 swaps which entry is the default if Zen loses (FR-024).

**Rationale**:

- At the pin, `linuxPackages_zen` is 7.2.11 but `linuxPackages_latest` is
  7.3; `linuxPackages_7_2` is 7.2.11. The spec requires the same series.
  Deriving the attribute from Zen's version keeps the pair matched on every
  `nix flake update` instead of silently drifting.
- Every host uses lanzaboote (`lib/mkNixosConfiguration.nix:82`), which
  installs one UKI per specialisation, so it appears in the menu.
- `system.nixos.tags` flows into the toplevel name and the boot entry title
  (P `misc/label.nix:68`, `top-level.nix:60`, `bootspec.nix:29`).
- The menu is hidden (`boot.loader.timeout = 0`,
  `modules/silent-boot/default.nix:64`); hold Space at POST.
- `system.boot.loader.kernelFile = "bzImage"` in `common/system/system.nix`
  also holds for the stock kernel (laptop already boots `linuxPackages_latest`
  with it).

**Alternatives**: `linuxPackages_latest` (different series, rejected by the
spec); a hard-coded `linuxPackages_7_2` (drifts silently when Zen moves to
7.3).

## R9. Zen behaviours on the stock kernel

**Decision**: one variant, `zen-knobs`, applied at runtime through the root
helper, only on the stock kernel:

| Knob                          | Zen value       | Interface                               |
| ----------------------------- | --------------- | --------------------------------------- |
| preemption                    | `full`          | `/sys/kernel/debug/sched/preempt`       |
| EEVDF base slice              | 400000 ns       | `/sys/kernel/debug/sched/base_slice_ns` |
| migration cost                | 300000 ns       | `.../migration_cost_ns`                 |
| `nr_migrate`                  | 8               | `.../nr_migrate`                        |
| `vm.page-cluster`             | 0               | sysctl                                  |
| NVMe I/O scheduler            | `kyber`         | `/sys/block/nvme*/queue/scheduler`      |

**Rationale**: the stock 7.3 config has `PREEMPT_DYNAMIC=y` and
`PREEMPT_LAZY=y` (P `common-config.nix:1469-1473`), and v7.2
`kernel/sched/debug.c:645-655` creates the four debugfs files. Kyber is
built in on both kernels. `vm.page-cluster` is already 0 today, so it is
recorded but not toggled. The scheduler knobs only matter with no sched_ext
scheduler loaded, so `zen-knobs` is not combined with `scx-*` variants. The
1000 Hz tick needs a custom kernel build and is out of scope (spec).

`vm.max_map_count` stays at 1048576 (spec Assumption).

## R10. sched_ext

**Decision**: variants `scx-bpfland` and `scx-lavd` start the scheduler
from `pkgs.scx.full` (scx 1.1.4) as root for the run and stop it after.
Variants `scx-bpfland-no-s76` and `scx-lavd-no-s76` also stop
`system76-scheduler` for the run. Applied state is checked through
`/sys/kernel/sched_ext/state` = `enabled`; a run whose state is not
`enabled` at the end is excluded (spec edge case). Phase 2 adoption uses
`services.scx.{enable,scheduler}`.

**Rationale**:

- `services.scx` takes a `scheduler` enum from `package.schedulers`, an
  `extraArgs` list, and asserts kernel ≥ 6.12 (P
  `services/scheduling/scx.nix:24-97`). Both kernels have
  `SCHED_CLASS_EXT=y`.
- system76-scheduler does not touch sched_ext. On EEVDF kernels its CFS step
  returns NotSupported (no `latency_ns`), but it still renices processes,
  sets I/O priority and turns autogroup off
  (pop-os/system76-scheduler `daemon/src/cfs/paths.rs:34-48`,
  `data/config.kdl`). Its renicing can still interact with a BPF
  scheduler's own priorities, so the `-no-s76` variants stay.

`[U]`: that `/sys/kernel/sched_ext/root/ops` names the loaded scheduler
(state is used instead).

## R11. Privileged steps

**Decision**: one root helper, `game-bench-priv`, built with
`writeShellApplication`, with a fixed set of subcommands that validate
their arguments (contract:
[contracts/game-bench-priv.md](contracts/game-bench-priv.md)). A
`security.sudo.extraRules` entry lets `config.user.username` run exactly
that store path with `NOPASSWD`. The harness calls `sudo -n` and fails at
start-up if the rule is missing. This gives SC-001 its "at most one
prompt" (in practice none).

**Rationale**: a bare command path in the rule allows any arguments
(P `security/sudo.nix:164-171`), so argument validation lives in the
helper. User rules are ordered after the default wheel rule, so this one
wins (P `sudo.nix:229-250`). Every write target is fixed in the helper; no
argument is used as a path.

**Alternatives**: `sudo -v` plus a keepalive loop (prompts, and the
timestamp can lapse during long sessions); polkit actions (more files for
the same effect).

This is a security-relevant decision, so it gets an ADR (plan).

## R12. Background load and build timing

**Decision**: loop `nix build --rebuild --no-link
'<drvPath of the bare Emacs package>^out' --cores 0` while the session
runs, ignoring its exit status. FR-013 times the same command with
`--rebuild` N times. The derivation path is baked into the script at
evaluation time, so the load is pinned by `flake.lock`.

**Rationale**: `--rebuild` rebuilds an already-valid path and compares the
result; non-identical output yields a non-zero exit (`[U]` exact code),
which is irrelevant here. The repo's Emacs is `emacs-unstable-pgtk` from
emacs-overlay wrapped by `emacsWithPackagesFromUsePackage`
(`workstation/home.nix:65-67`); the bare package is rebuilt, not the
wrapper. `make-emacs` sets `enableParallelBuilding`.

`[U]`: Emacs's build time and how well it uses 32 threads. If a quickstart
probe shows poor parallelism, the fallback is the running kernel
derivation, already in the store.

## R13. Packaging and tests

**Decision**:

- Shell: `writeShellApplication` (shellcheck at build). Python summary and
  comparison: `pkgs.writers.writePython3Bin` (flake8 at build, P
  `build-support/writers/scripts.nix:1165-1218`), standard library only.
- Fast check `tests/game-bench.nix`, wired like the existing entries in
  `flake.nix` `checks`: runs the summary over fixture MangoHud and Factorio
  logs, the comparison over two fixture sessions with differing versions,
  and `game-bench-wrap` with and without a live session, and with a stale
  one.

**Rationale**: Principles I and III; matches `tests/rtk-banner.nix`.
