# Feature Specification: Game Performance Tuning and Benchmarking

**Feature Branch**: `008-game-performance-tuning`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "the game performance tuning and benchmarking.
Also, I haven't really used gamescope at all recently since I find it causes
more problems than it fixes. So remove that". Expanded: "GPU power-limit is
in-scope. Also, take the findings from this artifact into consideration"
(the artifact is the report "Zen kernel: cheap to try, rarely worth it",
saved locally as `~/Downloads/Zen kernel benefits on NixOS.md`).

Sources:

- `docs/gaming-performance-research.md` (commit `2132898`). It found that two
  configured performance features are not in effect for Steam games, ranked
  eight candidate changes, and proposed a way to benchmark each one
  automatically.
- The Zen kernel report. It found that no EEVDF-era benchmark shows the Zen
  kernel beating the stock kernel beyond noise. On NixOS, Zen differs from
  the stock kernel mainly in full preemption, the 1000 Hz tick, about 15
  scheduler and memory defaults, and `vm.max_map_count`; all but the tick can
  be set on the stock kernel at runtime. Zen follows the newest stable series
  with no LTS line, and its place in nixpkgs is uncertain. The report
  recommends the stock kernel plus a sched_ext scheduler and a few sysctls,
  with Zen kept as a boot-menu entry for an A/B test. It says to judge by
  1% and 0.1% lows rather than average FPS, at least five runs per variant,
  and to also test while a compile runs in the background, a case no
  published test covers.

## Clarifications

### Session 2026-10-27

- Q: Should this feature ship only the parts that don't need benchmark
  results, with the measurement-dependent decisions done later as follow-up
  issues? → A: Yes, two phases. Phase 1 ships the harness, the gamescope
  removal, the GameMode fixes and the boot-menu kernel entries. Adopting
  tunings, choosing the kernel and setting the power limit are Phase 2,
  tracked as beads issues blocked on the user running the benchmarks.
- Q: When is a GPU power limit below stock good enough to keep? → A: When
  its median 1% low and average frame rate stay within run-to-run spread of
  stock, and its median GPU power draw is at least 10% lower.
- Q: Which test should show whether the CPU-side changes help? → A: Two
  unattended workloads, reported separately: Factorio's command-line
  benchmark on a community benchmark save, and Cyberpunk 2077's built-in
  benchmark at 1280×720 with upscaling off.
- Q: What should the background compile be when testing the kernel and
  schedulers under load? → A: Repeated rebuilds of one pinned, medium-sized
  package from this flake's nixpkgs, using all cores.

- Deploy finding (2026-10-27): preloading GameMode's client library for all
  of Steam aborts the Steam client on a D-Bus assertion, and the UI shows
  "Unexpected Transport Error" (Steam `console-linux.txt`). Per research R7
  the fallback applies: GameMode is per game through the launch option
  `gamemoderun %command%`. FR-016 is not met; SC-005 holds only for games
  with that launch option.

## User Scenarios & Testing *(mandatory)*

The user is the single owner of this workstation configuration. Only the
`desktop` machine (Ryzen 9 9950X, Radeon RX 7900 XT, 20 GiB) has gaming enabled. It
is used for both development and gaming. The user plays through Steam,
mostly with GE-Proton. All three machines currently run the Zen kernel,
except `laptop`, which runs the latest stock kernel.

"Variant" below means one candidate tuning, or the unchanged baseline, that
can be switched on for a single benchmark run. "Benchmark session" means one
unattended series of runs that covers a chosen set of variants. "Background
load" means a sustained compile at normal priority that resembles the user's
development work.

### User Story 1 - Benchmark candidate tunings without manual steps (Priority: P1)

The user starts one command, names the variants to compare and the number of
runs, and walks away. The command runs a repeatable in-game benchmark for
each variant. It runs the variants interleaved, repeats each one, and
restores the system to its normal state afterwards. At the end it prints a
table with, per variant, the median 1% low, the median 0.1% low, the median
average frame rate and the run-to-run spread.

**Why this priority**: The research reports' impact estimates are priors,
not measurements. Every adoption decision in User Stories 3 to 5 depends on
these numbers. The harness is also useful on its own whenever a driver,
Proton or kernel update lands.

