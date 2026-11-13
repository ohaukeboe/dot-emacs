# Quickstart: Mango Rail Bar

Validation guide. Layout and states: [data-model.md](data-model.md); IPC:
[contracts/popup-ipc.md](contracts/popup-ipc.md).

## Build

```bash
git add -A specs/012-mango-rail-bar modules/mango
nix fmt                       # revert unrelated churn
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

Expected: build passes, including the `qmllint` check (research R9). A typo
in the QML or a leftover `@placeholder@` fails the build.

## On the laptop

Deploy (`sudo nixos-rebuild switch --flake .#laptop`), log in to Mango.

1. **Rail** (US1): the left rail is at most 32 px wide, frame-coloured, no
   seam. Open three windows on tags 1, 2 and 5, stay on 2: two grey dots and
   an accent pill "2"; tags 3, 4, 6–9 are not shown. Click a dot: that tag
   becomes active.
2. **Clock** (US1): hour over minutes, 24-hour. Click it: a month calendar
   opens next to the rail; Escape closes it.
3. **Status icons** (US2): no text runs along the rail. Hover the network
   icon: SSID shown. Mute audio (`XF86AudioMute`): sound icon changes.
4. **Battery warning** (FR-010): unplug and wait for ≤ 15 %, or check the
   CSS class with `GTK_DEBUG=interactive waybar` — the battery icon turns
   the warning colour only while discharging.
5. **Quick controls** (US2, FR-012): click the gear at the bottom. Move the
   volume and brightness sliders (popup stays open), toggle mic mute, Wi-Fi,
   Bluetooth, cycle power profile, read battery. Click outside: closes.
   Reopen, press Escape: closes. Reopen, click Power: power menu appears.
6. **Docked** (edge cases, R5): with an external display, every display has a
   rail and each marks its own active tag. Click the gear on the external
   rail: the popup opens on that display, not on the panel.
7. **Tray** (US3): with KDE Connect and blueman running, one chevron shows;
   click it: tray icons appear and their menus open.
8. **COSMIC** (FR-014): log in to COSMIC; no waybar, no Quickshell popups.
9. **Detail pages** (US2/AC5–AC7, FR-015, FR-016): open the gear.
   - Wi-Fi `›`: networks list; pick an unsaved secured one, type its
     password inline, Enter: it connects. `‹` returns to the tiles.
   - Bluetooth `›`: paired devices show; click one to connect or
     disconnect. Scan, pick a new device: it pairs, then connects.
   - Volume `›`: pick another output and input; play sound in two apps:
     each has its own slider and Mute. Close and reopen: tiles show.
