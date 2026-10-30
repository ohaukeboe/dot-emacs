# Gaming benchmarks on `desktop`

Decision record for `specs/008-game-performance-tuning` (FR-021, US6). Each
section holds the summary rows of the `game-bench` sessions, the software
versions they ran with, and the keep or drop verdict for each variant with
the rule that decided it. Raw logs stay in `~/.local/share/game-bench/`.

Rules (from the spec):

- **FR-018**: keep a tuning if its median 1% low gain is larger than the
  run-to-run spread of both it and the baseline, and neither the 0.1% low
  nor the average regresses beyond that spread.
- **FR-020**: a system-wide tuning must not slow `game-bench build-time`
  beyond its spread.
- **FR-024**: Zen stays the default kernel only if it beats stock's median
  1% low under background load by more than the spread.
- **FR-027a**: keep a lowered GPU power limit if 1% low and average stay
  within noise of stock and GPU power drops at least 10%.

Status: decided 2026-10-30 from the sessions of 2026-10-28 and 2026-10-29.
Every value is a median of 5 runs; `±` is the spread (max − min).

## How the sessions are run

On each boot entry (default Zen, and `stock`), idle and with `--load`:

```bash
game-bench run -w factorio
game-bench run -w cyberpunk-720p
game-bench run -w cyberpunk -v "baseline wayland-off nggc gpu-3dfs cap-max cap-95 cap-90"
game-bench build-time
game-bench compare ~/.local/share/game-bench/<zen-session> ~/.local/share/game-bench/<stock-session>
```

`cyberpunk-720p` was not run with `--load`.

| Session                          | Kernel | Load |
| -------------------------------- | ------ | ---- |
| `20261029-061849-factorio`       | Zen    | idle |
| `20261029-071351-cyberpunk-720p` | Zen    | idle |
| `20261029-105743-cyberpunk`      | Zen    | idle |
| `20261029-131257-factorio`       | Zen    | load |
| `20261029-141519-cyberpunk`      | Zen    | load |
| `20261028-123014-factorio`       | stock  | idle |
| `20261028-133206-cyberpunk-720p` | stock  | idle |
| `20261028-173511-cyberpunk`      | stock  | idle |
| `20261028-220738-factorio`       | stock  | load |
| `20261028-231801-cyberpunk`      | stock  | load |

## Software versions

| Field        | Value                                                   |
| ------------ | ------------------------------------------------------- |
| Kernel (Zen) | 7.2.11-zen1                                             |
| Kernel stock | 7.2.11                                                  |
| Mesa         | 26.2.5                                                  |
| Proton       | GE-Proton (`proton-ge-bin`, nixpkgs 02c087f)            |
| scx          | 1.1.4                                                   |
| Cyberpunk    | 2.5 (Steam build 26161058)                              |
| Factorio     | Steam build 26076417                                    |

## CPU-side variants (Factorio, Cyberpunk 720p)

Median 1% low (p1): Factorio tick time in ms (lower is better), Cyberpunk
720p in fps (higher is better). Idle sessions; the `--load` sessions are below.

| Variant            | Factorio Zen | Factorio stock | 720p Zen    | 720p stock  |
| ------------------ | ------------ | -------------- | ----------- | ----------- |
| baseline           | 6.11 ± 0.16  | 6.17 ± 0.19    | 159.5 ± 3.5 | 141.4 ± 4.9 |
| gamemode           | 5.81 ± 0.10  | 5.78 ± 0.18    | 155.3 ± 5.9 | 139.9 ± 4.3 |
| ppd-performance    | 5.84 ± 0.15  | 5.82 ± 0.19    | 157.5 ± 8.2 | 138.9 ± 6.2 |
| ccd0               | 6.00 ± 0.11  | 6.02 ± 0.10    | 154.1 ± 8.1 | 153.9 ± 0.9 |
| scx-bpfland        | 5.96 ± 0.28  | 5.92 ± 0.25    | 154.1 ± 5.9 | 131.6 ± 3.2 |
| scx-lavd           | 6.11 ± 0.11  | 5.88 ± 0.22    | 145.1 ± 1.7 | 102.5 ± 3.8 |
| scx-bpfland-no-s76 | 5.90 ± 0.35  | 5.92 ± 0.15    | 154.8 ± 4.1 | 131.9 ± 5.1 |
| scx-lavd-no-s76    | 6.03 ± 0.08  | 5.94 ± 0.14    | 144.7 ± 4.6 | 98.2 ± 3.8  |
| zen-knobs          | n/a          | 6.16 ± 0.26    | n/a         | 138.7 ± 2.1 |

Verdicts:

- **gamemode, ppd-performance: keep for Factorio only** (FR-018). Both put
  the CPU governor and EPP at performance. Factorio's p1 improves by
  0.3 ms, beyond both spreads, and its average by 7% (Zen 2.98 → 2.78 ms,
  spread 0.07 / 0.04). Cyberpunk 720p does not improve. Adopted as GameMode
  through Factorio's launch option, not system-wide, so idle power is
  unchanged.
- **ccd0: drop** (FR-018). Its 9% gain on stock 7.2.11 (141.4 → 153.9) came
  from that session running without ntsync (see Kernel). With ntsync, on
  stock 7.3, it gains nothing (154.8 ± 6.7 → 152.7 ± 9.0), as on Zen.
- **scx-bpfland, scx-lavd, with or without system76-scheduler: drop**
  (FR-018). No gain in Factorio; in 720p bpfland loses 3–7% and lavd 9–30%.