**Independent Test**: Run a session with the baseline and one other variant
at 3 runs each. Confirm that the summary table lists both variants with 3
runs each. Confirm that each run's log records the variant's system state,
and that the system is back in its normal state afterwards.

**Acceptance Scenarios**:

1. **Given** a game whose Steam launch options route through the benchmark
   hook, **When** the user starts a session for variants A and B with 5 runs,
   **Then** the session runs one discarded warm-up run, then 5 runs of each
   variant in alternating order. It prints one summary row per variant.
2. **Given** a session is running, **When** it ends normally, fails, or is
   interrupted with Ctrl-C, **Then** every system setting the session
   changed is back to its pre-session value.
3. **Given** no benchmark session is running, **When** the user launches the
   same game normally from Steam, **Then** the game starts exactly as it
   would without the benchmark hook: no logging, no overlay, no tuning.
4. **Given** a run in which the game fails to start or does not exit,
   **When** the run's time limit passes, **Then** the session stops the game,
   records the run as failed and continues with the next run.
5. **Given** a finished session, **When** the user opens its output
   directory, **Then** it contains the raw per-frame log of every run, grouped
   by variant, and the summary table.
6. **Given** the user asks for background load, **When** the session runs,
   **Then** every run of every variant has the same background load running,
   and the summary states that the session was under load.

---

### User Story 2 - Remove gamescope (Priority: P1)

The user has stopped using gamescope because it causes more problems than it
fixes. Every gamescope piece is removed from the configuration: the custom
`gamescope-game` launcher, the system-wide gamescope program, the Steam
gamescope login session and the gamescope HDR layer.

**Why this priority**: The user asked for it directly. It shrinks the
configuration and removes the one place that currently calls GameMode, so
User Story 3 has to replace that.

**Independent Test**: Build and deploy `desktop`. Confirm that no gamescope
command is on the path, that the login screen offers no Steam gamescope
session, and that Steam and the installed games still launch.

**Acceptance Scenarios**:

1. **Given** the deployed `desktop` configuration, **When** the user searches
   the system for a gamescope executable or launcher, **Then** none is found.
2. **Given** the login screen, **When** the user lists the available
   sessions, **Then** no Steam gamescope session appears.
3. **Given** the deployed configuration, **When** the user starts Steam and a
   game, **Then** both start, and Steam Input still works under Wayland.
4. **Given** the repository, **When** the user searches the Nix and Org
   configuration for gamescope, **Then** there are no matches.

---

### User Story 3 - Adopt tunings that measurably help (Priority: P2)

The user wants games to run faster without having to remember per-game
tricks. Tunings that the benchmark shows help are made permanent in the
configuration, applied to every Steam game by default, and the user can
turn each one off for a single game. Tunings that do not help, or that
cannot be told apart from noise, are not adopted.

The always-correct fixes from the research are made regardless of benchmark
results, because they only make an already-enabled feature work: GameMode
takes effect for Steam games, and the user's account gets the permissions
GameMode needs for process priority.

**Why this priority**: This is the actual performance gain, but it depends on
the measurements from User Story 1. Only the GameMode fixes are Phase 1;
adopting benchmarked tunings is Phase 2 (FR-030).

**Independent Test**: Launch any Steam game with default launch options.
Confirm that GameMode reports the game as registered while it runs, and that
the CPU returns to its normal power policy when the game exits.

**Acceptance Scenarios**:

1. **Given** the deployed configuration, **When** the user starts any Steam
   game with no launch options, **Then** GameMode is active for that game
   and its priority and CPU tunings take effect without error.
2. **Given** a tuning that the benchmark showed to help, **When** it is
   adopted, **Then** it applies to every Steam game by default, and a
   per-game launch option turns it off for that game alone.
3. **Given** a variant whose median gain is smaller than its run-to-run
   spread, **When** the results are reviewed, **Then** that variant is not
   adopted. The benchmark result and the reason are recorded.
4. **Given** the adopted set of tunings, **When** the game exits, **Then**
   every system-wide setting the tunings changed returns to its normal
   value.
5. **Given** an adopted system-wide tuning such as a scheduler, **When** the
   harness times the pinned clean rebuild (FR-013), **Then** the build is
   not slower than the baseline beyond run-to-run spread.

---

### User Story 4 - Decide the kernel by measurement (Priority: P2)

