# Research: Mango Rail Bar

Facts below were checked against the pinned nixpkgs on 2026-11-13
(`nixosConfigurations.laptop.pkgs`) and the reference repository
`denonmaryland/omarchy-dotfiles` at its default branch.

## R1. What the reference rail is made of

- **Decision**: Copy the layout and visual rules, not the code.
- **Rationale**: The reference is a set of Quickshell plugins (`denon.shell`,
  `denon.corner`, ...) for the `omarchy-shell` host. They import
  `Quickshell.Hyprland`, read `~/.config/omarchy/shell.json` and Omarchy
  theme state, so none of it runs under Mango as is. Its layout
  (`omarchy/shell.json`) is: `position: left`; left group `denon.agents`,
  `denon.workspaces`; center `keyboard-layout`, `denon.clock`
  (`verticalFormat: "h\nmm\nAP"`), `denon.weather`, `system-update`; right
  group tray, studio drawers, hidden network/bluetooth/audio/power, an
  indicator and `denon.corner` last. Screenshots show workspaces as dots with
  a numbered pill for the active one and the rail coloured as the frame.
- **Alternatives considered**: Vendoring the plugins (Hyprland-only, needs
  the Omarchy host); adopting a full shell such as Noctalia or Dux (011
  research §5 rejected that, and this feature does not revisit it).

## R2. Bar program for the rail

- **Decision**: Keep waybar. The pinned version is now **0.16.0**, so switch
  `ext/workspaces` to the native `mango/workspaces` module.
