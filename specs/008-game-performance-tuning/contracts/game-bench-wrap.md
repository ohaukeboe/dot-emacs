# Contract: Steam launch-option wrappers

## `game-bench-wrap %command%`

Set once per benchmarked game in Steam → Properties → Launch Options.

- If `$XDG_RUNTIME_DIR/game-bench/lock` is missing, or its PID is not alive,
  or `run.env` is missing: `exec "$@"` unchanged (FR-006). No logging, no
  environment changes.
- Otherwise read `run.env`, which sets only these keys:

  | Key             | Effect                                                   |
  | --------------- | -------------------------------------------------------- |
  | `GB_ENV`        | `NAME=value` lines exported before exec                  |
  | `GB_CPUS`       | prefix `taskset -c <cpus>`                               |
  | `GB_GAMEMODE`   | `1`: prefix `gamemoderun`                                |
  | `GB_MANGOHUD`   | `MANGOHUD_CONFIG` string; also sets `MANGOHUD=1`         |

  `run.env` is parsed line by line as `KEY=value`, never sourced. Unknown
  keys are ignored.
- `exec` the composed command. The wrapper adds no process of its own.

## GameMode

Per game, with the launch option `gamemoderun %command%` (or both:
`gamemoderun game-bench-wrap %command%`). A global preload breaks the Steam
client; see research.md R7.

## Phase 2 opt-outs

Each adopted per-game tuning in `modules.gaming.tunings.env` is opted out
for one game with the launch option `NAME=<stock value> %command%`, for
example `PROTON_ENABLE_WAYLAND=0 %command%` (FR-019). The decision record
lists the exact opt-out for each adopted tuning.
