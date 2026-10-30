# Data Model: Game Performance Tuning and Benchmarking

Phase 1 output for [plan.md](plan.md). Two kinds of data exist: **Nix-side
definitions** (typed options, evaluated at build time) and **runtime
records** (files the harness writes under
`$XDG_DATA_HOME/game-bench/`, outside the repository).

## Nix-side entities

### Variant (`modules.gaming.benchmark.variants.<name>`)

One named tuning, or the baseline. Defined in one attrset (FR-009). Full
option types are in [contracts/options.md](contracts/options.md).

| Field            | Meaning                                                    |
| ---------------- | ---------------------------------------------------------- |
| `description`    | One line, shown in the summary                             |
| `workloads`      | Workload kinds it can affect: `proton`, `native` (FR-008b) |
| `gamemode`       | Run the game under GameMode for this run                   |
| `cpus`           | CPU list to pin the game to, or null                       |
| `env`            | Extra environment variables for the game                   |
| `cpuProfile`     | PPD profile for the run, or null                           |
| `scx`            | sched_ext scheduler for the run, or null                   |
| `stopSystem76`   | Stop system76-scheduler for the run                        |
| `zenKnobs`       | Apply Zen's runtime scheduler defaults (stock kernel only) |
| `gpuProfile`     | amdgpu power profile for the run, or null                  |
| `gpuPowerCap`    | Watts, or a percentage of the stock cap, or null           |
| `gpuUndervoltMv` | mV below stock voltage (1–200, overdrive), or null         |

Validation (evaluation-time assertions, Principle I):

- `scx` and `zenKnobs` are mutually exclusive (R9).
- `stopSystem76` requires `scx`.
- `baseline` exists and sets nothing.
- Every `workloads` entry names a known workload kind.

Derived: `needsRoot` = any of `cpuProfile`, `scx`, `stopSystem76`,
`zenKnobs`, `gpuProfile`, `gpuPowerCap`, `gpuUndervoltMv` is set. A
variant with `gpuUndervoltMv` is n/a while overdrive is off.

### Workload (`modules.gaming.benchmark.workloads.<name>`)

| Field          | Meaning                                                   |
| -------------- | --------------------------------------------------------- |
| `kind`         | `proton` (Steam launch + MangoHud) or `native` (Factorio) |
| `appid`        | Steam app id                                              |
| `args`         | Game arguments                                            |
| `settingsFile` | Runtime path of a settings file to swap in, or null       |
| `logDelay`     | Seconds before logging starts (proton)                    |
| `logSeconds`   | Logging window (proton)                                   |
| `ticks`        | Tick count (native)                                       |
| `timeout`      | Hard per-run limit in seconds (FR-007)                    |

Defaults: `cyberpunk` (normal settings), `cyberpunk-720p` (swaps the
user-exported 720p `UserSettings.json`), `factorio` (pinned save, R6).

## Runtime entities

### Session

Directory `$XDG_DATA_HOME/game-bench/<YYYYmmdd-HHMMSS>-<workload>/`.

| File             | Content                                                    |
| ---------------- | ---------------------------------------------------------- |
| `session.json`   | Workload, variants, runs, load on/off, start/end, versions |
| `<variant>/<n>/` | One directory per run (see Run)                            |
| `summary.tsv`    | One row per variant (FR-004)                               |
| `summary.txt`    | The same, aligned, plus noise flag and excluded counts     |

`session.json.versions`: kernel (`uname -r`), booted system
(`readlink /run/booted-system`), Mesa, Proton tool and version, game build
id (from `appmanifest_<appid>.acf`), MangoHud, scx.

State transitions:

```text
created ──> warm-up ──> running ──> summarising ──> done
                │           │
                └───────────┴──> interrupted (restore ran, partial summary)
```

### Run

| File              | Content                                                         |
| ----------------- | --------------------------------------------------------------- |
| `state.json`      | System state before and after the run (FR-003)                  |
| `game-frames.csv` | The game's own per-frame log, if any (Cyberpunk); preferred     |
| `frames.csv`      | MangoHud per-frame log (proton), used without `game-frames.csv` |
| `gpu.csv`         | GPU power, clocks, temperatures, fan, load at 1 Hz (proton)     |
| `power.csv`       | Power only (`epoch,microwatts`), sessions before `gpu.csv`      |
| `factorio.out`    | Factorio `--benchmark-verbose` output, parsed for tick times    |
| `game.json`       | Copy of the game's own result file, if any (Cyberpunk)          |
| `status`          | `valid`, `failed:<reason>` or `excluded:<reason>`               |

