# ADR 0009: Game tuning by measurement: a benchmark harness with one passwordless root helper

**Status:** Accepted (2026-10-27).

## Context

`desktop` games through Steam on a Ryzen 9 9950X and a Radeon RX 7900 XT.
Research (`docs/gaming-performance-research.md` and the Zen kernel report
summarised in `specs/008-game-performance-tuning/spec.md`) found that
GameMode was enabled but never ran for Steam games, that no sched_ext
scheduler was loaded, and that no published benchmark shows the Zen kernel
beating the stock kernel beyond noise. Every candidate gain was a prior,
not a measurement. The user also no longer used gamescope, which caused
more problems than it fixed. See `specs/008-game-performance-tuning/` and
its `research.md`.

## Decision

**Tunings are adopted only on measured evidence.** `game-bench`
(`modules/gaming/bench/`, `scripts/game-bench/`) runs a game's built-in
benchmark repeatedly per variant, interleaved, and summarises 1% lows,
0.1% lows and averages with their spread. A tuning is kept only when its
median 1% low beats the run-to-run spread without regressing the other
metrics (spec FR-018). A lowered GPU power limit is kept when frame rates
stay within noise and power drops at least 10% (FR-027a).

**One root helper may run without a password.** `game-bench-priv` has a
fixed set of subcommands, validates every argument against a fixed set or
a digit pattern, and writes only paths hard-coded in it. A
`security.sudo.extraRules` entry lets `config.user.username` run that one
store path with `NOPASSWD`. This lets an unattended session switch
schedulers, GPU profiles and power limits between runs. The alternatives
were a `sudo -v` keepalive (prompts, and the timestamp can lapse during a
multi-hour session) and polkit actions (more files for the same effect).

**Every change is journalled before it is made.** The harness writes the
undo command to `$XDG_RUNTIME_DIR/game-bench/journal` and replays it on any
exit, and at the next start if a session died. The launch-option wrapper
applies settings only while the session's PID is alive, so a leftover file
never reaches a normal game launch. GPU power limits revert at reboot.

**The kernel is compared, not assumed.** `modules.gaming.kernelComparison`
adds a boot entry tagged `stock` with the stock kernel of the Zen kernel's
series, derived from Zen's version at evaluation time so the pair stays
matched. If Zen does not beat stock's 1% lows under background compile load
by more than the spread, stock becomes the default: it has the lower
maintenance cost (FR-024).

**GameMode is per game.** A game gets it with the launch option
`gamemoderun %command%`. Preloading `libgamemodeauto` for all of Steam was
tried and reverted: inside the Steam client it aborts on a D-Bus assertion
and the UI shows "Unexpected Transport Error".

**gamescope is removed:** the launcher, `programs.gamescope`, the Steam
gamescope session and `gamescope-wsi`.

## Consequences

- The NOPASSWD rule widens what the user account can do as root to the
  helper's subcommands: stopping system76-scheduler, loading a sched_ext
  scheduler, changing scheduler and I/O knobs on the stock kernel, and
  setting the GPU power limit within the firmware's range. Overdrive,
  voltages and clocks were out of reach (FR-029); ADR 0010 later allowed a
  voltage offset below stock (an undervolt) with overdrive enabled.
- GameMode needs a launch option per game, so the spec's "every game with
  no launch options" (FR-016) is not met.
- `game-bench` drives Steam, the GPU and sudo, so the agent sandbox cannot
  run it. Only its summary and wrappers are covered by `checks.game-bench`.
- Decisions and their numbers live in `docs/gaming-benchmarks.md`. A new
  driver, Proton or kernel can change them; the record holds the commands
  to re-run.
