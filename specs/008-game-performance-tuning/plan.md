# Implementation Plan: Game Performance Tuning and Benchmarking

**Branch**: `008-game-performance-tuning` | **Date**: 2026-10-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-game-performance-tuning/spec.md`

## Summary

Two phases (spec FR-030).

**Phase 1** is configuration and tooling in `modules/gaming/`, deployed to
`desktop` only:

- **Remove gamescope**: the `gamescope-game` launcher, `programs.gamescope`,
  `gamescopeSession` and `gamescope-wsi`.
- **GameMode for every Steam game**: preload `libgamemodeauto` in Steam's
  environment next to extest, keep Steam's own processes out with a GameMode
  blacklist, add the user to `gamemode`, set renice. One launch-option
  wrapper opts a game out.
- **Benchmark harness** `game-bench`: variants and workloads as typed Nix
  options, a launch-option wrapper, a validated root helper behind one
  NOPASSWD sudo rule, a restore journal, MangoHud and Factorio logging, a
  Python summariser and comparer.
- **Kernel A/B**: a `stock` specialisation with the stock kernel of Zen's
  series.
- **Records**: ADR 0009, GLOSSARY terms, one beads issue per Phase 2
  decision.

**Phase 2** runs after the user's sessions: adopt tunings through
`modules.gaming.tunings.env`, `services.scx`, `gpu.powerCapWatts` and the
default kernel, and write `docs/gaming-benchmarks.md`.

Research details: [research.md](research.md).

## Technical Context

**Language/Version**: Nix (flakes, nixpkgs unstable at `02c087f`), NixOS
modules; Bash via `writeShellApplication`; Python 3 (standard library) via
`writers.writePython3Bin`.

**Primary Dependencies**:

| Dependency                 | Role                                          |
| -------------------------- | --------------------------------------------- |
| `programs.steam`, Steam    | Game launch (`-applaunch`), FHS env           |
| `gamemode`                 | CPU governor, renice; client lib preload      |
| `mangohud`                 | Per-frame CSV logging, GPU power and clocks   |
| `scx.full` 1.1.4           | `scx_bpfland`, `scx_lavd`                     |
| `power-profiles-daemon`    | CPU profile variant (`powerprofilesctl`)      |
| `steam-run`                | Runs the native Factorio binary               |
| `util-linux`, `procps`, `jq` | `taskset`, `pgrep`, JSON state              |
| lanzaboote                 | Boot entry per specialisation                 |

**Storage**: files only. Runtime records under
`$XDG_DATA_HOME/game-bench/`, transient state under
`$XDG_RUNTIME_DIR/game-bench/` ([data-model.md](data-model.md)). The
committed decision record is `docs/gaming-benchmarks.md` (Phase 2).

**Testing**:

- New fast check `tests/game-bench.nix` (summary over fixture logs,
  comparison version warning, wrapper pass-through and stale-lock cases).
- Evaluation-time assertions on the options.
- `nix build` of all four hosts.
- Manual checks in [quickstart.md](quickstart.md), on `desktop`.

**Target Platform**: `desktop` (NixOS, Ryzen 9 9950X, RX 7900 XT, COSMIC,
lanzaboote). Other hosts evaluate unchanged.

**Project Type**: declarative system configuration plus a small CLI.

**Performance Goals**: harness overhead negligible next to the game; one
7 variants × 5 runs session finishes unattended (SC-001), roughly 3–4 h
for Cyberpunk with 60 s cool-downs.

**Constraints**:

- Pure evaluation; Factorio save pinned by hash.
- The agent sandbox cannot run sessions; validation of anything touching
  Steam, the GPU or sudo is the user's.
- Restore on every exit path (SC-002).
- No overdrive, voltage or clock offsets (FR-029).

**Scale/Scope**: one host; about 12 new or changed files; no new flake
inputs.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                         | How this plan complies                                                                                     | Status |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------ |
| I. Evaluation-time verification   | Variants, workloads, scheduler names, CPU lists, cap values are narrow typed options; assertions for exclusive fields, baseline, kernel series; shell via `writeShellApplication`, Python via `writePython3Bin`; executables by store path | Pass |
| II. Determinism                   | Factorio save is a hashed `fetchurl`; stock kernel derived from Zen's version at evaluation; load derivation pinned by `flake.lock`; no ambient state read at evaluation | Pass |
| III. Fast default gate            | `tests/game-bench.nix` is a small `runCommand` over fixtures; no VM, no game                                | Pass |
| IV. Single source of truth        | Variants defined once (FR-009); username from `config.user.username`; ADR 0009 for the sudo rule and kernel A/B; GLOSSARY terms | Pass |
| V. Toggleable modules             | Everything under `mkIf cfg.enable` in `modules/gaming/`; `kernelComparison` a toggle set in `machines.nix`; disabled module adds nothing | Pass |
| Destructive operations            | Root helper changes only runtime sysfs and units, journals every change, refuses invalid arguments          | Pass |

No violations; Complexity Tracking stays empty.

**Post-design re-check**: Pass. The design added the `gpuPowerCap = "max"`
keyword and a runtime range check, because the card's range is not known
at evaluation time; the helper refuses out-of-range values (US5 scenario 2).
This is the one runtime check that evaluation cannot replace, and it is
covered by a quickstart step.

## Project Structure

### Documentation (this feature)

```text
specs/008-game-performance-tuning/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── options.md
│   ├── game-bench-cli.md
│   ├── game-bench-wrap.md
│   └── game-bench-priv.md
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
modules/gaming/
├── default.nix           # options, Steam/GameMode/MangoHud, gamescope gone
├── kernel.nix            # kernelComparison specialisation (+ Phase 2 default swap)
├── gpu.nix               # Phase 2: power-cap oneshot
└── bench/
    ├── default.nix       # installs the packages, the sudo rule
    ├── packages.nix      # game-bench, -wrap, -nogamemode, -priv, -summary
    └── variants.nix      # default variants and workloads (FR-008, FR-008a)
