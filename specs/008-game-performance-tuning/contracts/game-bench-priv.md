# Contract: `game-bench-priv` root helper

Run as `sudo -n game-bench-priv <subcommand> [arg]`. Allowed by one
`security.sudo.extraRules` NOPASSWD entry for `config.user.username`, for
this exact store path (R11). Every write target is a fixed path inside the
helper; no argument is used as a path. Invalid arguments exit 2 with a
message and change nothing.

| Subcommand              | Argument                              | Effect                                 |
| ----------------------- | ------------------------------------- | -------------------------------------- |
| `check`                 | none                                  | Exit 0 (proves the sudo rule works)    |
| `scx-start`             | `scx_bpfland` \| `scx_lavd`           | Start scheduler as transient unit      |
| `scx-stop`              | none                                  | Stop the transient unit                |
| `s76-stop`, `s76-start` | none                                  | Stop/start `system76-scheduler`        |
| `zen-knobs`             | `on` \| `off` \| `status`             | Set/restore/print R9 knobs (stock)     |
| `gpu-profile`           | `3d-full-screen` \| `default`         | perf level `manual`+profile / `auto`   |
| `gpu-cap`               | watts \| `default`                    | Write `power1_cap`; range-checked      |
| `gpu-cap-range`         | none                                  | Print `min default max` in watts       |

Rules:

- `scx-start` runs `${pkgs.scx.full}/bin/<name>` via `systemd-run --unit
  game-bench-scx`, so it is stoppable and logged; it waits up to 5 s for
  `/sys/kernel/sched_ext/state` = `enabled` and exits 1 otherwise.
- `zen-knobs on` records the previous values in `/run/game-bench-priv/`
  and `off` restores exactly those. It refuses on the Zen kernel (booted
  system name without `-stock-`), since Zen already has the values.
- `gpu-cap <W>` finds the hwmon whose `name` is `amdgpu`, reads
  `power1_cap_min`/`_max`, and refuses values outside them (exit 2,
  spec US5 scenario 2). `default` writes `power1_cap_default`.
- `cpuProfile` does not go through the helper: `powerprofilesctl` works as
  the user.

The harness journals the undo subcommand before every apply subcommand.
