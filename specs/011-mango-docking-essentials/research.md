# Research: Mango Docking and Session Essentials

Component choices come from `docs/mangowm-components-research.md` (the
report). This file settles how each is wired in, checked against the pinned
inputs: mango 0.18.4 source (`/nix/store/…-source`, the `src` of
`programs.mango.package`), and evaluation of `nixosConfigurations.laptop`
on 2026-11-13.

## R1. Known display setups: kanshi

- **Decision**: Home Manager `services.kanshi` (kanshi 1.9.0), generated from
  `modules.mango.displays.setups`, with `systemdTarget = mango-session.target`.
- **Rationale**: A setup is a *combination* of displays. kanshi matches a
  profile only when the whole set of connected outputs matches, by name or by
  "make model serial" description (kanshi(5), OUTPUT CRITERIA), and re-matches
  on every hotplug. Mango's `monitor_rule` matches each monitor on its own
  (`docs/configuration/monitors.md`: "only the first matching rule applies to
  a monitor"), so one monitor used at two desks cannot sit in two positions.
  kanshi drives Mango through `wlr-output-management`, which Mango implements
  (report §14).
- **Alternatives**: `monitor_rule` only (no per-setup matching); shikane
  (154 stars, same model, smaller); way-displays (nixpkgs a major version
  behind, its own auto-arrange model, report §14).

## R2. Unknown setups: Mango's own auto placement

- **Decision**: Write no `monitor_rule` lines. When kanshi finds no profile it
  does nothing, and Mango places the new output with
  `wlr_output_layout_add_auto` (`src/manage/monitor.c:797`), enabled at its
  preferred mode.
- **Rationale**: wlroots' auto layout puts each auto-placed output to the right
  of the outputs already in the layout, which is the clarified default
  (extend right, panel stays on). It needs no code and works before kanshi
  starts.
- **Alternatives**: a kanshi catch-all profile. kanshi profiles match a fixed
  number of outputs, so "any N displays" cannot be one profile.

## R3. Undocked profile, always generated

- **Decision**: Besides the user's setups, generate one kanshi profile
  `undocked` that matches the laptop panel alone: enabled, at `0,0`.
- **Rationale**: A setup may turn the panel off or move it right of an
  external display. Without a profile for "panel only", undocking leaves the
  panel off (black screen) or at an offset. kanshi applies `undocked` on the
  hotplug that removes the last external display.

## R4. Lid closed while docked

- **Decision**:
  - logind: keep `HandleLidSwitchDocked` at its default `ignore`. The laptop
    config sets `HandleLidSwitch` and `HandleLidSwitchExternalPower` to
    `suspend` and leaves `HandleLidSwitchDocked` unset (evaluated).
  - Panel off/on: a `mango-lid-sync` script, run from
    `switchbind=fold,…` / `switchbind=unfold,…`
    (`docs/bindings/mouse-gestures.md`, `src/input/switch.c`), from
    `exec_once`, and as `exec` in every kanshi profile. It reads
    `/proc/acpi/button/lid/*/state`; lid closed and another output connected →
    `mmsg dispatch disable_monitor,<panel>`; otherwise `enable_monitor`.
- **Rationale**: logind already treats "more than one display connected" as
  docked and ignores the lid then, so ADR 0001 is untouched: lid closed with
  no external display still suspends. Mango has no "disable panel on lid"
  setting, but `switchbind` plus the `disable_monitor` dispatch
  (`docs/configuration/monitors.md`) do it. The kanshi `exec` re-runs the
  sync after a profile has re-enabled the panel.
- **Open**: whether logind re-checks the lid when the dock is removed with the
  lid already closed. Checked in quickstart step D5; if not, the script
  calls `systemctl suspend` itself in that case.

## R5. Config reload must not undo kanshi

- **Decision**: Set `auto_reload_config=0`. `Super+r` runs a
  `mango-reload` script: `mmsg dispatch reload_config`, then
  `kanshictl reload`, then `mango-lid-sync`.
- **Rationale**: On reload Mango re-applies output state, and an output with
  no matching rule is set "same default as a new output, enabled"
  (`src/config/reapply.c:236`). That re-enables a panel kanshi or the lid
  script turned off. Auto-reload would fire on every Home Manager switch.

## R6. Ad-hoc display tool

- **Decision**: `wdisplays` 1.3.0, launched from the launcher.
- **Rationale**: GUI over `wlr-output-management`; changes apply at once and
  are not saved, which matches "nothing ad-hoc is kept". nwg-displays only
  targets sway, Hyprland and Niri (report §14).

## R7. Printing the current setup

- **Decision**: `mango-display-setup`: `wlr-randr --json` piped through `jq`,
  printing a ready-to-paste `modules.mango.displays.setups.<name>` entry
  (criteria as "make model serial", position, current mode, scale, enabled).
- **Rationale**: `wlr-randr` 0.5.0 has `--json` (man page). Mango's docs
  point to `wlr-randr` for make/model/serial (`monitors.md`).

## R8. Portal Screenshot key

- **Decision**: Set `xdg.portal.config.mango` with `mkForce` to the full,
  correctly spelled map (`Screenshot`, not `ScreenShot`), and add a build-time
  check: every `org.freedesktop.impl.portal.*` key in that map must appear in
  the `Interfaces=` line of the named backend's `.portal` file.
- **Rationale**: Evaluated today: the map contains
  `org.freedesktop.impl.portal.ScreenShot = wlr`, which no backend declares, so
  Screenshot falls to `default = gtk`, which has no Screenshot (report §2, R1).
  `mkForce` drops the misspelled key. The check turns this class of typo into
  a build error (Constitution III: a fix evaluation could not catch needs a
  guard).

## R9. Screen-share picker

- **Decision**: `xdg.portal.wlr.settings.screencast = { chooser_type =
  "simple"; chooser_cmd = "<slurp store path> -f %o -or"; }`.
- **Rationale**: xdpw looks pickers up on `PATH`, but runs as a user service
  (report §12). An absolute store path removes that dependency. `slurp -o`
  lets the user click the display to share, which matches "pick which display"
  with several outputs. The setting is written to
  `/etc/xdg/xdg-desktop-portal-wlr/config`, read only by xdpw, which only
  serves the Mango session (`portalCfg.common.default = cosmic`).
- **Alternatives**: `chooser_type = "dmenu"` with fuzzel (lists output names,
  less obvious with unknown displays).

## R10. Clipboard persistence

- **Decision**: HM `services.wl-clip-persist` (0.5.0),
  `clipboardType = "regular"`, `systemdTargets = [ mango-session.target ]`.
- **Rationale**: Mango's docs pair it with cliphist (report §10). `regular`
  skips the primary selection, which otherwise makes selecting text slow in
  some apps.

## R11. Volume/brightness OSD

- **Decision**: HM `services.swayosd` (0.3.2), unit bound to the session
  target with the module's existing `bindToSession`; key binds call
  `swayosd-client --output-volume …`, `--input-volume mute-toggle`,
  `--brightness …`. Add `services.udev.packages = [ pkgs.swayosd ]` and the
  user to group `video`.
- **Rationale**: The HM module has no target option (evaluated option list:
  `display enable package stylePath topMargin`). swayosd writes brightness to
  `/sys/class/backlight/*/brightness`; its udev rule makes that file
  group-`video` writable, and the user is not in `video` today (evaluated
  groups). `--display` is left unset so the OSD follows the focused output.
- **Alternatives**: keep `wpctl`/`brightnessctl` and draw the OSD with wob
  (needs a pipe and per-key glue).

## R12. Bluetooth and audio controls

- **Decision**: NixOS `services.blueman.enable = true` (blueman 2.4.6, D-Bus
  mechanism and `blueman-manager`); HM `services.blueman-applet` with
  `systemdTargets = [ mango-session.target ]`; `pwvucontrol` 0.5.3 opened from
  the waybar `wireplumber` module's `on-click`. Bluetooth hardware is already
  on (`hardware.bluetooth.enable = true`).
- **Rationale**: Report §17. The applet sits in the existing waybar tray.

## R13. Power menu

- **Decision**: `mango-power-menu`: `fuzzel --dmenu` over lock / log out /
  suspend / reboot / power off; bound to `Super+Shift+Escape` and a waybar
  `custom/power` button.
- **Rationale**: Reuses installed tools (report §23). Log out is
  `mmsg dispatch quit`; the rest are `swaylock -f` and `systemctl`.

## R14. Screenshot annotation

- **Decision**: HM `programs.satty` (0.22.0) with `output-filename` in the
  existing Screenshots directory and `copy-command = wl-copy`. The screenshot
  script gets an `annotate` mode: `grim -g "$(slurp)" - | satty --filename -`.
  Bound to `Ctrl+Print`.
- **Rationale**: Report §11; the plain modes stay unchanged.

## R15. Theming without COSMIC

- **Decision**, all scoped to Mango:
  - `env=GTK_THEME,adw-gtk3-dark` in Mango's config (GTK3).
  - HM `dconf.settings."org/gnome/desktop/interface"`:
    `color-scheme = "prefer-dark"`, `cursor-theme = "Adwaita"`,
    `cursor-size = 24` (libadwaita reads color-scheme through the gtk
    portal's Settings, which serves Mango; report §12, §21).
  - Mango `cursor_theme=Adwaita`, `cursor_size=24`
    (`src/config/option_defs.c:561`; 24 is Mango's default), plus
    `env=XCURSOR_THEME,Adwaita` and `env=XCURSOR_SIZE,24` for XWayland.
  - `adwaita-icon-theme` in the module's packages, so the cursor does not
    depend on COSMIC installing it.
  - Qt keeps `env=QT_QPA_PLATFORMTHEME,gtk3` (already there).
- **Rationale**: Session `env=` lines do not touch COSMIC (FR-016). The dconf
  keys are read under COSMIC too, but COSMIC answers Settings itself through
  its own portal, so they only matter in Mango.
- **Rejected**: HM `gtk.enable` and `home.pointerCursor.gtk.enable`. They
  write `~/.config/gtk-3.0`/`gtk-4.0` files that COSMIC's theme export also
  manages, so the two would fight over the same files.

## R16. Bar, wallpaper, lock on every display

- **Decision**: no change.
- **Rationale**: waybar's `main` bar has no `output` key, so it appears on
  every output, including hotplugged ones. `swaybg -c` without `-o` paints
  every output. swaylock uses `ext-session-lock`, which covers outputs added
  while locked. Verified by quickstart, not by code.

## R17. Corrections to spec 010 research (FR-020)

- **Decision**: Edit `specs/010-mango-wm-session/research.md` in place: the
  `ScreenShot` spelling, swaync availability, Noctalia/Dux packaging, the
  `GTK_THEME` source, and the dux-greeter `mangowc` name, each marked
  "Superseded 2026-11-13" with a link to the report.