The user wants to know whether the Zen kernel earns its maintenance cost on
`desktop`. Both kernels from the same upstream series are available as boot
menu entries, so the user can switch by rebooting, without a rebuild. The
user runs the same benchmark session once on each kernel, with and without
background load, and the harness compares the sessions. The kernel that
wins stays the default. If the two are within noise, the stock kernel wins,
because it is the lower-maintenance choice.

**Why this priority**: The Zen report says this decision cannot be settled
by published data and is cheap to test on NixOS. It needs User Story 1 and
a reboot per kernel, so it cannot be fully automated within one session.

**Independent Test**: Boot each entry, confirm which kernel and scheduler
are running, run the same session on each, and confirm that the harness
prints one comparison across both sessions.

**Acceptance Scenarios**:

1. **Given** the deployed `desktop` configuration, **When** the user opens
   the boot menu, **Then** it offers the default entry and one alternative
   kernel entry, both from the same upstream kernel series.
2. **Given** two finished sessions, one per kernel, **When** the user asks
   the harness to compare them, **Then** it prints the summary rows of both
   side by side, labelled by the kernel each ran on.
3. **Given** a session started on the alternative kernel entry, **When** it
   records its state, **Then** the kernel version and loaded scheduler are
   part of each run's recorded state.
4. **Given** the stock kernel as the default, **When** it runs, **Then** the
   Zen behaviours that can be set at runtime and that the benchmark showed
   to help are set on it.
5. **Given** Zen does not beat the stock kernel's 1% lows under background
   load by more than run-to-run spread, **When** the decision is made,
   **Then** the stock kernel becomes the default on `desktop`.

---

### User Story 5 - Tune the GPU power limit (Priority: P3)

The user wants to know whether a different GPU power limit gives better
frame rates, or the same frame rates at lower power and noise. The benchmark
includes variants with the GPU power limit raised to the highest allowed
value and lowered by fixed steps. Each run records GPU power, clocks and
temperature. If a limit wins, the configuration sets it permanently, and
the user can return to the stock limit with one change.

**Why this priority**: The user brought it into scope explicitly. It has the
highest risk of all the tunings, since it changes hardware operating limits,
so it comes after the low-risk changes.

**Independent Test**: Run a session with the stock limit, the highest
allowed limit and one lowered limit. Confirm that each run records the
power limit it ran with, and that the stock limit is back after the session.

**Acceptance Scenarios**:

1. **Given** a session with power-limit variants, **When** a run starts,
   **Then** the GPU power limit for that run is set to the variant's value,
   and the run's recorded state shows that value.
2. **Given** a power-limit variant outside the range the card's firmware
   allows, **When** the session applies it, **Then** the session refuses the
   variant and reports why. It does not benchmark it.
3. **Given** a session that changed the power limit, **When** it ends for any
   reason, **Then** the stock power limit is back.
4. **Given** an adopted power limit, **When** the machine boots, **Then** the
   limit is in effect, and the record states the measured frame rate, power
   draw and temperature that justified it.

---

### User Story 6 - Record what was measured and decided (Priority: P3)

Months later, after a driver or kernel update, the user wants to know which
tunings were tried, what they measured, and why each was kept or dropped, so
they can re-run the same comparison and see whether the decision still
holds.

**Why this priority**: Useful but not needed for the speed-up itself.

**Independent Test**: Read the record and re-run the exact session it
describes with the command it gives.

**Acceptance Scenarios**:

1. **Given** the completed feature, **When** the user reads the record,
   **Then** it lists every variant benchmarked, its summary numbers, the
   software versions and kernel at the time, whether background load was on,
   and the keep or drop decision with reason.
2. **Given** the record, **When** the user copies its benchmark command,
   **Then** the command reproduces the same session.

---

### Edge Cases

- The game updates, or shaders are recompiled, between runs: the warm-up run
  absorbs the first compile. A Steam update during the session invalidates
  that session, and the summary must make a short run visible.
- A run's per-frame log is missing or has too few frames: that run is
  excluded from the summary, and the excluded count is shown.
- Frame-time logging itself can cause hitches: every variant, including the
  baseline, is logged the same way, so the effect is equal across variants.
- A variant needs administrator rights (scheduler, GPU power state or
  limit): the session asks for them once at the start, not halfway through
  an unattended series.