`state.json` fields: `kernel`, `bootedSystem`, `schedExt`
(`/sys/kernel/sched_ext/state`), `system76` (active/inactive), `governor`,
`epp`, `ppdProfile`, `gpuPerfLevel`, `gpuProfileMode`, `gpuPowerCap`,
`gpuVoltageOffset` (mV from `pp_od_clk_voltage`, empty with overdrive off),
`preempt`, `baseSlice`, `loadRunning`.

Status rules:

- `failed:timeout` — the run hit `timeout` (FR-007).
- `failed:start` — the game never appeared.
- `failed:busy` — the game was still running from an earlier launch.
- `failed:nolog` — a Proton run wrote neither frame log.
- `failed:gamemode` — gamemoded refused the native game's PID.
- `failed:gpu-hang` — amdgpu logged a ring timeout or GPU reset during the
  run; the game's whole process tree was killed. If part of it survives
  SIGKILL, the session stops: Steam would refuse every later launch.
- `skipped:gpu-hang` — a later run of a variant that hung the GPU; not
  started.
- `excluded:short` — fewer than 100 frames or ticks logged.
- `excluded:state` — `state.json` after the run does not match the variant
  (for example `schedExt` no longer `enabled`).

### Metrics (per valid run)

| Metric | Proton workloads                 | Native workload (Factorio) |
| ------ | -------------------------------- | -------------------------- |
| `avg`  | frames ÷ total frametime (FPS)   | mean tick time (ms)        |
| `p1`   | 1000 ÷ p99 frametime (FPS)       | p99 tick time (ms)         |
| `p01`  | 1000 ÷ p99.9 frametime (FPS)     | p99.9 tick time (ms)       |
| power  | median `gpu.csv` power (W)       | n/a                        |
| sclk   | median `gpu.csv` GFX clock (MHz) | n/a                        |
| tj_max | peak junction temperature (°C)   | n/a                        |

`gpu.csv` columns: `epoch,power_uw,sclk_hz,mclk_hz,edge_mc,junction_mc,
mem_mc,fan_rpm,busy_pct`, read from the amdgpu hwmon and
`gpu_busy_percent`. The raw file stays in the run directory for throttling
checks.

GPU metrics count only samples inside the benchmark pass: the
`Data.time` seconds in `game.json` ending at `game-frames.csv`'s mtime.
Without both files it uses every sample of the run.

Summary row per variant: valid runs, excluded runs, median and spread
(max − min) of `avg`, `p1`, `p01`, median power, median GFX clock, and the
highest junction temperature of any run. "Better" means higher
for FPS and lower for tick time.

Noise flag (SC-003): baseline `p1` spread > 5% of its median, or `avg`
spread > 3%.

### Restore journal

`$XDG_RUNTIME_DIR/game-bench/journal`: one line per change applied
(`<helper subcommand to undo it>`), appended before the change is made.
Replayed in reverse after every run, on exit, interrupt, failure, or at the
next start if a previous session died. Empty after a clean restore (FR-005,
SC-002).

`$XDG_RUNTIME_DIR/game-bench/session-journal` holds changes that last the
whole session (the workload's settings-file swap). It is replayed on exit,
interrupt, failure, `game-bench restore`, or at the next start, but not
between runs.

### Lock and per-run file

`$XDG_RUNTIME_DIR/game-bench/lock` holds the session's PID.
`$XDG_RUNTIME_DIR/game-bench/run.env` holds the current run's settings for
`game-bench-wrap`. The wrapper ignores `run.env` unless the PID in `lock` is
alive (FR-006).

### Comparison

Output of `game-bench compare <session>...`: one block per workload, rows
per (session, variant), labelled by kernel tag and load. A warning lists
every `versions` field that differs between sessions, kernel excepted
(FR-012).

### Decision record

`docs/gaming-benchmarks.md` (committed, Phase 2): per variant, the summary
rows, `versions`, kernel, load, verdict (`keep`/`drop`) and the rule that
decided it (FR-018, FR-024, FR-027a), plus the exact `game-bench` command.
