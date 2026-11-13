# Contract: new `modules.mango` options, commands and bindings

Additions to `modules/mango/default.nix`; everything stays inside
`mkIf cfg.enable` (Constitution V). Existing options are unchanged.

## Options

```nix
modules.mango.displays = {
  # Laptop panel output name (R3, R4).
  internal = mkOption {
    type = types.nonEmptyStr;
    default = "eDP-1";
  };

  # Known setups (FR-001, FR-008). Empty by default; laptop adds none yet.
  setups = mkOption {
    type = types.attrsOf (types.submodule {
      options.outputs = mkOption {
        type = types.nonEmptyListOf (types.submodule {
          options = {
            criteria = mkOption { type = types.nonEmptyStr; };
            enable = mkOption { type = types.bool; default = true; };
            mode = mkOption {
              type = types.nullOr (types.strMatching "[0-9]+x[0-9]+(@[0-9.]+(Hz)?)?");
              default = null;
            };
            position = {
              x = mkOption { type = types.ints.unsigned; default = 0; };
              y = mkOption { type = types.ints.unsigned; default = 0; };
            };
            scale = mkOption {
              type = types.nullOr (types.addCheck types.float (s: s > 0));
              default = null;
            };
          };
        });
      };
    });
    default = { };
  };
};
```

Example entry, as printed by `mango-display-setup`:

```nix
modules.mango.displays.setups.home-desk.outputs = [
  { criteria = "eDP-1"; enable = false; }
  { criteria = "Dell Inc. DELL U2723QE ABC123"; position = { x = 0; y = 0; }; scale = 1.5; }
];
```

## Assertions

| Fails when                                  | Message tells the user to              |
|---------------------------------------------|----------------------------------------|
| two outputs in one setup share `criteria`   | rename or remove the duplicate         |
| a setup is named `undocked`                 | pick another name (reserved)           |
| a setup has no enabled output               | enable at least one output             |
| a portal key names an interface the backend | fix the key spelling (build-time check |
| does not declare                            | on the generated portal config)        |

## Commands (all `writeShellApplication`, on `PATH` in the session)

| Command               | Does                                                         |
|-----------------------|--------------------------------------------------------------|
| `mango-display-setup` | prints connected displays as a `setups.<name>` entry (R7)    |
| `mango-lid-sync`      | panel off if lid closed and docked, else on (R4)             |
| `mango-reload`        | reload Mango config, `kanshictl reload`, `mango-lid-sync`    |
| `mango-power-menu`    | fuzzel menu: lock, log out, suspend, reboot, power off (R13) |
| `mango-screenshot`    | existing; adds `annotate` mode (grim + slurp into satty)     |

## Key bindings (changed or new)

| Binding                    | Action                                    |
|----------------------------|-------------------------------------------|
| `Super+r`                  | `mango-reload` (was `reload_config`)      |
| `Super+Shift+Escape`       | `mango-power-menu`                        |
| `Ctrl+Print`               | `mango-screenshot annotate`               |
| volume, mic-mute keys      | `swayosd-client` (was `wpctl`)            |
| brightness keys            | `swayosd-client` (was `brightnessctl`)    |
| `switchbind` fold / unfold | `mango-lid-sync`                          |

## Session services (all bound to `mango-session.target`)

kanshi, wl-clip-persist, swayosd, blueman-applet; existing ones unchanged.
