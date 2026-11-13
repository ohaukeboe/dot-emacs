# Contract: `modules.mango` and `modules.cosmic-de.greeter` options

`modules.mango` lives in `modules/mango/default.nix`, imported through
`modules/default.nix`. Everything is inside `mkIf cfg.enable` (Principle V).

```nix
modules.mango = {
  enable = mkEnableOption "Mango window manager session";

  # FR-003: the module's own login screen (greetd + ReGreet).
  greeter.enable = mkOption { type = types.bool; default = true; };

  # FR-012: per-taste choices, typed so a wrong value fails evaluation.
  terminal = mkPackageOption pkgs "foot" { };   # spawned by Super+Return
  lockAfter = mkOption {                        # idle seconds before lock
    type = types.ints.positive;
    default = 300;
  };
  screenOffAfter = mkOption {                   # idle seconds before DPMS off
    type = types.ints.positive;
    default = 600;
  };
};

# FR-003a: new option on the existing COSMIC module.
modules.cosmic-de.greeter.enable = mkOption { type = types.bool; default = true; };
```

## Assertions

| Fails when                                      | Message tells the user to            |
|-------------------------------------------------|--------------------------------------|
| `mango.greeter.enable && cosmic-greeter.enable` | set `cosmic-de.greeter.enable=false` |
| `screenOffAfter <= lockAfter`                   | raise `modules.mango.screenOffAfter` |

The first is the FR-003b guard. It reads the nixpkgs option
`services.displayManager.cosmic-greeter.enable`, not COSMIC module internals.

## Key bindings (generated into `config.conf`)

Super is the main modifier, as in COSMIC.

| Keys                   | Action                                  |
|------------------------|-----------------------------------------|
| Super+Return           | `terminal`                              |
| Super+d                | fuzzel launcher                         |
| Super+q                | close window                            |
| Super+arrows           | focus direction                         |
| Super+Shift+arrows     | move window                             |
| Super+1..9             | view tag                                |
| Super+Shift+1..9       | move window to tag                      |
| Super+f                | fullscreen                              |
| Super+Shift+f          | toggle floating                         |
| Super+Escape           | lock (swaylock)                         |
| Super+Shift+e          | quit mango (back to login screen)       |
| Super+v                | clipboard history (cliphist + fuzzel)   |
| Print / Shift+Print    | screenshot full / region (grim, slurp)  |
| Super+Space            | `proton-pass`                           |
| Super+Shift+Space      | `1password --quick-access`              |
| XF86 audio/brightness  | `wpctl` / `brightnessctl`               |

## Machine composition (`machines/machines.nix`, `laptop`)

```nix
{ modules.cosmic-de.enable = true; }
{ modules.cosmic-de.greeter.enable = false; }
{ modules.mango.enable = true; }
```

Dropping COSMIC later (SC-007) removes the first two lines.
