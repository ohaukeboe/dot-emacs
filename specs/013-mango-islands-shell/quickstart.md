# Quickstart: Validating the Mango Islands Shell

Reference: the design canvas named in `spec.md`. Contracts:
[popup-ipc](contracts/popup-ipc.md), [usage-record](contracts/usage-record.md).

## Build gate (every change)

```bash
git add -A modules/mango workstation/agents tests
nix fmt
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

`nix flake check` runs the status-line and collector tests (`checks.context-statusline`,
`checks.agent-usage`).

The toplevel build runs `qmllint` over the Quickshell directory and fails on
a missing palette key or placeholder.

`qmllint` does not catch every load error. Inside the Mango session, run
`just qs-check` before deploying: it loads the built config for a few
seconds next to the running one and fails on any QML error.

## Deploy

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Quickshell and waybar restart by themselves when their config changed.

## Story 1: islands look

1. Three capsules on the top edge; the frame around them is darker than
   foot and Emacs.
2. Click the clock: calendar under the clock capsule, clock shows the raised
   fill, no outline anywhere.
3. Click the Wi-Fi icon: capsule sliders, three rows with round toggles, segmented
   power profile, footer with lock and power.
4. Open the Wi-Fi, Bluetooth and sound pages; all controls from spec 012
   still work.
5. `grep -nE '#?[0-9a-f]{6}' modules/mango -r` shows colours only in the
   `palette` definition.
6. Plug in a second monitor; popups open on the monitor that was clicked.

## Story 2: Claude usage

1. Run `claude` once, send a message, then
   `cat ~/.local/state/agent-usage/limits.json`: both limits present.
2. The pill shows the same session percentage as `/usage` in Claude Code.
3. Click the pill: two meters with reset times, "By day" rows
   with today last, weekly total.
4. Switch to "By model"; click refresh and watch "updated" reset.
5. "Open Claude" opens foot running `claude`.
6. Move `limits.json` away: the pill disappears within a refresh. Put it back.
7. `journalctl --user -u agent-usage -n 20` contains no token or credential.

## Story 3 and 4: KDE Connect

1. Phone on the same network: phone icon on the rail; quick controls show
   the card with the phone's real battery.
2. Ring, Clipboard, Send file and Browse each work once.
3. Arrow opens the detail page; notifications match the phone; dismiss one;
   "Clear all" empties the list on the phone.
4. Turn the phone's Wi-Fi off: card says "Not reachable", actions disabled,
   rail icon gone.
5. No tray entry for KDE Connect remains.

## Off cases (SC-006)

- `agents.usage.enable = false` and no state files: no pill, no errors in
  `journalctl --user -u quickshell`.
- KDE Connect disabled in the module: no card, no page, no rail icon, and
  the toplevel still builds.
- COSMIC session: unchanged.
