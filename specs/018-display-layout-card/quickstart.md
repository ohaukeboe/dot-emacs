# Quickstart: validate the displays card

## Prerequisites

- The laptop deployed (`sudo nixos-rebuild switch --flake .#laptop`), a
  Mango session.
- A second display that no display setup in `machines/machines.nix`
  knows, and one that a setup knows (the same display works: test before
  and after adding its setup).

## Gates

```bash
nix fmt && nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
just qs-check
```

The system build runs `qmlCheck` and `mango-display-layout-test`. Then
look at the card with the `verify-quickshell` skill.

## Scenarios

Open with `qs -c mango ipc call displays toggle` or "Displays" in the
launcher. "Read back" means `wlr-randr --json`.

| #   | Do                                     | Expect                              |
|-----|----------------------------------------|-------------------------------------|
| D1  | open with two displays                 | both drawn to scale, within 1 s     |
| D2  | drag one near the other's edge         | snaps; slides along the edge        |
| D3  | drop it on top of the other            | settles beside it, no overlap       |
| D4  | drop it far away                       | settles touching the other          |
| D5  | Apply, then Keep                       | pointer crosses as drawn            |
| D6  | change resolution, Apply, wait         | old mode back in 10 to 11 s         |
| D7  | change something, Apply, `Esc`         | reverted at once                    |
| D8  | turn off the card's display, Apply     | question on the other display       |
| D9  | scale 1.25, then 1.5, Apply, Keep      | read back matches the card          |
| D10 | rotate 90, Apply, Keep                 | rectangle and display both upright  |
| D11 | one display on: turn it off            | refused, with the reason            |
| D12 | nothing pending: `Enter`               | nothing; Apply looks unavailable    |
| D13 | unplug with changes pending            | new set shown; line says why        |
| D14 | unplug during the keep question        | question ends; no revert            |
| D15 | unknown display connected              | "No saved setup matches"            |
| D16 | Copy as setup, paste, rebuild, replug  | evaluates; same layout              |
| D17 | known setup connected, open            | its name is shown                   |
| D18 | adaptive sync on, Apply                | kept, or "refused" and unchanged    |
| D19 | open, change, `Esc`                    | closed; read back unchanged         |
| D20 | open another popup during the question | reverted                            |
| D21 | launcher: type `wdisplays`             | no entry; `Displays` opens the card |
| D22 | lid closed, docked: open the card      | panel drawn as off                  |

D6 covers SC-003; repeat it for position, scale, rotation and a display
turned off. D9 settles research R5, D15 settles R6.
