# Research: Mango Window Manager Session

All facts below were read from the nixpkgs revision pinned in `flake.lock`
(`nix eval '.#nixosConfigurations.laptop.pkgs.path'`) and from the source of
the `mango` package it builds, on 2026-11-11.

## R1. Compositor package and NixOS module

- **Decision**: Use nixpkgs `programs.mango.enable` with the default
  `pkgs.mango` (0.18.4, upstream `mangowm/mango`). Also add
  `systemd.packages = [ config.programs.mango.package ]`.
- **Rationale**: The nixpkgs module already installs the package, registers
  the `mango` Wayland session (`services.displayManager.sessionPackages`) and
  sets `xdg.portal.config.mango` (gtk default, wlr for ScreenCast/ScreenShot,
  gnome-keyring for Secret). *Superseded 2026-11-13: nixpkgs spells the key
  `ScreenShot`; the interface is `Screenshot`, so Screenshot fell through to
  gtk. `modules/mango` now overrides the map (spec 011 research R8; see
  `docs/mangowm-components-research.md` §2).* The package ships `lib/systemd/user/mango-session.target`
  (`BindsTo=graphical-session.target`), and mango itself runs
  `systemctl --user import-environment ...; systemctl --user start mango-session.target`
  on start-up (`src/main.c`). The nixpkgs module does not add the package to
  `systemd.packages`, so without our line the target does not exist and no
  `graphical-session.target` user service starts in a Mango session.
- **Alternatives considered**: Upstream's own flake (`nix/` in the repo,
  also has a Home Manager module) — rejected by the nixpkgs-only rule.
  The name `mangowc` is a deprecated alias (`mkRenamedOptionModule`).

## R2. Login screen

- **Decision**: greetd + ReGreet through nixpkgs
  `services.displayManager.regreet.enable` (ReGreet 0.5.0, runs in `cage`).
- **Rationale**: ReGreet lists every session in
  `services.displayManager.sessionData` (Mango and COSMIC), remembers the last
  user and session, is a graphical GTK login screen, needs no particular
  compositor, and keeps working once COSMIC is gone. Theme, icon, font and
  cursor are typed options of the nixpkgs module, so it can match the dark
  look of the session.
- **Alternatives considered**:
  - `services.displayManager.dux-greeter` with `compositor.name = "mangowc"`:
    the module passes `--command mangowc` to `dms-greeter`, but the package's
    binary is `mango` (`meta.mainProgram`), so it is likely broken for Mango;
    it also pulls quickshell and the DankMaterialShell stack. Rejected.
    *Superseded 2026-11-13: confirmed broken, not just likely: the
    `dms-greeter` 2.0.0 binary accepts `mango` and has no `mangowc` at all
    (`docs/mangowm-components-research.md` §2).*
  - `tuigreet`: text-only, robust, but a step down from COSMIC's graphical
    greeter. Kept as the fallback if ReGreet misbehaves.
  - SDDM / GDM: heavy, pull Qt/GNOME stacks. Rejected.
- **Conflict with COSMIC**: `cosmic-greeter` and ReGreet both set
  `services.greetd.settings.default_session`. Evaluation already fails on the
  clash, but with a generic "conflicting definition values" message. Add an
  explicit assertion in the Mango module (FR-003b) and a new
  `modules.cosmic-de.greeter.enable` option (default `true`) that gates
  `services.displayManager.cosmic-greeter.enable` (FR-003a).
- **Default session**: ReGreet has no "default session" setting; it preselects
  the last session used, stored in `/var/lib/regreet/state.toml`. First login
  shows the first entry. The spec allows either; Mango is chosen once and then
  remembered.
- **Keyring unlock**: `security.pam.services.greetd.enableGnomeKeyring = true`
  so the login password unlocks gnome-keyring as cosmic-greeter does today.

## R3. Mango configuration file

- **Decision**: Generate `~/.config/mango/config.conf` with Home Manager
  `xdg.configFile`, from a Nix attrset rendered to mango's `key=value` format.
  Validate it at build time with `mango -c <file> -p` in a `runCommand`.
- **Rationale**: Home Manager has no Mango module. Mango reads
  `~/.config/mango/config.conf` first (`src/config/load.c`). `-p` is mango's
  "check config" flag (`docs/configuration/basics.md`), which turns a typo in
  the config into a build failure (Constitution I). If `-p` needs a Wayland
  display or `$HOME` in the build sandbox, set `HOME=$TMPDIR`; if it still
  cannot run headless, drop the check and record that in the plan.
- **Keys used** (from `assets/config.conf` and `docs/configuration/input.md`):
  `xkb_rules_layout=eu`, `xkb_rules_options=terminate:ctrl_alt_bksp,caps:ctrl_modifier`,
  `repeat_delay=600`, `repeat_rate=25`, `tap_to_click=1`, `tap_and_drag=1`,
  `drag_lock=0`, `trackpad_natural_scrolling=1`, `exec_once=...`,
  `env=KEY,VALUE`, `bind=MODS,key,action,arg`.