- A variant cannot be applied on this machine, for example because a
  scheduler fails to load: the session reports it and skips that variant
  instead of benchmarking the baseline under the variant's name.
- A scheduler stalls the system for a second or so at game launch (reported
  for `scx_lavd`): the run's log shows the stall in its 0.1% low, and the
  record notes it. An adopted scheduler can be turned off with one change.
- A scheduler exits during a run: the system falls back to the default
  scheduler, and the run's recorded state must show it, so the run is
  excluded rather than counted for the wrong variant.
- The game is GPU-bound at the chosen settings: CPU-side variants show no
  difference. The summary still reports it, and the record notes it. CPU-side
  decisions are taken from the CPU-bound workloads (FR-008a), not from the
  normal-settings run.
- Cyberpunk at 1280×720 still reports high GPU load: the summary flags that
  workload as not CPU-bound, and Factorio alone decides CPU-side variants.
- The user plays normally while a stale variant file is left from a crashed
  session: normal launches must not pick up a stale variant.
- The machine crashes or reboots during a session with a changed GPU power
  limit: the stock limit applies after the reboot unless a limit was adopted
  in the configuration.
- Background load finishes before the session does: the load restarts, so
  every run has load.
- Two sessions being compared ran with different game, driver or Proton
  versions: the comparison warns that they are not comparable.
- The benchmark is started on a machine without gaming enabled: the command
  is not available there.
- A tuning conflicts with another service already running (for example a
  second scheduler tuner): the benchmark includes a variant with the other
  service stopped before either is adopted.

## Requirements *(mandatory)*

### Functional Requirements

**Benchmark harness**

- **FR-001**: The system MUST provide one command that runs a benchmark
  session for a user-chosen list of variants and number of runs, against a
  user-chosen Steam game and its benchmark arguments, with defaults for all
  of them.
- **FR-002**: Each session MUST run one discarded warm-up run, then
  interleave the variants round-robin, and pause between runs so that
  hardware temperature does not favour one variant. The default number of
  runs per variant MUST be at least 5.
- **FR-003**: Each run MUST record a per-frame timing log, along with the
  system state that shows the variant was really in effect: kernel version,
  active scheduler, CPU power policy, GPU power state and power limit.
- **FR-004**: The session MUST print, per variant, the number of valid runs,
  the median 1% low, the median 0.1% low, the median average frame rate,
  and the spread of each across runs. The 1% low is the primary metric.
- **FR-005**: The session MUST restore every setting it changed when it ends
  normally, fails or is interrupted.
- **FR-006**: Game launches outside a session MUST behave as if the
  benchmark hook were absent, including after a crashed session.
- **FR-007**: A run that does not finish within a time limit MUST be
  stopped and counted as failed, without stopping the session.
- **FR-008**: The variant set MUST include at least: baseline, GameMode,
  maximum CPU power profile, pinning to the faster CCD, `scx_bpfland` and
  `scx_lavd` (each alone and with the competing scheduler service stopped),
  Zen's scheduler defaults applied to the stock scheduler, Proton Wayland
  off, opt-in RADV NGG culling, the GPU full-screen 3D power profile, and
  GPU power-limit variants.
- **FR-008a**: The harness MUST support at least three workloads, each
  unattended and reported separately: Cyberpunk 2077's built-in benchmark at
  the user's normal settings (GPU-side variants), the same benchmark at
  1280×720 with upscaling off (CPU-side variants through Proton), and
  Factorio's command-line benchmark on a fixed community benchmark save
  (CPU-side variants, measured as simulation time per tick rather than frame
  rate). For Factorio, "1% low" and "0.1% low" in FR-004 and FR-018 mean the
  99th and 99.9th percentile tick time, and "average frame rate" means the
  mean tick time.
- **FR-008b**: A variant that cannot affect a workload MUST be skipped for
  that workload and reported as not applicable, for example Proton and RADV
  variants on Factorio, which runs natively.
- **FR-009**: Adding a variant MUST require changing only one place.
- **FR-010**: The harness MUST exist only on machines with gaming enabled.
- **FR-011**: The session MUST optionally run a background compile load for
  its whole duration, at normal priority, the same for every run. The load
  is a repeated rebuild of one pinned, medium-sized package from this
  flake's nixpkgs (default: Emacs), using all cores. The package is pinned
  by the flake lock, so every run compiles the same source.
