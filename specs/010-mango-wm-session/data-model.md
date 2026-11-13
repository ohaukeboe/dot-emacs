# Data Model: Mango Window Manager Session

There is no runtime data store. The "entities" are Nix options and the files
they generate.

## Mango module (`modules.mango`)

Fields and types: see [contracts/options.md](contracts/options.md).

Validation:
- `screenOffAfter > lockAfter` (assertion).
- `greeter.enable` excludes `cosmic-greeter` (assertion, FR-003b).
- Disabled ⇒ contributes nothing (FR-010): all config under `mkIf cfg.enable`.

## Login screen

- Owner: `modules.mango` when `greeter.enable`.
- Lists: every entry of `services.displayManager.sessionData` (`mango`,
  `cosmic` when COSMIC is on).
- State: last user and session, kept by ReGreet in `/var/lib/regreet/`.

## Generated files

| File                              | Source                         | Check        |
|-----------------------------------|--------------------------------|--------------|
| `~/.config/mango/config.conf`     | Nix attrset rendered to `k=v`  | `mango -c -p`|
| `~/.config/waybar/config`, style  | HM `programs.waybar`           | HM types     |
| `~/.config/fuzzel/fuzzel.ini`     | HM `programs.fuzzel`           | HM types     |
| `~/.config/mako/config`           | HM `services.mako`             | HM types     |
| `~/.config/swaylock/config`       | HM `programs.swaylock`         | HM types     |
| user units for idle, polkit, clip | HM services                    | HM types     |

## Session lifecycle

```text
greetd ─► ReGreet ─► user picks session
                      ├─ Mango ─► mango ─► import env ─► mango-session.target
                      │                                  ├─ BindsTo graphical-session.target
                      │                                  └─ Wants waybar, mako, swayidle,
                      │                                     polkit agent, cliphist, nm-applet
                      └─ COSMIC ─► start-cosmic (unchanged; Mango units stay down)
quit mango ─► mango stops graphical-session.target ─► greetd shows ReGreet
```
