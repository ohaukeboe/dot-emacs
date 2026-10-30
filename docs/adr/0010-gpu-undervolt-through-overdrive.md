# ADR 0010: GPU undervolt through amdgpu overdrive, as a measured variant

**Status:** Accepted (2026-10-30). Amends spec 008 FR-029 and the
"Overdrive … out of reach" consequence of ADR 0009.

## Context

`desktop`'s RX 7900 XT is power-limited in GPU-bound games: at 4K with ray
tracing it sits at its limit, and raising the limit from 265 W to the
vBIOS maximum of 290 W gave +2.3% 1% lows (`docs/gaming-benchmarks.md`). A
lower voltage at each clock lowers power at that clock, so the card can
hold higher clocks inside the same limit
(`docs/gpu-performance-research.md`, section 1). On Navi 31 the driver
exposes one voltage offset for the whole V/F curve (`OD_VDDGFX_OFFSET`),
but only with the overdrive bit set in `amdgpu.ppfeaturemask`. Spec 008
FR-029 had ruled out changing voltages, and ADR 0009 kept overdrive out of
the root helper's reach. The user asked to measure an undervolt.

## Decision

**Overdrive is enabled on `desktop`, changing only its bit.**
`modules.gaming.gpu.overdrive.enable` sets `hardware.amdgpu.overdrive` with
`ppfeaturemask = "0xfff7ffff"`: the kernel default plus `0x4000`. The
nixpkgs default mask (`0xfffd7fff`) would also turn GFXOFF and stutter mode
off and GFX_DCS on, which would change the baseline.

**The root helper may lower the voltage, never raise it.**
`game-bench-priv gpu-undervolt <mV>` accepts `0`–`200` and writes `vo -<mV>`
and `c` to `pp_od_clk_voltage`. Clock offsets and positive voltage offsets
stay out of reach. The harness journals the offset in force before a
variant and restores it after every run.

**An undervolt is adopted only on measured evidence**, like every other
tuning (FR-018), and only after a soak test outside the harness: a deep
offset can pass a 60-second benchmark and still crash another game.
Variants `uv-50`, `uv-75` and `uv-50-cap-max` are n/a while overdrive is
off. A run during which amdgpu logs a ring timeout or GPU reset is
`failed:gpu-hang`, and the variant's remaining runs are skipped. A run
whose offset was cleared some other way is excluded (`excluded:state`).

## Consequences

- The kernel is tainted (`TAINT_CPU_OUT_OF_SPEC`) on every boot of
  `desktop`, and amdgpu logs that overdrive bugs should be reported with it
  disabled. Enabling the bit alone changes no clock or voltage.
- With overdrive on, `power1_cap_max` may rise above 290 W by the board's
  overdrive percentage, so `cap-max` measures a different limit than in the
  sessions of 2026-10-28/29.
- An offset written by the helper is lost at reboot or driver reset, which
  is the recovery path for a bad value. The adopted offset
  (`modules.gaming.gpu.undervoltMv`) is set at boot by `gpu-undervolt`,
  ordered after `gpu-power-cap`; a driver reset leaves it off until the
  next boot.
- A full GPU reset ends the desktop session, and a `game-bench` started
  from a terminal in it. On 2026-10-30, -100 mV did this in Cyberpunk;
  the next attempt hung only the game's ring, which left the game frozen
  until the hang check was added. `uv-100` became `uv-75`.
- A power limit above the board's own maximum (290 W) is sent to the SMU
  in the overdrive table, and setting one after the offset appeared to
  drop the offset: `uv-50-300w` ran 74 MHz slower than `uv-50` at 290 W,
  while `pp_od_clk_voltage` still read -50 mV. The harness sets the
  offset after the limit. A boot-time undervolt must do the same.
- Each Proton run now writes `gpu.csv` (power, clocks, temperatures, fan,
  load), so throttling and clock gains are visible per run.