- **Rationale**: `waybar-mango-workspaces(5)` provides `hide-empty` ("buttons
  for empty workspaces are hidden, unless the workspace is active"), the
  `.active`, `.empty`, `.urgent`, `.current_output` classes and
  `on-click: activate`. That covers FR-004/FR-005 with no code. 011 research
  §4 already planned this switch "when nixpkgs reaches 0.16". Quickshell's
  `Quickshell.WindowManager` (ext-workspace) has no client count, so it cannot
  tell empty from occupied tags.
- **Alternatives considered**: Whole rail in Quickshell (closer to the
  reference's frame join, but needs a hand-written workspace source via
  `mmsg` and rewrites everything waybar already does); eww (no release since
  2024-04, nixpkgs builds a git snapshot).

## R3. Dots with a numbered active pill

- **Decision**: `format: "{value}"`, `hide-empty: true`; CSS hides the label
  of inactive buttons (`#workspaces button:not(.active) label { font-size:
  0; }`) and draws each as a small round dot; `.active` is an accent pill
  with its number, `.urgent` dot uses the accent outline.
- **Rationale**: `format-icons` state keys (`active`, `default`, `empty`)
  are literal strings, so they cannot carry the number; the CSS route keeps
  `{value}` for the active one. GTK3 CSS supports `:not()`.
- **Alternatives considered**: Per-index `format-icons` with a glyph per
  number (precedence between index keys and `active` is undocumented; nine
  entries per state).

## R4. Quick-controls popup (FR-012) and calendar (FR-007)

- **Decision**: A small Quickshell config (pinned 0.3.2, HM
  `programs.quickshell`) that draws only two popups, the quick controls and
  the calendar, toggled from waybar over Quickshell IPC (`qs -c mango ipc
  call <target> toggle`). The rail stays waybar.
- **Rationale**: Waybar has no popup windows; its `pulseaudio/slider` and
  `backlight/slider` modules sit inline in the bar, which a 32 px rail cannot
  hold. Quickshell 0.3.2 ships every service the popup needs:
  `Quickshell.Services.Pipewire` (sink volume, source mute),
  `Quickshell.Services.UPower` (display device, `PowerProfiles`),
  `Quickshell.Bluetooth` (adapter on/off), `Quickshell.Networking` (Wi-Fi
  on/off). Brightness goes through `brightnessctl` (the user is already in
  `video` for swayosd's udev rule). QtQuick.Controls' `MonthGrid`,
  `DayOfWeekRow` and `WeekNumberColumn` draw the calendar. It is also the
  toolkit the reference's corner drawer is written in, so its motion and
  shape can be borrowed later.
- **Alternatives considered**: swaync control centre (replaces mako, which
  011 kept; it has no live battery widget, so FR-012 battery fails); eww
  (unreleased snapshot, no native services, everything via polling
  scripts); waybar `clock` tooltip calendar (hover only, US1 scenario 5 asks
  for click).
- **Note**: This is not a desktop shell (011 research §5): mako, fuzzel,
  swaylock, swayosd and waybar all stay.

## R5. Which display the popup opens on

- **Decision** (revised during implementation): The IPC call takes no
  argument. On toggle, the popup runs `mmsg get cursorpos` and opens on the
  returned `monitor`; the popup is a `Variants` over `Quickshell.screens`
  shown only on the screen whose `name` matches (all screens if `monitor` is
  null).
- **Rationale**: The pointer is on the rail that was clicked, so the monitor
  under it is the right one. Mango's `get cursorpos` returns
  `{"x","y","monitor"}` (`src/ipc/ipc.c`), and Mango imports
  `MANGO_INSTANCE_SIGNATURE` into the systemd user environment
  (`src/main.c`), so the Quickshell service can reach it. This avoids relying
  on `WAYBAR_OUTPUT_NAME`, which `waybar-custom(5)` documents only for
  `exec`, not `on-click`.
- **Alternatives considered**: Leaving `screen` unset (Quickshell then picks
  a default screen, not the clicked one).

## R6. Closing the popups

- **Decision**: Each popup is a full-output transparent `PanelWindow` on the
  overlay layer with `exclusionMode: Ignore` and exclusive keyboard focus; a
  background `MouseArea` closes it, `Keys.onEscapePressed` closes it, the
  visible card sits next to the rail's bottom (controls) or middle
  (calendar).
- **Rationale**: Meets FR-012 "close on Escape or a click outside" with no
  compositor-specific focus grab (Hyprland's `HyprlandFocusGrab` is not
  available on Mango).

## R7. Icons and status modules

- **Decision**: Icons from `Symbols Nerd Font Mono` (uniform 1-em cells; the
  proportional face gave uneven sizes), already installed via
  `nerd-fonts.symbols-only` in `workstation/home.nix`. `network`,
  `wireplumber`, `battery`, `power-profiles-daemon` use `format-icons` /
  `{icon}` only, details in `tooltip-format*`. Battery states
  `warning: 15`, styled by `#battery.warning.discharging` (FR-010). Tray is
  `group/tray` with `drawer.click-to-reveal: true` and a chevron leader
  (`custom/tray-chevron`), `empty-if-drawer-empty` to hide the chevron when
  no tray items exist.
- **Rationale**: All options exist in waybar 0.16 (`waybar(5)` "Group
  Drawers"); the font is already on the machine. `rotate` goes away (SC-004).

## R8. Power menu reachability

- **Decision**: Drop `custom/power` from the rail; the quick-controls popup
  has a power button that runs the existing `mango-power-menu` and closes
  the popup. `Super+Shift+Escape` stays.
- **Rationale**: FR-009/SC-003 allow two clicks; the reference also keeps
  power behind the corner.

## R9. Build-time checks

- **Decision**: Render the QML with `pkgs.replaceVars` (store paths for
  `brightnessctl`, `mango-power-menu`, `mmsg`), and add a `qmllint` run
  against Quickshell's QML import path to `system.extraDependencies`, next to
  `portalCheck`.
- **Rationale**: Constitution I: `replaceVars` fails the build on an unused
  or missing placeholder; `qmllint` catches syntax and unknown-type errors at
  build time instead of at login. It is not added to `checks.*` (Principle
  III: it builds Qt tooling).
- **Outcome**: `qmllint` resolves Quickshell's types. It runs with
  `--max-warnings 0` and only `unresolved-type` (`BluetoothAdapter` is not
  exposed to it) and `uncreatable-type` (`PanelWindow`) disabled. Typos in a
  method, type or property name each fail the check (tested).

## R10. Glossary

- **Decision**: Add **Rail** and **Quick controls** to `GLOSSARY.md` under
  "Desktop / sessions" (Constitution IV).