- **Alternatives considered**: `config.toml` (also supported) — rejected,
  the `.conf` format is the documented primary one and every doc example uses
  it.

## R4. Session components (all nixpkgs)

| Need          | Choice                                   | Version |
|---------------|------------------------------------------|---------|
| Bar           | waybar (HM `programs.waybar`)            | 0.15.0  |
| Launcher      | fuzzel (HM `programs.fuzzel`)            | 1.15.0  |
| Notifications | mako (HM `services.mako`)                | 1.11.0  |
| Lock          | swaylock (HM `programs.swaylock`)        | 1.8.6   |
| Idle          | swayidle (HM `services.swayidle`)        | 1.9.1   |
| Polkit agent  | hyprpolkitagent (HM service)             | 0.2.0   |
| Clipboard     | wl-clipboard + cliphist (HM service)     | 0.7.0   |
| Screenshot    | grim + slurp                             | 1.5.0   |
| Brightness    | brightnessctl                            | 0.5.1   |
| Volume        | `wpctl` (PipeWire, already installed)    | -       |
| Wallpaper     | swaybg, flat `#171717` as in COSMIC      | 1.2.2   |
| Network tray  | nm-applet (in waybar tray)               | 1.36.0  |
| Terminal      | option, default `pkgs.foot`              | -       |

- **Rationale**: Each is the common choice for wlroots compositors, is in
  nixpkgs, and (except swaybg, grim, slurp, brightnessctl) has a Home Manager
  service or program module, so it starts as a systemd user service rather
  than an `exec_once` line.
- **Scoping to Mango**: user services must start only in a Mango session, not
  in COSMIC (which also activates `graphical-session.target`). Bind every
  component service to `mango-session.target` (`WantedBy`/`PartOf`) instead
  of `graphical-session.target`. HM exposes the target per module (e.g.
  `programs.waybar.systemd.target(s)`, `services.swayidle.systemdTarget`,
  `services.cliphist.systemdTargets`); exact option names are checked against
  the pinned Home Manager during implementation.
- **Alternatives considered**: swaync (not in this nixpkgs under that
  attribute), hyprlock/hypridle (pull hyprland libs; swaylock/swayidle are
  smaller and wlroots-native), DankMaterialShell/Noctalia (whole shells, not
  in the nixpkgs-only spirit and much bigger).
  *Superseded 2026-11-13: swaync is `pkgs.swaynotificationcenter` 0.12.6 with
  HM `services.swaync`; DankMaterialShell is now Dux Shell (`dux-shell`,
  NixOS `programs.dux-shell`) and Noctalia is `pkgs.noctalia` with NixOS and
  HM modules, so both fit nixpkgs-only. Size remains the reason to skip them
  (`docs/mangowm-components-research.md` §2, §5).*

## R5. Password quick access

- **Decision**: `Super+Space` spawns the nixpkgs `proton-pass` desktop app
  (already in `workstation/home.nix`); `Super+Shift+Space` spawns
  `1password --quick-access` as in COSMIC.
- **Rationale**: `cosmic-pass` is a flake input, not nixpkgs, and is a COSMIC
  applet; FR-009 forbids pulling it in from the Mango module. Gap recorded:
  no Proton Pass quick-access popup under Mango, only the full app.
- **Alternatives considered**: reusing `cosmic-pass` when COSMIC is on —
  rejected, it would break the moment COSMIC is turned off (FR-014).

## R6. Coexistence with COSMIC

- **Portals**: `xdg-desktop-portal` picks `mango-portals.conf` because mango
  sets `XDG_CURRENT_DESKTOP=mango` (`src/main.c`) and imports it into the
  systemd user environment. COSMIC's `xdg.portal.config.common.default` only
  applies when no desktop-specific file matches, so it does not leak in.
- **Session variables**: the COSMIC module sets `QT_QPA_PLATFORMTHEME=cosmic`
  and `GTK_THEME=adw-gtk3-dark` system-wide. In Mango, override
  `QT_QPA_PLATFORMTHEME` with mango's `env=` lines; keep `GTK_THEME` (it only
  needs the theme package, which the Mango module also installs).
  *Superseded 2026-11-13: `GTK_THEME` itself comes from `modules/cosmic-de`,
  so Mango lost it with COSMIC off. `modules/mango` now sets it with an
  `env=` line (spec 011 research R15; `docs/mangowm-components-research.md`
  §2, §21).*
- **gnome-keyring / SSH agent**: the Mango module sets
  `services.gnome.gnome-keyring.enable = true` and
  `services.gnome.gcr-ssh-agent.enable = false`, the same values as the COSMIC
  module, so the definitions merge and FR-007 holds with COSMIC off.
- **Power**: `services.power-profiles-daemon.enable = true` in the Mango
  module too (the COSMIC module owns it today); waybar's `power-profiles-daemon`
  module drives it.
- **Lid / suspend-then-hibernate**: handled by logind and
  `modules.sleep-then-hibernate`, independent of the session. swayidle's
  `before-sleep` locks the screen.