- **FR-012**: The harness MUST compare two or more finished sessions side by
  side, labelled by kernel and load, and warn when their game, driver or
  Proton versions differ.
- **FR-013**: The harness MUST time a clean rebuild of the same pinned
  package as FR-011 several times and report its median and spread, so that
  a system-wide tuning can be checked for a development slowdown.

**gamescope removal**

- **FR-014**: The configuration MUST NOT install or enable gamescope in any
  form: the `gamescope-game` launcher, the gamescope program, the Steam
  gamescope session, and the gamescope WSI layer.
- **FR-015**: Steam, its Proton tools, Steam Input under Wayland, Lutris and
  Prism Launcher MUST keep working after the removal.

**Tuning**

- **FR-016**: GameMode MUST take effect for every Steam game without
  per-game launch options.
- **FR-017**: The user's account MUST have the permissions GameMode needs
  for its process-priority and core features.
- **FR-018**: A benchmarked tuning MUST be adopted only if its median 1% low
  gain is larger than the run-to-run spread of both it and the baseline, and
  neither 0.1% low nor average frame rate regresses beyond that spread.
- **FR-019**: Each adopted per-game tuning MUST apply to all Steam games by
  default and MUST be possible to turn off for one game through its launch
  options.
- **FR-020**: An adopted system-wide tuning MUST NOT slow the clean-build
  timing from FR-013 beyond its run-to-run spread.
- **FR-021**: The benchmark results, decisions and reasons MUST be recorded
  in the repository, together with the command that reproduces them.

**Phasing**

- **FR-030**: The feature MUST be delivered in two phases. Phase 1 is
  complete when User Stories 1 and 2, FR-016, FR-017 and FR-022 are
  deployed. Phase 2 covers every decision that needs benchmark results:
  FR-018 to FR-021, FR-024, FR-025 adoption, FR-027a and FR-028.
- **FR-031**: At the end of Phase 1, each Phase 2 decision MUST exist as a
  beads issue that states the session to run and the adoption rule, and that
  is blocked until the user has run that session.

**Kernel**

- **FR-022**: `desktop` MUST offer the stock and the Zen kernel as boot menu
  entries from the same upstream series, switchable without a rebuild.
- **FR-023**: The kernel comparison MUST run on both entries with the same
  variants, once without and once with background load.
- **FR-024**: The Zen kernel MUST remain the default only if it beats the
  stock kernel's median 1% low under background load by more than the
  run-to-run spread. Otherwise the stock kernel MUST become the default.
- **FR-025**: The Zen behaviours that can be set at runtime on the stock
  kernel (preemption mode, swap-in readahead, `vm.max_map_count`, the I/O
  schedulers, and the scheduler slice and migration defaults) MUST be
  benchmarkable as variants on the stock kernel, and MUST be applied only
  if they pass FR-018.

**GPU power limit**

- **FR-026**: The harness MUST support power-limit variants given as a
  value or as a percentage of the stock limit, within the range the card's
  firmware allows. It MUST refuse values outside that range.
- **FR-027**: Each run MUST record the GPU's power draw, clocks and
  temperature, alongside the power limit.
- **FR-027a**: A raised power limit MUST be adopted only under FR-018. A
  lowered power limit MUST be adopted only if its median 1% low and median
  average frame rate are within run-to-run spread of the stock limit, and its
  median GPU power draw is at least 10% lower than at the stock limit. If
  several lowered limits qualify, the lowest one wins.
- **FR-028**: An adopted power limit MUST apply at every boot, and MUST be
  revertible to the stock limit with one configuration change.
- **FR-029**: This feature MUST NOT raise GPU voltages, change clock
  offsets, or set a power limit outside the driver's allowed range. Amended
  2026-10-30 at the user's request: a voltage *offset below stock* (an
  undervolt, at most 200 mV) is allowed as a benchmark variant once amdgpu
  overdrive is enabled (`modules.gaming.gpu.overdrive.enable`), and the
  power limit may then use overdrive's wider range. See ADR 0010.

### Key Entities

- **Variant**: a named tuning, or the baseline. It has a way to switch it on
  for one run, a way to switch it off, and whether it needs administrator
  rights.
- **Run**: one launch of the benchmark under one variant. It has a frame
  log, a recorded system state, and a status (valid, failed, excluded).
