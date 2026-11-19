# Quickstart: validate duplicate display

## Prerequisites

- The laptop deployed (`sudo nixos-rebuild switch --flake .#laptop`), a
  Mango session, one external display; a second external display for M8
  to M11.
- The desktop machine (no panel) for M16.

## Gates

```bash
nix fmt && nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
just qs-check
```

The system build runs `qmlCheck`, shellcheck on `mango-copy-guard` and
`mango-display-layout-test`. Then look at the card with the
`verify-quickshell` skill.

## Scenarios

Open with `qs -c mango ipc call displays toggle`. "Read back" means
`wlr-randr --json`. The rules are in
[contracts/displays.md](contracts/displays.md).

| #   | Do                                         | Expect                             |
|-----|--------------------------------------------|------------------------------------|
| M1  | two displays: open, `Right`, `Enter` twice | external shows the panel           |
| M2  | read back                                  | external at the panel's x, y 8192  |
| M3  | play a 60 fps video on the source          | smooth on the copy; note the rate  |
| M4  | push the pointer past every panel edge     | it stays on the panel              |
| M5  | start an X11 program                       | it opens and draws on the source   |
| M6  | `Super+.` several times                    | focus never rests on the copy      |
| M7  | open, `Left`, `Enter` twice                | extended again; windows reachable  |
| M8  | three displays: drag one onto another      | target marked; a stack on release  |
| M9  | Apply, Keep; `Super+.`                     | third display still reached        |
| M10 | select the copy, "Make source", Apply      | roles swapped; stack stayed put    |
| M11 | select the copy, "Separate", Apply         | own desktop, beside the others     |
| M12 | duplicated: `mango-lock`                   | lock screen on every display       |
| M13 | duplicated: unplug the source              | copy has a desktop within 5 s      |
| M14 | duplicated, docked: close the lid          | external has the desktop in 5 s    |
| M15 | Duplicate, Apply, wait 10 s                | back to before; mirror gone        |
| M16 | desktop machine: open                      | only Extend and Duplicate offered  |
| M17 | one display connected: open                | no switch                          |
| M18 | duplicated: Copy as setup, paste           | no y of 8192; note in the card     |
| M19 | duplicated: restart the shell              | mirror back; card shows a stack    |
| M20 | duplicated: replug a known display         | setup applied; duplicate ended     |
| M21 | window on the external, then M1            | the window is on the panel         |
| M22 | copy of another shape                      | whole picture, bars, not stretched |
| M23 | rotate the copy 90, Apply                  | picture upright on the turned copy |
| M24 | hand-made stack, then pick Extend          | stack gone; no choice was marked   |

M3 settles research R2 and the number in SC-003. M4 and M5 settle R3. M6
and M9 settle R5. M13 and M14 settle R7. If M3 is not smooth, compare
with `wl-mirror` on the same displays before changing the design:

```bash
nix-shell -p wl-mirror --run 'wl-mirror --fullscreen-output <copy> <source>'
```
