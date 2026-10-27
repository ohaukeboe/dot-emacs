# Tasks: Game Performance Tuning and Benchmarking

**Input**: Design documents from `specs/008-game-performance-tuning/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/, quickstart.md

**Tests**: The spec asks for no TDD. One fast flake check, `game-bench`, is
still included, because constitution Principles I and III require one for
new scripts. Its fixtures are built in US1.

**Organization**: Tasks are grouped by user story. This file covers
**Phase 1 of the feature** (spec FR-030). Phase 2 decisions are created as
beads issues in the last phase, not implemented here.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel: different files, and no dependency on an
  unfinished task.
- **[Story]**: the user story the task belongs to (US1–US6).

## Rules for every task

- The flake sees only git-tracked files. `git add` every new file before
  `nix build` or `nix flake check`.
- Shell goes in `scripts/game-bench/*.sh`, wrapped with
  `writeShellApplication` in `modules/gaming/bench/default.nix`, with every
  tool listed in `runtimeInputs` or referenced as `${pkg}/bin/...`.
- Python goes in `scripts/game-bench/summary.py`, wrapped with
  `pkgs.writers.writePython3Bin` (flake8 runs at build). Standard library
  only.
- Assertion messages name their file and the fix, as in
  `workstation/agents/process-cap.nix:255-271`.
- Use `config.user.username`, never the literal user name.
- Everything new in `modules/gaming/` sits inside `mkIf cfg.enable`.
- The agent sandbox cannot reach Steam, the GPU or sudo. Steps marked
  **(user)** are the user's, on `desktop`.

## Phase 1: Setup

**Purpose**: file layout for the split module and the harness.

- [X] T001 Create directories `modules/gaming/bench/`, `scripts/game-bench/` and `tests/fixtures/game-bench/`, and add `./kernel.nix`, `./gpu.nix` and `./bench` to the `imports` of `modules/gaming/default.nix` (create `modules/gaming/kernel.nix` and `modules/gaming/gpu.nix` as empty modules `{ ... }: { }` for now)
- [X] T002 [P] Create `beads` epic (`dot-emacs-t21`; stories `.1`–`.6`, Phase 2 gate `.7`, decisions `.8`–`.13`) "008 game performance tuning" with `bd create --type=epic` and record its id in `specs/008-game-performance-tuning/tasks.md` under this phase; create one child task per user story with `--parent`

---

## Phase 2: Foundational

**Purpose**: the typed options every story reads (contract:
`contracts/options.md`).

**⚠️ CRITICAL**: no story can start until this phase is complete.

- [X] T003 Declare `modules.gaming.benchmark.{enable,variants,workloads,loadPackage}`, `modules.gaming.kernelComparison.enable`, `modules.gaming.gpu.powerCapWatts` and `modules.gaming.tunings.env` in `modules/gaming/default.nix`, with exactly the types in `contracts/options.md`: `cpus` is `types.nullOr (types.strMatching "[0-9,-]+")`, `scx` is `types.nullOr (types.enum [ "scx_bpfland" "scx_lavd" ])`, `gpuPowerCap` is `types.nullOr (types.oneOf [ types.ints.positive (types.strMatching "[0-9]{1,3}%") (types.enum [ "max" ]) ])`, workload `kind` is `types.enum [ "proton" "native" ]`, `timeout` default `900`, `logDelay` default `20`, `logSeconds` default `60`, `ticks` default `6000`
- [X] T004 Add the option assertions to `modules/gaming/default.nix`: `benchmark.variants.baseline` exists and sets nothing; no variant sets both `scx` and `zenKnobs`; `stopSystem76` requires `scx`; `gpu.powerCapWatts != null` requires `amdgpu` in `modules.silent-boot.earlyKms.modules` or `hardware.amdgpu` enabled
- [X] T005 Create `modules/gaming/bench/variants.nix` returning the default `variants` (the 15 variants in the "Default variants" table in `contracts/options.md`; `wayland-off`, `nggc`, `gpu-3dfs`, `cap-max`, `cap-95`, `cap-90` get `workloads = [ "proton" ]`) and default `workloads` `cyberpunk` (`kind = "proton"`, `appid = 1091500`, `args = [ "--launcher-skip" "-benchmark" "-skipStartScreen" ]`), `cyberpunk-720p` (same, `settingsFile = "~/.local/share/game-bench/cyberpunk-720p.json"` expanded at runtime) and `factorio` (`kind = "native"`, `appid = 427520`); set them as option defaults in `modules/gaming/default.nix`
- [X] T006 Set `modules.gaming.benchmark.loadPackage` default in `modules/gaming/default.nix` to the bare Emacs package the repo uses (`emacs-unstable-pgtk`, per `workstation/home.nix:65-67`; if the emacs-overlay is not applied to the NixOS `pkgs`, use the home-manager package via `config.home-manager.users.${config.user.username}` or fall back to `pkgs.emacs-pgtk`, and note which in a comment)
- [X] T007 Run `nix flake check` and `nix build '.#nixosConfigurations.desktop.config.system.build.toplevel' --no-link`; both pass with no behaviour change yet

**Checkpoint**: options evaluate; stories can start.

---

## Phase 3: User Story 2 - Remove gamescope (Priority: P1) 🎯 MVP part 1

**Goal**: no gamescope anywhere (FR-014, FR-015).

**Independent Test**: quickstart step 2.

- [X] T008 [US2] In `modules/gaming/default.nix` delete the `gamescope-game` `let` binding and its `environment.systemPackages` entry, `programs.steam.gamescopeSession.enable`, the `programs.gamescope` block and `gamescope-wsi`; keep `extest.enable` and `STEAM_FORCE_DESKTOPUI_SCALING` with a comment that they serve Steam Input and scaling under Wayland
- [X] T009 [US2] Verify `rg -n gamescope --glob '*.nix' --glob '*.org' .` has no matches outside `specs/` and `docs/`, then `nix build` desktop's toplevel
- [X] T010 [US2] Add a "Superseded" note to section 8 of `docs/gaming-performance-research.md` pointing to `specs/008-game-performance-tuning/spec.md` (gamescope removed)

**Checkpoint**: US2 deployable on its own.

---

## Phase 4: User Story 1 - Benchmark harness (Priority: P1) 🎯 MVP part 2

**Goal**: `game-bench` runs sessions unattended and restores everything
(FR-001–FR-013).

**Independent Test**: quickstart step 6.

### Root helper and wrappers

- [X] T011 [P] [US1] Write `scripts/game-bench/game-bench-priv.sh` per `contracts/game-bench-priv.md`: subcommands `check`, `scx-start <scx_bpfland|scx_lavd>`, `scx-stop`, `s76-stop`, `s76-start`, `zen-knobs <on|off>`, `gpu-profile <3d-full-screen|default>`, `gpu-cap <watts|default>`, `gpu-cap-range`; fixed write targets only; `scx-start` uses `systemd-run --unit game-bench-scx` with the scheduler path passed in as `@scx@` substitution and waits ≤ 5 s for `/sys/kernel/sched_ext/state` = `enabled`; `zen-knobs on` saves previous values in `/run/game-bench-priv/` and refuses unless `readlink /run/booted-system` ends in `-stock`; `gpu-cap` finds the hwmon whose `name` is `amdgpu`, refuses values outside `power1_cap_min`..`power1_cap_max` with exit 2, writes watts × 1000000, and `default` writes `power1_cap_default`; any invalid argument exits 2 and changes nothing
- [X] T012 [P] [US1] Write `scripts/game-bench/game-bench-wrap.sh` per `contracts/game-bench-wrap.md`: pass through with `exec "$@"` unless `$XDG_RUNTIME_DIR/game-bench/lock` names a live PID and `run.env` exists; parse `run.env` line by line as `KEY=value` (never `source`), honour only `GB_ENV`, `GB_CPUS`, `GB_GAMEMODE`, `GB_MANGOHUD`; `exec` the composed command
- [X] T013 [P] [US1] Write `scripts/game-bench/game-bench-nogamemode.sh`: remove `libgamemodeauto.so.0` from `LD_PRELOAD` (space- or colon-separated), keep every other entry, `exec "$@"`

### Summary and comparison

- [X] T014 [P] [US1] Write `scripts/game-bench/summary.py` with subcommands `summarise <session-dir>` and `compare <dir>...`: parse MangoHud CSVs (skip to the line starting `fps,frametime`), Factorio `ticks.csv` (header read from the file), compute per run `avg`, `p1`, `p01` and median `gpu_power` as defined in `data-model.md` "Metrics"; exclude runs with fewer than 100 frames or ticks (`excluded:short`) or a non-`valid` `status`; write `summary.tsv` and `summary.txt` (median and spread per variant, excluded count, noise flag when baseline `p1` spread > 5% or `avg` spread > 3%); `compare` labels rows `<kernel tag>/<load|idle>` and prints `WARNING: versions differ: <fields>` for any differing `session.json.versions` field except `kernel` and `bootedSystem`
- [X] T015 [P] [US1] Add fixtures (implemented as generators inside `tests/game-bench.nix`, no fixture files): a two-variant proton session (MangoHud CSV format from `research.md` R3, 3 runs each, one run with 50 frames), a native session with a Factorio `ticks.csv` (placeholder header `tick,timestamp,wholeUpdate`, replaced by the real header after the quickstart step 5 probe), and two `session.json` files whose `versions.mesa` differ

### Main CLI

- [X] T016 [US1] Write `scripts/game-bench/game-bench.sh` per `contracts/game-bench-cli.md` with subcommands `run`, `compare`, `build-time`, `restore`, `list`; variants and workloads are read from a JSON file passed as `@config@` (generated by T018); implement lock (refuse if live, replay journal if dead), `sudo -n game-bench-priv check` when any chosen variant needs root (exit 2 before changes), drop and print n/a variants by workload kind (and `zen-knobs` when the booted system is not tagged `stock`), warm-up run discarded, round-robin loop, cool-down, `trap` on EXIT INT TERM HUP that stops the load loop, kills the game's reaper process group, replays the journal in reverse, and removes `run.env` and `lock`; exit codes 0/1/2/130
- [X] T017 [US1] In `scripts/game-bench/game-bench.sh` implement per-run work: journal the undo before each apply (`powerprofilesctl set balanced` for `cpuProfile`, `game-bench-priv scx-stop`, `s76-start`, `zen-knobs off`, `gpu-profile default`, `gpu-cap default`); resolve `gpuPowerCap` `"max"` and `"N%"` to watts with `gpu-cap-range`; write `run.env`; for `proton` launch `steam -applaunch <appid> <args>`, wait for a process matching `reaper` and `SteamLaunch AppId=<appid>` to appear (≤ 120 s, else `failed:start`) and disappear (≤ `timeout`, else kill and `failed:timeout`), move the newest MangoHud CSV to `frames.csv` and copy the newest Cyberpunk `summary.json` to `game.json`; for `native` run Factorio via `steam-run` as in `research.md` R6 into `ticks.csv`; for `settingsFile`, back up the prefix's `UserSettings.json`, journal its restore, install the prepared copy; write `state.json` before and after (fields in `data-model.md`), and set `excluded:state` when `after` does not match the variant
- [X] T018 [US1] In `modules/gaming/bench/default.nix` build `game-bench-priv`, `game-bench-wrap`, `game-bench-nogamemode`, `game-bench-summary` and `game-bench` (with `@config@` = `pkgs.writeText "game-bench.json" (builtins.toJSON { variants; workloads; })`, `@scx@` = `${pkgs.scx.full}/bin`, the Factorio save as `pkgs.fetchurl { url = "https://assets.factoriobench.com/maps/4c5f65003d84370f16d6950f639be1d6f92984f24c0240de6335d3e161705504.zip"; sha256 = "4c5f65003d84370f16d6950f639be1d6f92984f24c0240de6335d3e161705504"; }`, and the load command `nix build --rebuild --no-link '${loadPackage.drvPath}^out' --cores 0`); add all five to `environment.systemPackages` when `benchmark.enable`
- [X] T019 [US1] In `modules/gaming/default.nix` add `security.sudo.extraRules = [ { users = [ config.user.username ]; commands = [ { command = "${game-bench-priv}/bin/game-bench-priv"; options = [ "NOPASSWD" ]; } ]; } ]` under `mkIf (cfg.enable && cfg.benchmark.enable)`, and add `mangohud` to `programs.steam.extraPackages`

### Fast check

- [X] T020 [US1] Create `tests/game-bench.nix` (pattern: `tests/rtk-banner.nix`): run `game-bench-summary summarise` on the proton and native fixtures and assert row counts, the excluded run and the noise flag; run `compare` on the two `session.json` fixtures and assert the `versions differ: mesa` warning; run `game-bench-wrap env` with no lock, with a lock naming a dead PID, and with a live lock plus `run.env`, and assert `MANGOHUD` is set only in the last case; run `game-bench-nogamemode env` with `LD_PRELOAD="a.so libgamemodeauto.so.0 b.so"` and assert `a.so b.so`
- [X] T021 [US1] Wire `game-bench = nixpkgsFor.${system}.callPackage ./tests/game-bench.nix { … };` into `checks` in `flake.nix` (inside `onLinux`), passing the built scripts from the desktop configuration or building them standalone from `modules/gaming/bench/default.nix`
- [X] T022 [US1] `git add` new files, `nix fmt` (revert unrelated churn), `nix flake check`, build all four hosts
- [X] T023 [US1] **(user)** Deploy and run quickstart steps 4, 5 and 6; copy the real Factorio `ticks.csv` header into `tests/fixtures/game-bench/` and the parser if it differs from the placeholder; record probe outcomes (Cyberpunk exits by itself, Factorio without Steam client, Emacs rebuild parallelism) in `specs/008-game-performance-tuning/research.md` under the matching `[U]` entries

**Checkpoint**: US1 + US2 = MVP.

---

## Phase 5: User Story 3 - GameMode for every Steam game (Priority: P2)

**Goal**: Phase 1 part of US3: FR-016, FR-017.

**Independent Test**: quickstart step 3.

- [X] T024 [US3] In `modules/gaming/default.nix` set the Steam override's `extraEnv` to `{ PROTON_ENABLE_WAYLAND = "1"; LD_PRELOAD = "<extest lib> libgamemodeauto.so.0"; LD_LIBRARY_PATH = "<gamemode-lib 64>:<gamemode-lib 32>"; } // cfg.tunings.env`, taking the extest path from the same expression `nixos/modules/programs/steam.nix:57-67` uses (`pkgs.pkgsi686Linux.extest`) and the lib paths from `pkgs.gamemode.lib` and `pkgs.pkgsi686Linux.gamemode.lib`; comment why our `LD_PRELOAD` must repeat extest
- [X] T025 [US3] In `modules/gaming/default.nix` set `programs.gamemode.settings = { general = { renice = 10; ioprio = 0; softrealtime = "off"; }; cpu.park_cores = "no"; filter.blacklist = [ "steam" "steamwebhelper" "reaper" "pressure-vessel-wrap" "pv-adverb" "srt-bwrap" ]; }` and add `users.users.${config.user.username}.extraGroups = [ "gamemode" ]`
- [X] T026 [US3] (Done by fallback: the global preload broke the Steam client, so it was removed and FR-016 recorded as not met.) Build desktop, then **(user)** deploy and run quickstart step 3; extend `filter.blacklist` with any process `gamemodelist` shows while Steam is idle; if Steam's processes cannot be filtered, replace T024's preload with documented per-game `gamemoderun %command%`, and record FR-016 as not met in `spec.md` Clarifications

**Checkpoint**: GameMode active for games, inactive for idle Steam.

---

## Phase 6: User Story 4 - Kernel entries (Priority: P2)

**Goal**: Phase 1 part of US4: FR-022.

**Independent Test**: quickstart step 7.

- [X] T027 [US4] In `modules/gaming/kernel.nix`, under `mkIf (cfg.enable && cfg.kernelComparison.enable)`, add `specialisation.stock.configuration = { system.nixos.tags = [ "stock" ]; boot.kernelPackages = lib.mkForce stockPackages; }` where `stockPackages = pkgs.linuxKernel.packages."linux_${major}_${minor}"` from `lib.versions.major`/`minor` of `pkgs.linuxPackages_zen.kernel.version`
- [X] T028 [US4] In `modules/gaming/kernel.nix` assert that `config.boot.kernelPackages.kernel` is the Zen kernel (version string contains `zen`) and that `pkgs.linuxKernel.packages ? "linux_${major}_${minor}"`; messages name `common/system/system.nix` and `modules/gaming/kernel.nix`
- [X] T029 [US4] Add `{ modules.gaming.kernelComparison.enable = true; }` to `desktop` in `machines/machines.nix`; build desktop and confirm `nix eval '.#nixosConfigurations.desktop.config.specialisation.stock.configuration.boot.kernelPackages.kernel.version'` has Zen's major.minor
- [X] T030 [US4] **(user)** Deploy, boot the `stock` entry (hold Space at POST), run quickstart step 7

---

## Phase 7: User Story 5 - GPU power limit (Priority: P3)

**Goal**: power-limit variants work now (in US1's helper); the boot-time
option exists, inert, for Phase 2 (FR-026–FR-029).

**Independent Test**: quickstart step 6 "Out-of-range cap" and an
interrupt during a `cap-90` run.

- [X] T031 [US5] In `modules/gaming/gpu.nix`, under `mkIf (cfg.enable && cfg.gpu.powerCapWatts != null)`, add a `systemd.services.gpu-power-cap` oneshot (`wantedBy = [ "multi-user.target" ]`, after `systemd-udev-settle.service`) that calls `game-bench-priv gpu-cap <watts>` logic: find the hwmon named `amdgpu`, check range, write `watts × 1000000`, fail the unit without writing when out of range; comment that `null` means stock and deleting the setting reverts at next boot
- [X] T032 [US5] Build desktop with a temporary `modules.gaming.gpu.powerCapWatts = 250;` (do not commit), confirm the unit is generated, then remove it

---

## Phase 8: User Story 6 - Records (Priority: P3)

**Goal**: decision record skeleton and ADR (FR-021).

**Independent Test**: `docs/gaming-benchmarks.md` lists every variant with
an empty result row and the exact commands from quickstart step 8.

- [X] T033 [P] [US6] Create `docs/gaming-benchmarks.md` with a section per workload and kernel, a table per section (variant, runs, `p1`, `p01`, `avg`, power, verdict, rule), the commands from quickstart step 8, and a "Software versions" block to fill from `session.json`
- [X] T034 [P] [US6] Write `docs/adr/0009-game-benchmark-harness.md` (format of `docs/adr/0008-agent-context-hygiene.md`): the NOPASSWD rule for one validated root helper (R11), the same-series stock kernel specialisation and the stock-wins-ties rule (R8, FR-024), gamescope removal, and GameMode preload with blacklist (R7)
- [X] T035 [P] [US6] Add `Benchmark session`, `Variant` and `Workload` to `GLOSSARY.md` with the definitions from the spec

---

## Phase 9: Polish and Phase 2 hand-off

- [X] T036 Create the Phase 2 beads issues under the epic from T002: one "Run Phase 2 benchmark sessions (user)" issue with quickstart step 8 as its description, and six issues that each depend on it (`bd dep add`) — adopt per-game tunings (FR-018, FR-019), adopt CPU-side tunings, adopt a sched_ext scheduler (FR-018, FR-020), decide the default kernel and whether the losing entry stays (FR-024, FR-025), adopt a GPU power cap and profile (FR-027a, FR-028), fill `docs/gaming-benchmarks.md` (FR-021); each description quotes its adoption rule from `spec.md`
- [X] T037 Mirror any `AGENTS.md`/`CLAUDE.md` mention of gaming or gamescope (check with `rg -n -i 'gamescope|gaming' AGENTS.md CLAUDE.md`); update both if present
- [X] T038 Final gate: `nix fmt` (revert unrelated churn), `nix flake check`, build all four hosts, `git status` reviewed; close finished beads tasks; report staged changes to the user without committing

---

## Dependencies & Execution Order

### Phase dependencies

- Setup (Phase 1) → Foundational (Phase 2) → stories.
- US2 needs only Foundational. US1 needs Foundational.
- US3 needs US1's T013 (`game-bench-nogamemode`) and the T019 Steam
  package changes in the same file; do it after US1.
- US4 needs Foundational only; US4's T030 needs a deploy.
- US5 needs US1's T011 (the helper's cap logic, reused).
- US6 can run any time after Foundational.
- Phase 9 needs everything.

### Story dependency graph

```text
Setup ─> Foundational ─┬─> US2 ─────────────────────────┐
                       ├─> US1 ─┬─> US3 ────────────────┤
                       │        └─> US5 ────────────────┼─> Polish/hand-off
                       ├─> US4 ─────────────────────────┤
                       └─> US6 ─────────────────────────┘
```

### Within each story

Scripts before the Nix that wraps them; Nix before the check; build before
the **(user)** deploy step.

### Parallel opportunities

- T011, T012, T013, T014, T015: separate files.
- T033, T034, T035: separate files.
- US2, US4 and US6 in parallel once Foundational is done.

## Parallel Example: User Story 1

```text
T011 scripts/game-bench/game-bench-priv.sh
T012 scripts/game-bench/game-bench-wrap.sh
T013 scripts/game-bench/game-bench-nogamemode.sh
T014 scripts/game-bench/summary.py
T015 tests/fixtures/game-bench/*
then T016 → T017 → T018 → T019 → T020 → T021 → T022 → T023
```

## Implementation Strategy

### MVP

Setup, Foundational, US2 (gamescope gone), US1 (harness). Stop and run
quickstart steps 2, 4–6. This already lets the user measure everything.

### Incremental delivery

1. MVP.
2. US3: GameMode for all games (needs the step 3 probe).
3. US4: kernel entry; user can start kernel sessions.
4. US5, US6: inert power-cap option, records.
5. Phase 9: Phase 2 issues created; feature's Phase 1 done (FR-031).

## Notes

- Do not commit; stage and summarise (user's global rule).
- Each **(user)** step blocks only the tasks after it in the same story.
- Phase 2 work is tracked in beads, not in this file.
