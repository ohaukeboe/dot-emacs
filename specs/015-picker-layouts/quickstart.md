# Quickstart: Picker Layouts

Validates the spec's stories on the laptop. Interface details:
`contracts/mango-pick.md`; item formats: `data-model.md`.

## Build gate

```bash
git add -A specs/015-picker-layouts modules/mango
nix fmt
nix flake check
nix build '.#nixosConfigurations.laptop.config.system.build.toplevel'
```

The build runs `qmlCheck` (qmllint over the shell) and fails on a missing
`Config.qml` placeholder.

## Apply

```bash
sudo nixos-rebuild switch --flake .#laptop
```

Quickshell restarts on the switch (its unit's `X-Restart-Triggers`).

## Checks

- **Q1**: `printf 'a\nb\n' | mango-pick Test; echo $?`, pick `b`.
  Expect today's list; prints `b`, status 0.
- **Q2**: the same with `--layout nope`, then Esc. Expect the list; status 1.
- **Q3**: open the power menu, press `4`, then Esc. Expect the Reboot tile to
  show "Press 4 again"; nothing runs.
- **Q4**: `printf 'Lock\tlock\nReboot\trestart\tconfirm\n' | mango-pick --layout tiles P`,
  press `2` twice. Expect `Reboot` printed, status 0.
- **Q5**: start a screen share in Zen with the dock attached. Expect screen
  cards with live thumbnails; window rows show app and tag.
- **Q6**: copy a password from Proton Pass, then Super+v. Expect it absent
  (if shown, Proton Pass sets no sensitive hint: research R3 risk).
- **Q7**: Super+v, Enter on a text entry while foot had focus. Expect the
  text pasted in foot.
- **Q8**: Super+v, Ctrl+Enter on an entry. Expect the clipboard set, nothing
  pasted.
- **Q9**: Super+v, select a screenshot, Delete, reopen. Expect the preview to
  have shown the image and the entry gone.
- **Q10**: `cliphist wipe`, then Super+v. Expect nothing to open.

Q5 needs a share request; the portal's own test app (`ashpd-demo`) works too.
