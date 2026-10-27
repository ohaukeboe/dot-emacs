# Quickstart: validate Game Performance Tuning and Benchmarking

Validation guide for both phases. Commands that touch Steam, the GPU or
sudo run in the user's own terminal on `desktop`, not in the agent sandbox
(spec Assumptions). Contracts: [options](contracts/options.md),
[CLI](contracts/game-bench-cli.md), [wrappers](contracts/game-bench-wrap.md),
[root helper](contracts/game-bench-priv.md).

## 0. Build gate (agent or user)

```bash
git add -A specs/008-game-performance-tuning modules/gaming tests
nix fmt
nix flake check                      # includes the new game-bench check
for h in desktop laptop work-laptop dig-laptop; do
  nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --no-link
done
```

Expected: all pass. Only `desktop`'s closure changes (Principle V).

## 1. Deploy (user)

```bash
sudo nixos-rebuild switch --flake .#desktop
```

## 2. gamescope removed (US2, SC-004)

```bash
command -v gamescope gamescope-game          # prints nothing, exit 1
ls /run/current-system/sw/share/wayland-sessions/ | grep -i steam  # nothing
rg -n gamescope --glob '*.nix' --glob '*.org' .  # no matches
```

Start Steam and one game; Steam Input works under Wayland (US2 scenario 3).

## 3. GameMode per game (US3, SC-005, R7)

The global preload broke the Steam client ("Unexpected Transport Error"),
so GameMode is per game and FR-016 is not met.

1. With Steam open and idle: `gamemoded -s` reports **inactive**.
2. Start a game with launch options `gamemoderun %command%`:
   `gamemoded -s` reports **active**; `gamemodelist` shows the game; `id`
   lists `gamemode`.
3. Quit the game: `gamemoded -s` is inactive again and
   `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` is back to
   `powersave`.
4. Start a game with empty launch options: GameMode stays inactive.

## 4. One-time workload setup (user)

1. Steam launch options for Cyberpunk 2077:
   `game-bench-wrap %command%`.
2. In Cyberpunk, set Window Mode **Windowed**, 1280×720, quick preset Low,
   ray tracing and frame generation off, quit, and copy the prefix's `UserSettings.json` to
   `~/.local/share/game-bench/cyberpunk-720p.json`. Restore normal settings
   in the game. Fullscreen does not work: under Proton's Wayland driver
   the game renders at the monitor's resolution whatever the file says
   (seen 2026-10-27: `renderWidth` 3840 in `game.json`).
3. Factorio installed through Steam.

## 5. Probes for unverified research (R4–R7, R12)

| Probe                                                     | Expect                                |
| --------------------------------------------------------- | ------------------------------------- |
| `steam -applaunch 1091500 --launcher-skip -benchmark -skipStartScreen` | benchmark starts, game exits by itself |
| `game-bench run -w factorio -v baseline -n 1`             | ticks logged with no Steam client open |
| first Factorio `ticks.csv` header                         | copy into `tests/fixtures/` (R6)       |
| `game-bench build-time -n 1` while `htop` runs            | most of 32 threads busy (R12)          |

If Cyberpunk does not exit by itself, the run ends at its timeout with
`failed:timeout`; raise the issue before trusting the session.

## 6. Harness smoke test (US1, SC-001, SC-002)

```bash
game-bench run -w cyberpunk -v "baseline gamemode" -n 3
```

Expected:

- No password prompt.
- Output directory with `baseline/1..3` and `gamemode/1..3`, each with
  `frames.csv`, `state.json`, `status`.
- `summary.txt` with two rows, 3 valid runs each.
- After the session: `cat /sys/kernel/sched_ext/state` = `disabled`,
  PPD profile `balanced`, GPU `power1_cap` = default, `systemctl is-active
  system76-scheduler` = `active`, `$XDG_RUNTIME_DIR/game-bench/journal`
  empty.

Interrupt test: start a 2-variant session using `scx-lavd` and `cap-90`,
press Ctrl-C during a run. The same checks pass, exit code 130.

Stale-file test: `kill -9` a session, then start the game normally from
Steam. MangoHud does not log and no variant applies (FR-006). The next
`game-bench run` replays the journal first.

Out-of-range cap: `sudo -n game-bench-priv gpu-cap 400` exits 2 and the cap
is unchanged (US5 scenario 2).

## 7. Kernel entries (US4, FR-022)

Reboot, hold Space, choose the entry tagged `stock`. Then:

```bash
readlink /run/booted-system   # name contains -stock-
uname -r                      # same major.minor as the Zen entry, no "zen"
```

## 8. Phase 2 sessions (user; feeds the beads issues)

Each on both kernel entries, with and without `--load`:

```bash
game-bench run -w factorio
game-bench run -w cyberpunk-720p
game-bench run -w cyberpunk -v "baseline wayland-off nggc gpu-3dfs cap-max cap-95 cap-90"
game-bench build-time
game-bench compare ~/.local/share/game-bench/<zen-session> ~/.local/share/game-bench/<stock-session>
```

Decisions follow FR-018, FR-024 and FR-027a, and are written to
`docs/gaming-benchmarks.md` with the commands above.
