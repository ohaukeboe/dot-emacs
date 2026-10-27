# Contract: `game-bench` CLI

User-facing command, run from a terminal in the graphical session.
Installed only when `modules.gaming.benchmark.enable` (FR-010).

```text
game-bench run     [-w WORKLOAD] [-v "V1 V2 ..."] [-n RUNS] [--load] [--cool SECS]
game-bench compare SESSION_DIR SESSION_DIR [...]
game-bench build-time [-n RUNS]
game-bench restore
game-bench list
```

## `run`

| Flag     | Default                              | Meaning                              |
| -------- | ------------------------------------ | ------------------------------------ |
| `-w`     | `cyberpunk`                          | Workload name                        |
| `-v`     | all variants applicable to workload  | Space-separated variant names        |
| `-n`     | `5`                                  | Runs per variant (FR-002)            |
| `--load` | off                                  | Run background load throughout       |
| `--cool` | `60`                                 | Seconds between runs                 |

Behaviour, in order:

1. Refuse if another session's lock PID is alive. Replay a leftover
   journal from a dead session first.
2. Check `sudo -n game-bench-priv check` when any chosen variant needs root;
   on failure exit 2 before any change.
3. Drop variants not applicable to the workload's kind, and print them as
   "n/a" (FR-008b). Unknown names exit 2.
4. Write `session.json`. Start the load loop if `--load`.
5. One warm-up run with `baseline`, discarded.
6. For `i` in 1..N, for each variant: restore, apply, write `run.env`,
   launch, wait (timeout), collect, snapshot state, cool down.
7. Summarise (`summary.tsv`, `summary.txt`), print `summary.txt`.
8. On exit, interrupt (INT, TERM, HUP) or error: stop the load, kill the
   game, replay the journal, remove `run.env` and `lock`.

Exit codes: `0` done; `1` finished with failed runs; `2` refused to start;
`130` interrupted (restore still ran).

Output: the session directory path on the first line, then progress lines
`[i/N] <variant>: <status> <avg>/<p1>`.

## `compare`

Reads `session.json` and `summary.tsv` from each directory. Prints one table
per workload: session label (`<kernel tag>/<load|idle>`), variant, runs,
median and spread of `p1`, `p01`, `avg`. Prints `WARNING: versions differ:
<field>...` when any `versions` field other than the kernel differs.

## `build-time`

Rebuilds `loadPackage` N times (default 5) with `--rebuild`, prints median
and spread in seconds, and appends them to
`$XDG_DATA_HOME/game-bench/build-time.tsv` with the booted system and the
active scheduler (FR-013).

## `restore`

Replays and clears the journal. Safe to run any time.

## `list`

Prints the variants and workloads with their descriptions and kinds.
