# Quickstart: validate Mango docking and session essentials

## Build gate (no deploy)

```bash
git add -A specs/011-mango-docking-essentials modules/mango
nix fmt          # revert unrelated churn
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
for m in desktop work-laptop dig-laptop; do
  nix build ".#nixosConfigurations.$m.config.system.build.toplevel" --dry-run
done
```

Expected: all pass. The toplevel build runs `mango -p` on the generated
config and the portal-key check (R8).

Assertion probes (each must fail evaluation with the contract's message):
add a setup named `undocked`; add a setup with two outputs sharing
`criteria`; add a setup whose only output has `enable = false`.

Other machines (SC-008): compare `toplevel` out paths of `desktop`,
`work-laptop`, `dig-laptop` before and after; they must be identical.

## Deploy

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Log out and in to Mango (group `video` and udev rules need a new login).

## D. Docking (US1–US3)

1. **Unknown display**: plug in any external display. Within 5 s it shows the
   wallpaper and a bar, right of the panel; panel stays on (SC-002).
2. **Display tool**: open `wdisplays` from fuzzel, move the display left of
   the panel, apply. Unplug, replug: it is back on the right (R6).
3. **Record a setup**: while docked, run `mango-display-setup`; paste its
   output into `machines/machines.nix` under `laptop`, rebuild, re-login.
   Unplug and replug: the recorded arrangement returns within 5 s, 10 times
   out of 10 (SC-001, SC-004).
4. **Undock**: with windows on the external display, unplug. All windows are
   on the panel; panel at `0,0` (SC-007).
5. **Lid**: docked, close the lid: panel off, session keeps running on the
   external display. Unplug the external display with the lid still closed:
   the laptop suspends. If it does not, apply R4's fallback.
6. **Lock**: lock, then plug in a display: it shows the lock screen.
7. **Reload**: docked with the lid closed, press `Super+r`: panel stays off.

## G. Session gaps (US4, SC-005)

1. Screenshot from Firefox (`about:screenshots` or the portal test page
   <https://flatpak.github.io/xdg-desktop-portal/>): works.
2. Start a screen share in a browser with two displays: click one; it is
   shared.
3. Copy text in an app, close the app, paste: text is there.
4. Volume and brightness keys: an OSD popup shows the level.
5. Tray: blueman applet pairs a device; clicking the volume module opens
   pwvucontrol and switches output.
6. `Super+Shift+Escape`: power menu; pick lock.

## A. Annotation (US6)

`Ctrl+Print`, select a region, draw an arrow, copy, paste into a chat.
`Shift+Print` still saves without the editor.

## T. Theming (US5, SC-006)

With `modules.cosmic-de.enable = false` set temporarily on `laptop`:

```bash
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

must succeed. In a test boot (or VM), open `gtk3-demo`, `gtk4-demo` or
Nautilus, and a Qt app: all dark, same cursor. Revert the toggle afterwards.