- **Session**: an ordered set of runs over chosen variants, on one kernel,
  with or without background load. It has an output directory and a summary
  table.
- **Comparison**: two or more sessions summarised side by side, with a
  warning when their software versions differ.
- **Decision record**: per variant, its summary numbers, software versions,
  kernel, load, and the keep or drop verdict with reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A benchmark session of 7 variants × 5 runs completes without
  user interaction after the start, apart from one administrator prompt.
- **SC-002**: After any session, including an interrupted one, 100% of the
  settings it changed are back at their pre-session values.
- **SC-003**: Repeating the baseline in the same session gives a 1% low
  spread of 5% or less and an average frame rate spread of 3% or less.
  Otherwise the summary flags the session as too noisy to decide on.
- **SC-004**: 0 gamescope components remain installed on `desktop`, and 0
  references remain in the Nix and Org configuration.
- **SC-005**: Every Steam game launched with default options runs with
  GameMode active.
- **SC-006**: Every adopted tuning shows a median 1% low gain larger than
  its measured noise, and no adopted tuning lowers the 0.1% low or average
  frame rate beyond noise.
- **SC-007**: No adopted system-wide tuning or kernel choice makes the
  clean-build timing slower beyond its measured noise.
- **SC-008**: The kernel decision on `desktop` is backed by at least 5 runs
  per kernel, both with and without background load.
- **SC-008a**: An adopted lowered power limit draws at least 10% less GPU
  power than stock in the recorded benchmark, with 1% low and average frame
  rate within noise of stock.
- **SC-009**: The user can re-run any recorded comparison with commands
  copied from the record.

## Assumptions

- `desktop` is the only machine with gaming enabled, and the only machine
  whose kernel this feature may change. `laptop` stays on its current
  kernel. The third machine keeps the shared default until a separate
  decision.
- The kernel comparison uses the latest stock kernel, not the NixOS LTS
  default, so that both entries come from the same upstream series, as the
  Zen report advises.
- If Zen loses, its boot entry may stay for later re-tests or be removed;
  the record states which.
- The 1000 Hz tick is not reproduced on the stock kernel: it needs a custom
  kernel build, and the Zen report's cited data shows no gain from it.
- Zen's ACS override, its amdgpu option to go below the firmware's minimum
  power limit, BBRv3 and VHBA are not needed and are out of scope.
- The workloads are fixed by FR-008a. Cyberpunk 2077 is installed. Whether
  its benchmark can be started and ended unattended from the command line is
  not yet verified; if it cannot, the harness logs a fixed time window and
  the user starts the scene, which breaks SC-001 for that workload only.
  Factorio is in the user's library and is installed for benchmarking. Its
  benchmark save is a published community map, pinned by hash and stored
  outside the repository with the benchmark output. The exact command-line
  flags and output format are to be confirmed from Factorio's documentation
  during planning.
- Other games in the library were considered and rejected as workloads:
  GTA V and Red Dead Redemption 2 (benchmarks behind the Rockstar launcher,
  unattended start unverified), Horizon Zero Dawn and Forza Horizon 5
  (benchmark started from the menu only), and Cities: Skylines, Starfield
  and Hogwarts Legacy (no built-in benchmark).
- Steam launch options are per-game client settings outside the repository.
  The user sets the benchmark hook once per benchmarked game, by hand.
- The benchmark runs from a terminal in the user's graphical session, not in
  the agent sandbox, which cannot reach the Steam session.
- Benchmark output lives outside the repository. Only the summaries and
  decisions are committed.
- "Faster CCD" means cores `0-7,16-23`, the CCD that the firmware ranks
  higher on this CPU.
- The firmware-allowed power-limit range on this card is 238–290 W, with
  265 W stock, and the driver accepts the whole range without the overdrive
  feature unlocked (see `research.md`). Overdrive was locked until the
  FR-029 amendment of 2026-10-30.
- The Steam extest input shim and the desktop UI scaling variable are kept.
  They serve Steam Input and scaling under Wayland, not gamescope.
- The research report's section on gamescope (recommendation 8) and its
  gamescope benchmark variant are superseded by the removal.
- `vm.max_map_count` is already 1048576 from the NixOS default. Zen's value
  (about 2³¹) is a variant only if a benchmarked game is known to need more.
