# Why Zen beats stock on `desktop`, and what Nobara ships

Research report. Questions: what in the Zen kernel explains its 13% better
1% low in the CPU-limited Cyberpunk 2077 run, can the stock kernel get
the same result without Zen, and which of Nobara's gaming tweaks apply
to this machine?

Verified on 2026-10-30 against these sources:

- The two kernel configs nixpkgs builds for `desktop` (nixpkgs
  `02c087f3fe67`):
  `linuxPackages_zen` →
  `/nix/store/qlipbah2kcvp5irim0gicdpmxci4qn08-linux-config-7.2.11`,
  `linuxKernel.packages.linux_7_2` →
  `/nix/store/dpbymfv9zkjz3p015jww1647dhv4qq48-linux-config-7.2.11`.
  The running Zen kernel's `/proc/config.gz` matches the first one.
- The Zen patch set: GitHub compare from `Linux 7.2.11`
  ([a2de78ee6ed8](https://github.com/zen-kernel/zen-kernel/commit/a2de78ee6ed8))
  to tag
  [`v7.2.11-zen1`](https://github.com/zen-kernel/zen-kernel/tree/v7.2.11-zen1).
- Mainline `v7.2` source (`torvalds/linux`).
- Nobara: `Nobara-Project/rpm-sources` branch `44`, and the CachyOS
  sources its kernel spec pulls in.
- Live system state and the game-bench sessions in
  `~/.local/share/game-bench/`.

Nothing in the repo was changed except this file.

## TL;DR

1. **The most likely cause is not the scheduler, it is ntsync.** The Zen
   build has `CONFIG_NTSYNC=y`, so `/dev/ntsync` always exists. The stock
   build has `CONFIG_NTSYNC=m`. The module cannot autoload, and nothing on
   `desktop` loads it. On the stock boot, GE-Proton therefore falls back
   from ntsync to fsync. That only matters for Wine games, which fits the
   data: there was no difference in Factorio (native) or in the GPU-bound
   4K run. Confidence: **medium-high** that this explains most of the
   gap. It is cheap to test: `modprobe ntsync` on the stock boot.
2. **The `zen-knobs` variant did not reproduce Zen.** It wrote
   `base_slice_ns=400000`, but Zen's effective value is **1600000**. The
   kernel scales the 0.4 ms base by `1 + ilog2(min(ncpus, 8)) = 4`, and
   the harness's own `state.json` records 1600000 on Zen and 2800000 on
   stock. The test ran with a slice 4× shorter than Zen's. The scheduler
   is not ruled out yet.
3. **No other Zen change differs in a way that matters.** Both builds
   have `HZ=1000`, `NO_HZ_FULL`, `PREEMPT_DYNAMIC`, `SCHED_MC`,
   `SCHED_CLUSTER`, `SCHED_CACHE`, the same amd-pstate (mode 3 =
   active), and the same EPP. Zen has no amd-pstate, load-balancing,
   LLC or cluster patches. What is left: the always-inline context-switch
   path, `RCU_BOOST`, and a compile-time migrate-batch constant. All are
   small.
4. **Mainline 7.2 already has a software "pin to one CCD".** Cache-aware
   scheduling (`CONFIG_SCHED_CACHE=y`, on by default) groups a process's
   threads into one LLC, but only while its average running-thread count
   fits the LLC. Raising
   `/sys/kernel/debug/sched/llc_balancing/aggr_tolerance` is the runtime
   way to get the `ccd0` effect without `taskset`.
5. **Nobara today means a CachyOS kernel** (BORE, `-O3`, `NTSYNC=y`) plus
   a few sysctl and udev files. On this machine the only parts that apply
   and are not already in place are ntsync on stock and, possibly,
   throttling the Steam client's bus locks.

## 1. What Zen 7.2.11-zen1 changes

### Built config: Zen versus stock (nixpkgs)

The two configs differ in only 43 lines. Every difference that touches
scheduling, timers, preemption or cpufreq is listed below:

| Option                        | Zen         | Stock       | Runtime-switchable?    |
| ----------------------------- | ----------- | ----------- | ---------------------- |
| `PREEMPT` / `PREEMPT_LAZY`    | `y` / unset | unset / `y` | yes, `preempt=`        |
| `ZEN_INTERACTIVE`             | `y`         | absent      | partly, see below      |
| `NTSYNC`                      | `y`         | `m`         | yes, `modprobe ntsync` |
| `RCU_BOOST` (+`RCU_EXPERT`)   | `y`, 500 ms | unset       | no                     |
| `IOSCHED_BFQ`                 | `y`         | `m`         | yes                    |
| `COMPACT_UNEVICTABLE_DEFAULT` | 0           | 1           | yes, sysctl            |
| `DEFAULT_NET_SCH`             | `fq_codel`  | default     | yes, sysctl            |
| `X86_64_VERSION`              | 1 (generic) | absent      | n/a                    |

Identical in both: `HZ_1000`, `NO_HZ_FULL`, `PREEMPT_DYNAMIC`,
`PREEMPT_RCU`, `RCU_LAZY`, `SCHED_SMT/MC/CLUSTER`, `SCHED_MC_PRIO`,
`SCHED_CACHE`, `SCHED_CLASS_EXT`, `SCHED_AUTOGROUP`, `NUMA_BALANCING`,
`X86_AMD_PSTATE=y`, `X86_AMD_PSTATE_DEFAULT_MODE=3`,
`CPU_FREQ_DEFAULT_GOV_SCHEDUTIL`, `CC_OPTIMIZE_FOR_PERFORMANCE`
(`-O2`, `-O3` is off), `TRANSPARENT_HUGEPAGE_MADVISE`, `LRU_GEN`.

The nixpkgs sources for these differences:

- `zen-kernels.nix` sets `ZEN_INTERACTIVE`, `PREEMPT = yes`,
  `PREEMPT_LAZY = no`, the RCU block, `IOSCHED_BFQ = yes`, `NTSYNC = yes`
  and `HZ_1000`
  ([L38–82](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/os-specific/linux/kernel/zen-kernels.nix#L38-L82)).
- `common-config.nix` gives every kernel `PREEMPT = no` and
  `PREEMPT_LAZY = yes` from 6.18
  ([L1469–1473](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/os-specific/linux/kernel/common-config.nix#L1469-L1473))
  and `IOSCHED_BFQ = module`
  ([L270](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/os-specific/linux/kernel/common-config.nix#L270)).
  It does not mention `NTSYNC`, so stock keeps the upstream default `m`.

Live on the Zen boot: `amd_pstate/status` = `active`, `prefcore` =
`enabled`, `scaling_driver` = `amd-pstate-epp`, governor `powersave`,
EPP `balance_performance`. The harness recorded the same governor and EPP
on the stock boot (`state.json`). amd-pstate is not a difference.

### The Zen patch set

The compare contains 911 commits, mostly Project C (PDS/BMQ). Project C
is compiled out here (`# CONFIG_SCHED_ALT is not set`), so it changes
nothing in the running kernel. The Zen commits that do take effect:

| Commit                         | Change                    |
| ------------------------------ | ------------------------- |
| [90bc67c2e07c][z-90bc67c2e07c] | Base config item          |
| [28014767dba9][z-28014767dba9] | Tune EEVDF                |
| [394833407005][z-394833407005] | Inline finish_task_switch |
| [548c3c159818][z-548c3c159818] | Kyber for MQ devices      |
| [793c7ea23829][z-793c7ea23829] | BFQ for SQ devices        |
| [cbdf3e9ef622][z-cbdf3e9ef622] | THP background reclaim    |
| [79d00fb04ebe][z-79d00fb04ebe] | No unevictable compaction |
| [f8197953b0e7][z-f8197953b0e7] | No swap-in readahead      |
| [299e73098bef][z-299e73098bef] | split_lock_mitigate=0     |
| [277b51bc972b][z-277b51bc972b] | Tune ondemand             |
| [6030c5c5983f][z-6030c5c5983f] | max_map_count INT_MAX-5   |
| [6bedec045374][z-6bedec045374] | schedutil not forced      |
| [f6ac9623fc5d][z-f6ac9623fc5d] | No AVX2 in kernel         |

[z-90bc67c2e07c]: https://github.com/zen-kernel/zen-kernel/commit/90bc67c2e07c
[z-28014767dba9]: https://github.com/zen-kernel/zen-kernel/commit/28014767dba9
[z-394833407005]: https://github.com/zen-kernel/zen-kernel/commit/394833407005
[z-548c3c159818]: https://github.com/zen-kernel/zen-kernel/commit/548c3c159818
[z-793c7ea23829]: https://github.com/zen-kernel/zen-kernel/commit/793c7ea23829
[z-cbdf3e9ef622]: https://github.com/zen-kernel/zen-kernel/commit/cbdf3e9ef622
[z-79d00fb04ebe]: https://github.com/zen-kernel/zen-kernel/commit/79d00fb04ebe
[z-f8197953b0e7]: https://github.com/zen-kernel/zen-kernel/commit/f8197953b0e7
[z-299e73098bef]: https://github.com/zen-kernel/zen-kernel/commit/299e73098bef
[z-277b51bc972b]: https://github.com/zen-kernel/zen-kernel/commit/277b51bc972b
[z-6030c5c5983f]: https://github.com/zen-kernel/zen-kernel/commit/6030c5c5983f
[z-6bedec045374]: https://github.com/zen-kernel/zen-kernel/commit/6bedec045374
[z-f6ac9623fc5d]: https://github.com/zen-kernel/zen-kernel/commit/f6ac9623fc5d

What each one does, and whether it can affect this benchmark:

- **Base config item** (`90bc67c2e07c`): adds `CONFIG_ZEN_INTERACTIVE`.
- **Tune EEVDF** (`28014767dba9`), `kernel/sched/fair.c` and `sched.h`:
  - Normalized `base_slice` 0.7 → 0.4 ms. The effective value is
    1.6 ms on 32 CPUs (stock: 2.8 ms).
  - `migration_cost` 0.5 → 0.3 ms. This value is used by `task_hot()`
    and also gates newidle balance (`avg_idle < migration_cost`,
    [fair.c L14312](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/fair.c#L14312)).
    A lower value means idle cores pull work sooner.
  - `cfs_bandwidth_slice` 5 → 3 ms. This only matters with CPU quotas.
  - `SCHED_NR_MIGRATE_BREAK` 32 → 8, the batch size of a load-balance
    pass. It is a compile-time constant
    ([sched.h L3104](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/sched.h#L3104)).
    Its debugfs counterpart `nr_migrate` caps the loop, so `nr_migrate=8`
    gives the same result.

  The commit message gives the goal: "behave more like out-of-tree
  schedulers that aggressively use idle cores to reduce latency". This
  is the only Zen patch that touches task placement or load balancing.
  **Plausible, and not properly tested yet** (see §2).
- **Always-inline `finish_task_switch()`** (`394833407005`): makes every
  context switch cheaper. The commit measures −9 to −11% of that
  function's time without Spectre v2 user mitigations and up to −45%
  with them. `desktop` has `spectre_v2`: "Enhanced / Automatic IBRS;
  IBPB: conditional; STIBP: always-on". This helps Wine-heavy workloads a
  little. It is not runtime-switchable. **Small.**
- **Kyber for multi-queue devices and BFQ for single-queue devices**
  (`548c3c159818`, `793c7ea23829`): the NVMe drive uses `kyber`. This is
  not relevant to a benchmark that runs from page cache.
- **THP defrag `defer+madvise`** (`cbdf3e9ef622`), **no unevictable
  compaction** (`79d00fb04ebe`), **`page-cluster=0`** (`f8197953b0e7`):
  memory-reclaim latency. All three are runtime sysctls or sysfs knobs.
  Swap was unused, so this is not relevant to this benchmark.
- **`split_lock_mitigate=0`** (`299e73098bef`): **no effect on AMD.**
  `sysctl_sld_mitigate` is only read in `split_lock_warn()`, the Intel
  `#AC` path. AMD Zen 5 has only `bus_lock_detect`, and its `#DB`
  handler `handle_bus_lock()` never reads the sysctl
  ([bus_lock.c](https://github.com/zen-kernel/zen-kernel/blob/v7.2.11-zen1/arch/x86/kernel/cpu/bus_lock.c)).
- **ondemand tuning** (`277b51bc972b`): not used here (amd-pstate-epp).
- **`max_map_count`** (`6030c5c5983f`): NixOS already sets 1048576.
- **schedutil not forced** (`6bedec045374`): Kconfig only.
- **No AVX2/vectorization in the kernel** (`f6ac9623fc5d`): build flags.

There are no Zen patches to amd-pstate, preferred-core ranking,
`topology.c` domain flags (except under `SCHED_ALT`), cluster or NUMA
scheduling, or HZ. The other branches merged into 7.2/main are BBRv3
(TCP), the dmem cgroup and TTM VRAM-eviction series (only matters when
VRAM is full), and zram/zswap. None of them affects a CPU-limited 720p
run.

### ntsync: the difference nobody configured

- Upstream `ntsync.c` registers the device with `module_misc_device()`
  and `.mode = 0666`, but has no `devname:` module alias
  ([ntsync.c L1201–1208](https://github.com/torvalds/linux/blob/v7.2/drivers/misc/ntsync.c#L1201-L1208)).
  The stock kernel's `modules.devname`
  (`/nix/store/…-linux-7.2.11-modules/lib/modules/7.2.11/`) has no
  ntsync entry, so opening `/dev/ntsync` cannot trigger an autoload.
- The `stock` specialisation's `etc/modules-load.d/nixos.conf` lists
  `atkbd br_netfilter bridge ctr i2c-dev kvm-amd loop tun uinput veth
  xt_nat`, without ntsync. No NixOS module mentions ntsync: there is no
  option for it on search.nixos.org, and `nixos/modules` at `02c087f`
  has no match.
- GE-Proton 10-10 and later: "ntsync now enabled by default, will be used
  if kernel supports it"
  ([release notes](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton10-10)).
  The benchmarks used GE-Proton (`compatTool` in `session.json`).

Unless `ntsync` was loaded by hand on the stock boot, the Zen sessions
used ntsync and the stock sessions used fsync. That fits the result
pattern:

- Factorio (native, no Wine): identical.
- 4K GPU-bound: identical.
- 720p CPU-bound Wine: Zen +13% p1, +17% average.
- CCD0 pinning helps stock (+9%) but not Zen. Wine sync objects
  implemented as shared-memory futexes are likely to cost more when
  waiter and waker sit on different CCDs. ntsync does the wait and wake
  in the kernel, so there is less left to gain. This mechanism is
  *unverified*.

## 2. Getting the gain on stock

Ranked by likelihood. Each is a variant the harness can run on the stock
boot (`bootedSystem` ends in `-stock-`):

1. **`ntsync`**: `modprobe ntsync` before the run (and `rmmod ntsync`
   after it, when no Wine process still holds it). Check that it was
   used: `ls -l /proc/$(pgrep -f Cyberpunk2077.exe)/fd | grep ntsync`.
   Permanent fix: `boot.kernelModules = [ "ntsync" ];` (option verified
   on search.nixos.org).
2. **`zen-knobs-fixed`**: the current `zen-knobs` with
   `base_slice_ns=1600000` instead of 400000, so it matches what Zen
   actually runs. The scaling is `factor = 1 + ilog2(min(cpus, 8))`
   ([fair.c L192–221](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/fair.c#L192-L221)).
   Keep `preempt=full`, `migration_cost_ns=300000` and `nr_migrate=8`.
   Run it together with `ntsync`, because the two effects may overlap.
3. **`llc-aggr`**: cache-aware scheduling, which is mainline and the same
   on both kernels. A process counts as too big for one LLC when
   `nr_running_avg × SMT(2) > aggr_tolerance × llc_size(16)`
   ([fair.c L1482–1500](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/fair.c#L1482-L1500)).
   With the default `aggr_tolerance = 1`
   ([L1407](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/fair.c#L1407)),
   more than about 8 running threads disables grouping. The footprint
   check only applies when NUMA balancing is active, which a single-node
   desktop does not use
   ([L1434–1478](https://github.com/torvalds/linux/blob/v7.2/kernel/sched/fair.c#L1434-L1478)).
   The variant sets
   `/sys/kernel/debug/sched/llc_balancing/aggr_tolerance = 100` ("ignore
   … and do the aggregation anyway"). Check `llc_balancing/enabled = 1`
   first. Expected effect: close to `ccd0`, without `taskset`, and
   possibly on CCD1.
4. **`bus-lock-off`**: boot parameter `split_lock_detect=off`. Every boot
   logs thousands of `#DB: CHTTPClientThre/… took a bus_lock trap`
   messages from the Steam client (19,051 logged on the stock boot of
   10-28, after rate limiting). Each one is a debug trap, and a bus lock
   stalls memory traffic on other cores too (see §3, Nobara's patch).
   This affects both kernels equally, so it does not explain the gap,
   but it may lift both. It needs a reboot, so test it as a
   specialisation.
5. **`zen-mm`**: `vm.compact_unevictable_allowed=0`, `vm.page-cluster=0`,
   THP `defrag=defer+madvise`. Expected effect: none at 0 swap. Only
   run it if 1–3 leave a gap.

Not candidates:

- amd-pstate mode, EPP and preferred core: identical on both kernels
  already.
- `HZ`: compile-time and identical.
- `split_lock_mitigate`: no effect on AMD, see above.
- RCU boost and inlining: need a rebuild. If 1–3 close the gap, they
  were not the cause.

## 3. Nobara

### Kernel

Nobara 44's kernel spec (`baseos/kernel/mainline/7.2/kernel.spec`)
describes itself as "A port of linux-cachyos … for the Fedora operating
system".
[Source0](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/kernel/mainline/7.2/kernel.spec)
is the `CachyOS/linux` tag `cachyos-7.2.11-1`, with the CachyOS config.
It adds these patches:

- `0001-bore-cachy.patch` (BORE, a burst-aware tweak of EEVDF weights
  and slices, by Masahito Suzuki), `0001-handheld.patch`, and Nobara
  hardware patches: Surface, ROG Ally, Logitech wheel, gamescope
  framerate control, USB poll rate, xpadneo, AMD vfio, ASUS keyboard,
  GFX10 resume, I226-V.
- Config overrides
  ([config.generic](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/kernel/mainline/7.2/config.generic)):
  `CONFIG_CACHY=y`, `CONFIG_SCHED_BORE=y`, `HZ_1000`, `NO_HZ_FULL`,
  `PREEMPT_LAZY` + `PREEMPT_DYNAMIC`, `CC_OPTIMIZE_FOR_PERFORMANCE_O3`,
  `SCHED_CLASS_EXT`
  ([config.x86_64](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/kernel/mainline/7.2/config.x86_64)
  adds `NTSYNC=y`).
- CachyOS's `CONFIG_CACHY` sets the same kind of EEVDF defaults as Zen:
  `base_slice` 0.4 ms normalized and `migration_cost` 0.4 ms
  ([fair.c L81–93](https://github.com/CachyOS/linux/blob/cachyos-7.2.11-1/kernel/sched/fair.c#L81-L93)).
- The 7.1 kernel also carried
  [`x86-bus-lock-default-ratelimit.patch`](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/kernel/mainline/7.1/x86-bus-lock-default-ratelimit.patch).
  It sets the default to `split_lock_detect=ratelimit:100` on CPUs with
  bus-lock detection, because Steam's `libtier0_s.so` caused "complete
  system hangs". It is no longer in the 7.2 directory.

### System tweaks (`nobara-login` / `nobara-login-sysctl`)

From
[`nobara-login.spec`](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/nobara-login.spec)
and its sources:

| Tweak                                  | Relevant here | Status on `desktop`         |
| -------------------------------------- | ------------- | --------------------------- |
| `kernel.split_lock_mitigate = 0`       | no (AMD #DB)  | Zen sets 0 already          |
| `vm.max_map_count = 16777216`          | marginal      | NixOS: 1048576              |
| NVMe `none`, SSD `mq-deadline` (udev)  | no (cached)   | Zen: kyber                  |
| `99-ntsync.rules`: `MODE="0644"`       | no            | upstream 0666 already       |
| PipeWire wine `min.quantum 1024/48000` | audio only    | not set                     |
| `20-uplay-mtu-probing.conf`            | Ubisoft only  | not set                     |
| hpet/rtc group `audio`, powercap rules | no            | not set                     |

Files:
[20-disable-split-lock-detect.conf](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/20-disable-split-lock-detect.conf),
[20-starcitizen-max_map_count.conf](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/20-starcitizen-max_map_count.conf),
[60-ioschedulers.rules](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/60-ioschedulers.rules),
[99-ntsync.rules](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/99-ntsync.rules),
[wine_gaming.conf](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/nobara-login/wine_gaming.conf).

On NixOS these would go in `boot.kernel.sysctl."<key>"` and
`services.udev.extraRules`.

### Other packages

- **falcond** (from PikaOS, packaged in `baseos/falcond`): a GameMode
  alternative. Per profile it can switch the scx scheduler, the V-Cache
  mode, performance mode, `split_lock_mitigate`, and set `dmem.low`
  protection
  ([README](https://github.com/PikaOS-Linux/falcond)). On this machine:
  the CPU has no V-Cache, scx tested worse, and split lock has no
  effect, so it adds nothing over GameMode. It is not in nixpkgs.
- **scx-scheds 1.1.0**: the same schedulers as nixpkgs scx 1.1.4, which
  were already tested.
- **Mesa 26.2.6** with
  [`valve.patch`](https://github.com/Nobara-Project/rpm-sources/blob/44/baseos/mesa/valve.patch)
  (SteamOS: FH5 swapchain image count, gamescope frame limiter).
  `desktop` has 26.2.5. Not relevant to RADV performance here.
- **dmemcg-booster / kcgroups-dmemcg**: user-space for the dmem cgroup
  VRAM protection that Zen's `7.2/dmem-ttm-v8` branch also carries. It
  only matters when VRAM is overcommitted (20 GB card, 720p low: no).
- Also packaged: gamescope, LACT, MangoHud, umu-launcher. `desktop`
  already uses gamescope and MangoHud.

Nothing Nobara-specific on the Proton side applies: Nobara ships
GE-Proton through ProtonPlus, the same build `desktop` uses.

## Candidates to benchmark next

| Variant           | Sets (stock boot unless noted)         | Source             |
| ----------------- | -------------------------------------- | ------------------ |
| `ntsync`          | `modprobe ntsync`                      | GE-Proton 10-10    |
| `ntsync+knobs`    | `ntsync` + `zen-knobs-fixed`           | Zen `28014767dba9` |
| `zen-knobs-fixed` | `zen-knobs`, `base_slice_ns=1600000`   | fair.c L192        |
| `llc-aggr`        | `llc_balancing/aggr_tolerance=100`     | fair.c L1482       |
| `bus-lock-off`    | `split_lock_detect=off` (both kernels) | bus_lock.c         |

Expected effects:

- `ntsync`: closes most of the Zen gap in the 720p Wine run. If it does,
  the fix is `boot.kernelModules = [ "ntsync" ]`, and the stock kernel
  can stay the default.
- `ntsync+knobs` and `zen-knobs-fixed`: whatever gap remains after
  `ntsync` would come from the EEVDF tuning.
- `llc-aggr`: close to `ccd0`, on both kernels, without per-game
  `taskset`. Also run it on Zen.
- `bus-lock-off`: a small gain at most, the same on both kernels. Run it
  last.

To confirm ntsync was the cause, also run `ntsync` with `ccd0`. If
pinning no longer helps once ntsync is loaded, as on Zen, the mechanism
in §1 is supported.
