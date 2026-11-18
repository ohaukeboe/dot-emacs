# Quickstart: validate the Quickshell rail

## Before the change

Take a screenshot of the rail on the laptop panel for SC-001. Use `grim -g`
on the top 60 px, with a window on tags 1 and 3, tag 1 active, and a tray app
running.

## Build

```bash
git add -A specs/014-quickshell-rail modules/mango
nix fmt
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'   # runs qmllint
sudo nixos-rebuild switch --flake .#laptop
```

The switch restarts `quickshell.service`, because its restart trigger
changed. Waybar's unit is gone; if a waybar process from the old generation
is still running, log out and back in.

## Checks

| #  | Do                                                 | Expect                       |
|----|----------------------------------------------------|------------------------------|
| 1  | `pgrep -a waybar`                                  | No output (US1-2, SC-004)    |
| 2  | Compare the rail with the before screenshot        | No visible difference        |
|    |                                                    | (SC-001)                     |
| 3  | Windows on tags 1, 3 and 5, tag 3 active           | dot, pill "3", dot (US2-1)   |
| 4  | Click each dot                                     | Tag switches (US2-2)         |
| 5  | `SUPER+1`…`SUPER+5` quickly                        | Pill follows with no lag     |
|    |                                                    | (SC-003)                     |
| 6  | Make a window on another tag request attention     | Ring on its dot until        |
|    | (a terminal bell with urgency on)                  | visited (US2-4)              |
| 7  | Click clock, usage ring and each controls icon     | Popup under that capsule;    |
|    |                                                    | open state shown (US3)       |
| 8  | Escape, click outside, click the opener again      | Closes, open state clears    |
| 9  | `qs -c mango ipc call controls toggle`             | Opens at the right edge      |
|    |                                                    | (FR-016)                     |
| 10 | Chevron, then left and right click a tray icon     | Reveal, activate, menu works |
| 11 | Hover network, sound, battery and usage            | Tooltips as before (US3-9)   |
| 12 | Turn the phone's Wi-Fi off, then on                | Phone icon hides, shows      |
| 13 | Plug in an external monitor                        | Second rail with its tags    |
|    |                                                    | (US1-3, US1-4)               |
| 14 | `mmsg dispatch reload_config`                      | Tags correct within 2 s      |
|    |                                                    | (SC-006)                     |
| 15 | `systemctl --user restart quickshell`              | Rail back within 2 s         |
| 16 | `git diff --stat main -- modules/mango`            | Net negative lines (SC-005)  |

For check 2, compare at least: island height and gaps, dot and pill sizes,
the clock's date colour, the ring thickness, and the hover tint on each item.
