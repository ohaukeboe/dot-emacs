# Gaming benchmarks on `desktop`

Decision record for `specs/008-game-performance-tuning` (FR-021, US6). Each
section holds the summary rows of one `game-bench` session, the software
versions it ran with, and the keep or drop verdict for each variant with the
rule that decided it. Raw logs stay in `~/.local/share/game-bench/`.

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

Status: **no sessions run yet** (Phase 2, beads epic `dot-emacs-t21`).

## How the sessions are run

On each boot entry (default Zen, and `stock`), idle and with `--load`:

```bash
game-bench run -w factorio
game-bench run -w cyberpunk-720p
game-bench run -w cyberpunk -v "baseline wayland-off nggc gpu-3dfs cap-max cap-95 cap-90"
game-bench build-time
game-bench compare ~/.local/share/game-bench/<zen-session> ~/.local/share/game-bench/<stock-session>
```

## Software versions

| Field        | Value |
| ------------ | ----- |
| Kernel (Zen) |       |
| Kernel stock |       |
| Mesa         |       |
| Proton       |       |
| Cyberpunk    |       |
| Factorio     |       |

## CPU-side variants (Factorio, Cyberpunk 720p)

| Variant            | Kernel | Load | p1  | p0.1 | avg | Verdict | Rule   |
| ------------------ | ------ | ---- | --- | ---- | --- | ------- | ------ |
| baseline           |        |      |     |      |     |         |        |
| gamemode           |        |      |     |      |     |         | FR-018 |
| ppd-performance    |        |      |     |      |     |         | FR-018 |
| ccd0               |        |      |     |      |     |         | FR-018 |
| scx-bpfland        |        |      |     |      |     |         | FR-018 |
| scx-lavd           |        |      |     |      |     |         | FR-018 |
| scx-bpfland-no-s76 |        |      |     |      |     |         | FR-018 |
| scx-lavd-no-s76    |        |      |     |      |     |         | FR-018 |
| zen-knobs          | stock  |      |     |      |     |         | FR-018 |

## GPU-side variants (Cyberpunk, normal settings)

| Variant     | p1  | p0.1 | avg | Power W | Verdict | Rule    |
| ----------- | --- | ---- | --- | ------- | ------- | ------- |
| baseline    |     |      |     |         |         |         |
| wayland-off |     |      |     |         |         | FR-018  |
| nggc        |     |      |     |         |         | FR-018  |
| gpu-3dfs    |     |      |     |         |         | FR-018  |
| cap-max     |     |      |     |         |         | FR-018  |
| cap-95      |     |      |     |         |         | FR-027a |
| cap-90      |     |      |     |         |         | FR-027a |

## Kernel

| Kernel | Load | p1  | p0.1 | avg | Build time | Verdict | Rule   |
| ------ | ---- | --- | ---- | --- | ---------- | ------- | ------ |
| Zen    | idle |     |      |     |            |         |        |
| Zen    | load |     |      |     |            |         | FR-024 |
| stock  | idle |     |      |     |            |         |        |
| stock  | load |     |      |     |            |         | FR-024 |

If Zen loses: the `stock` entry becomes the default; record here whether the
Zen entry stays for later re-tests.

## Adopted tunings and opt-outs

| Tuning | Where it is set | Per-game opt-out |
| ------ | --------------- | ---------------- |
|        |                 |                  |