scripts/game-bench/
├── game-bench.sh         # each pulled in by writeShellApplication
├── game-bench-wrap.sh
├── game-bench-nogamemode.sh
├── game-bench-priv.sh
└── summary.py            # summary + compare, via writePython3Bin
tests/
└── game-bench.nix        # fast check; generates its fixtures
docs/
├── adr/0009-game-benchmark-harness.md
└── gaming-benchmarks.md  # Phase 2 decision record
GLOSSARY.md               # Variant, Workload, Benchmark session
machines/machines.nix     # desktop: kernelComparison.enable
flake.nix                 # checks.game-bench
```

**Structure Decision**: everything lives in the existing `gaming` module,
split into files by concern because the module grows from 120 lines to a
harness. Script bodies live in `scripts/game-bench/`, as Principle I
requires for loose `.sh` files, and are wrapped by
`modules/gaming/bench/default.nix`.

## Design notes

**Steam environment** (R7): the gaming module's Steam override becomes

```nix
extraEnv = {
  PROTON_ENABLE_WAYLAND = "1";
  # extest first: our value replaces the module's (steam.nix:57-67).
  LD_PRELOAD = "${extestLib} libgamemodeauto.so.0";
  # 64- and 32-bit gamemode-lib dirs, the same pair gamemoderun adds.
  LD_LIBRARY_PATH = "${gamemodeLib64}:${gamemodeLib32}";
} // cfg.tunings.env;
```

The extest path is the one `steam.nix` builds, referenced from the same
package so it cannot drift. `programs.gamemode.settings.filter.blacklist`
lists Steam's own executables; the exact list is fixed by the quickstart
probe in step 3.

**Session loop**: as in [contracts/game-bench-cli.md](contracts/game-bench-cli.md).
`run.env` is written per run and parsed, never sourced, by the wrapper.

**Phase 2 hand-off**: Phase 1 ends by creating beads issues, each blocked
on a "run Phase 2 sessions" issue assigned to the user:

1. Adopt per-game tunings (`wayland-off`, `nggc`; FR-018/019).
2. Adopt a CPU-side tuning (GameMode settings, `ccd0`, `ppd-performance`).
3. Adopt a sched_ext scheduler, with or without system76-scheduler
   (FR-018/020).
4. Decide the default kernel (FR-024, FR-025), including whether the losing
   entry stays.
5. Adopt a GPU power cap (FR-027a/028) and GPU profile.
6. Write `docs/gaming-benchmarks.md` (FR-021, US6).

## Complexity Tracking

None.
