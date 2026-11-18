# Quickstart: validating Proton Pass Quick Access

## Prerequisites

- `cosmic-pass` with `serve` merged, and `nix flake update cosmic-pass` run
  here.
- A machine with `modules.mango.enable = true`, in the Mango session.
- `pass-cli` signed in (`pass-cli login`), keyring unlocked.

## Build gates (no session needed)

```bash
nix fmt
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

The toplevel build runs `qmlCheck`; any qmllint warning in `Pass.qml` or
`PassPopup.qml` fails it. A value outside 10..600 for
`modules.mango.pass.clipboardClearSeconds` must fail evaluation; try 5 once.

Then, in the session, before deploying:

```bash
just qs-check
```

## Backend alone

```bash
cosmic-pass serve --clipboard-clear-secs 90
```

A snapshot line appears at once. Type `{"t":"show"}` then
`{"t":"query","text":"<part of a title>"}`: each prints a snapshot whose
`rows` match. Ctrl+D exits 0. Shapes: `contracts/serve-protocol.md`.

## In the session

Deploy with `sudo nixos-rebuild switch --flake .#laptop`. Use the
`verify-quickshell` skill for screenshots of V1, V3 and V5.

- **V1 (story 1)**: `Super+Space`, type part of a title, `Enter`. The popup
  closes, focus returns, paste gives the password.
- **V2 (SC-004, SC-005)**: the clipboard history picker does not list it.
  After 95 seconds paste gives nothing. Repeat, copy something else within
  the 90 seconds: that stays.
- **V3 (story 2)**: `Super+Space`, select a login with a one-time code,
  `Tab`, move to the code, `Enter`. The site accepts the pasted code. `Tab`
  again, `Esc`: the item list is back with the same query.
- **V4 (story 4)**: in the field list, `Ctrl+R` on the password shows it;
  `Ctrl+R`, moving, `Esc` or closing hides it. On a one-time code the shown
  code changes when its period ends.
- **V5 (story 3)**: `pass-cli logout`, `Super+Space`: "Signed out" and Sign
  in. `Enter`: the browser opens the sign-in page, lines appear. Finish:
  items are listed without restarting anything.
- **V6 (story 3)**: disconnect the network, `Super+Space`: the saved items
  and the out-of-date line. `F5` keeps them.
- **V7 (FR-001)**: the launcher still starts the Proton Pass application;
  `Super+Space` does not.
- **V8 (SC-002)**: `systemctl --user restart quickshell`, then at once
  `Super+Space`: the popup opens within half a second and shows "Loading
  items…" or the items.
- **V9 (research R6)**: with `modules.cosmic-de` also on,
  `systemctl --user status cosmic-pass` in the Mango session reports the
  condition failed, and `pgrep -fc 'cosmic-pass'` counts one backend. In the
  COSMIC session the service runs and its `Super+Space` popup still works.
- **V10 (SC-006)**: after the steps above,
  `journalctl --user -b | grep -c '<the test password>'` prints 0, and so
  does `grep -rIl '<the test password>' ~/.cache ~/.local/state ~/.config`.
- **V11 (SC-009)**: on a machine with the Mango module off, the toplevel
  store path is the same before and after this change.
- **V12 (edge cases)**: open another Rail popup, then `Super+Space`: it is
  replaced. With two monitors, the popup opens on the focused one.
  `pkill -f 'cosmic-pass serve'` with the popup open: "Backend stopped",
  then it works again within a few seconds.
- **V13 (edge cases)**: copy a password, lock the screen for 95 seconds,
  unlock, paste: nothing. Select the third item, press `F5`: it stays
  selected.