- **zen-knobs: drop** (FR-018). No effect on the stock kernel.

GameMode cannot renice or change I/O priority while system76-scheduler has
set them (`gamemoded`: "prio was (-3) but we expected (-10)"), so its effect
here is the governor alone.

## GPU-side variants (Cyberpunk, normal settings)

Cyberpunk at 3840×2160 with ray tracing, which keeps the GPU at its power
limit. Zen, idle; the stock session agrees within spread.

| Variant     | p1           | p0.1         | avg          | Power W | Verdict | Rule    |
| ----------- | ------------ | ------------ | ------------ | ------- | ------- | ------- |
| baseline    | 39.65 ± 0.25 | 38.43 ± 0.57 | 45.85 ± 0.13 | 264     |         |         |
| wayland-off | 39.64 ± 0.35 | 38.52 ± 1.11 | 45.95 ± 0.23 | 264     | drop    | FR-018  |
| nggc        | 39.62 ± 0.38 | 38.64 ± 0.42 | 45.79 ± 0.32 | 264     | drop    | FR-018  |
| gpu-3dfs    | 39.75 ± 0.33 | 38.82 ± 0.73 | 45.91 ± 0.08 | 264     | drop    | FR-018  |
| cap-max     | 40.55 ± 0.23 | 39.49 ± 0.66 | 46.91 ± 0.22 | 288     | keep    | FR-018  |
| cap-95      | 38.93 ± 0.36 | 37.88 ± 1.12 | 44.90 ± 0.15 | 250     | drop    | FR-027a |
| cap-90      | 38.02 ± 0.39 | 36.58 ± 1.39 | 43.89 ± 0.13 | 237     | drop    | FR-027a |

- **cap-max: keep.** The card's maximum, 290 W, gains 2.3% p1 and 2.3%
  average for 24 W (9%) more power. Set with `modules.gaming.gpu.powerCapWatts`.
- **cap-95, cap-90: drop.** Power drops 5% and 10%, but p1 drops 1.8% and
  4.1%, beyond the spread, so frame rates do not stay within noise.
- **wayland-off, nggc, gpu-3dfs: drop.** No difference beyond the spread.

## Kernel

Baselines only. Build time is `game-bench build-time` (Emacs, 5 runs).

| Kernel | Load | Factorio p1 ms | 720p p1 fps | 4K p1 fps    | Build time s |
| ------ | ---- | -------------- | ----------- | ------------ | ------------ |
| Zen    | idle | 6.11 ± 0.16    | 159.5 ± 3.5 | 39.65 ± 0.25 | 254.5 ± 1.2  |
| Zen    | load | 11.64 ± 8.01   | not run     | 30.60 ± 0.92 |              |
| stock  | idle | 6.17 ± 0.19    | 141.4 ± 4.9 | 39.65 ± 0.74 | 256.2 ± 1.5  |
| stock  | load | 13.05 ± 8.64   | not run     | 37.97 ± 0.69 |              |

**Verdict: stock becomes the default** (FR-024). Zen did not show a 1% low
advantage under background load beyond the spread: Factorio under load is
noise (±8 ms on a 6–13 ms median), and the GPU-limited 4K run favours stock.
Idle, the stock 7.2.11 session was 13% slower in 720p, but only because it
ran without ntsync (below). Re-run with ntsync on stock 7.3
(`20261030-105338-cyberpunk-720p`): baseline p1 154.8 ± 6.7, p0.1 133.3,
avg 211.1, against Zen's 159.5 ± 3.5, 137.2, 218.0, a difference inside the
spread. Build times are equal within spread.

`desktop` now boots `pkgs.linuxPackages_latest` (7.3 at the time of the
switch, the same as `laptop`), not the measured 7.2.11, and the `stock`
comparison entry is off. To re-test, set `boot.kernelPackages` back to Zen
and turn `modules.gaming.kernelComparison.enable` on again.

**Flaw found after the decision, now corrected (2026-10-30):** the stock sessions ran
without ntsync. Zen builds it in (`CONFIG_NTSYNC=y`); the stock kernel
builds it as a module that nothing loaded, so GE-Proton fell back to fsync
(`fsync: up and running` in the stock boot's journal, `ntsync` on Zen). The
720p gap and the `ccd0` gain on stock may come from that rather than from
scheduling. `modules.gaming` now loads `ntsync`, and the re-run above
confirms it: with ntsync, stock matches Zen and `ccd0` no longer helps. The
`zen-knobs` variant also did not reproduce
Zen: it wrote `base_slice_ns` 400000, but Zen runs 1600000 (the kernel
scales the base by CPU count). See `docs/zen-kernel-nobara-research.md`.

Limits of this data:

- The `--load` sessions cannot decide anything: the Emacs rebuild alternates
  between single-threaded and parallel phases, so the load is not steady.
- `game-bench build-time` recorded 0.2–0.3 s for its first run on each boot;
  those rows are ignored.

## Adopted tunings and opt-outs

| Tuning                | Where it is set                         | Opt-out            |
| --------------------- | --------------------------------------- | ------------------ |
| Stock kernel          | `machines/machines.nix` (`desktop`)     | none               |
| GPU power limit 290 W | `modules.gaming.gpu.powerCapWatts`      | none (system-wide) |
| ntsync loaded at boot | `modules.gaming` (`boot.kernelModules`) | none               |
| GameMode for Factorio | launch option `gamemoderun %command%`   | remove the option  |
