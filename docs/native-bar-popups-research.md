# Rail popups that feel native: Wi-Fi, Bluetooth, audio, power

Research for growing the Mango **rail** (`specs/012-mango-rail-bar`) from
icons that launch separate apps into GNOME/KDE-style popups: a Wi-Fi list
with a password field, Bluetooth pairing, output/input switching with
per-app volume, brightness and power profiles. It builds on
[`mangowm-components-research.md`](mangowm-components-research.md) (§4 bar,
§5 shells, §7 notifications, §17 network/Bluetooth/audio) and does not
repeat it. Terms follow `GLOSSARY.md`: **Rail** (the waybar strip),
**Quick controls** (the gear popup, drawn by Quickshell).

**Gathered 2026-11-13.** "Pinned" means the nixpkgs this flake locks,
evaluated with `nix eval --inputs-from . nixpkgs#<pkg>.version`. Quickshell
API claims come from the pinned build's QML type files
(`/nix/store/…-quickshell-0.3.2/lib/qt-6/qml/Quickshell/**/*.qmltypes`) and
from the upstream source at
[quickshell-mirror/quickshell][qs]; the quickshell.org docs URL for the
Networking module returned 404 when tried, so the source is cited instead.

## 1. Summary

The rail today: waybar draws the icons; `network` opens
`nm-connection-editor`, `wireplumber` opens `pwvucontrol`, and the gear opens
the Quickshell **Quick controls** with on/off toggles only
(`modules/mango/default.nix`, `modules/mango/quickshell/shell.qml`).
Popups that feel native need two things: lists you can act on (networks,
devices, sinks, streams) and the D-Bus **agents** that answer password and
PIN prompts.

| Popup         | Data source     | Build in QML with          | Delegate                |
|---------------|-----------------|----------------------------|-------------------------|
| Wi-Fi list    | NetworkManager  | `Quickshell.Networking`    | nm-applet (agent)       |
| Bluetooth     | BlueZ           | `Quickshell.Bluetooth`     | blueman-applet (agent)  |
| Audio         | PipeWire        | `Services.Pipewire`        | pwvucontrol (profiles)  |
| Battery       | UPower          | `Services.UPower`          | -                       |
| Power profile | p-p-daemon      | `PowerProfiles` (UPower)   | -                       |
| Brightness    | sysfs backlight | `Process` + brightnessctl  | swayosd for keys        |
| Media         | MPRIS           | `Services.Mpris`           | -                       |
| Notifications | D-Bus name      | only by replacing mako     | keep mako (or swaync)   |

**Recommendation.** Keep the rail in waybar and the popups in Quickshell.
Point waybar's `network`, `wireplumber` and a new `bluetooth` module at
three new Quickshell popups (same `popupToggle` IPC as today) and build them
on the native service modules: Quickshell 0.3.2 now has a NetworkManager
module, so none of the `nmcli` wrapper code the big shells carry is needed.
Keep `nm-applet` and `blueman-applet` running, not as UIs but because they
are the secret/pairing agents Quickshell lacks (§3). Leave card profiles and
anything advanced to a "Settings…" row that opens `pwvucontrol`,
`blueman-manager` or `nm-connection-editor`. Borrow from small configs that
use the native APIs (§6), not from end-4 or caelestia's network code.

Decisions for the user:

1. **Per-app volume.** `specs/012-mango-rail-bar` lists "per-app mixers" as
   out of scope (spec, Assumptions). Adding them means amending the spec.
2. **One popup or drill-down.** Separate popups per rail icon (KDE style), or
   GNOME-style Quick controls where each toggle has an arrow that opens its
   list in place. Both reuse the existing `RailPopup` component.
3. **Notification history.** Unchanged from components research §7: mako,
   or swaync. A Quickshell notification centre means retiring mako.

## 2. Approaches and how featureful their popups are

| Approach               | Wi-Fi           | BT pairing    | Audio streams | Pinned      |
|------------------------|-----------------|---------------|---------------|-------------|
| Quickshell, native     | list + PSK      | yes, no agent | yes           | 0.3.2       |
| Dux Shell (Quickshell) | NM/iwd + agents | own agent     | yes           | 2.0.0       |
| Noctalia (C++)         | NM/iwd + agents | own agent     | yes           | 5.4.1       |
| end-4 / caelestia      | via `nmcli`     | QS module     | yes           | unpackaged  |
| AGS / Astal            | NM wrapper lib  | BlueZ lib     | yes (Wp)      | removed     |
| waybar + applets       | nm-applet menu  | blueman       | pwvucontrol   | in use      |
| waybar + launcher menu | nm_dmenu        | bzmenu        | pwmenu        | yes         |
| swaync centre          | none            | none          | one slider    | 0.12.6      |
| nwg-panel Controls     | none            | none          | per-app       | 0.12.3      |
| eww                    | DIY scripts     | DIY           | DIY           | git 2026-07 |

`nm_dmenu` is networkmanager_dmenu (§2.5).

### 2.1 Quickshell built-in service modules

The pinned 0.3.2 ships these QML modules (listing of
`lib/qt-6/qml/Quickshell` in the store path): `Bluetooth`, `Networking`,
`DBusMenu`, `Services/{Pipewire,UPower,Mpris,Notifications,SystemTray,
Polkit,Pam,Greetd}`, plus `Hyprland`, `I3`, `Wayland`, `X11`.

- **`Quickshell.Networking`** (added in 0.3.0: "Added network management
  support", [changelog v0.3.0][qs-ch030]). "For now, the only backend
  available is the NetworkManager DBus interface" ([module.md][qs-netmod];
  `NetworkBackendType` values are `None`, `NetworkManager` in the qmltypes).
  It exposes `Networking.devices`, `wifiEnabled`, `wifiHardwareEnabled`,
  `connectivity`; `WifiDevice.scannerEnabled` ("When enabled, the scanner
  populates the device with an active list of available wifi networks") and
  `networks`; per network `signalStrength`, `security`, `connected`,
  `known`, `connect()`, `disconnect()`, `forget()`, and
  `connectWithPsk(psk)`. A wrong PSK emits `connectionFailed` with
  `NoSecrets`, and the docs recommend calling `connect()` first so a stored
  key avoids the prompt ([wifi.hpp][qs-wifi]). `connectWithSettings` takes an
  `NMSettings` object (NetworkManager only, [network.hpp][qs-net]), which is
  the route to WPA-Enterprise. No VPN or hidden-SSID API appears in the
  headers or qmltypes. `WiredDevice` gives `hasLink` and `linkSpeed`.
- **`Quickshell.Bluetooth`**: "Bluetooth management APIs provided by the
  BlueZ DBus interface" ([module.md][qs-btmod]). Adapter: `enabled`,
  `discovering`, `discoverable`, `pairable`, `devices`. Device: `name`,
  `icon`, `connected`, `paired`, `pairing`, `trusted` (writable), `blocked`,
  `battery`/`batteryAvailable`, and `connect()`, `disconnect()`, `pair()`,
  `cancelPair()`, `forget()` ([device.hpp][qs-btdev]).
- **`Quickshell.Services.Pipewire`**: `Pipewire.nodes`, `defaultAudioSink`,
  `defaultAudioSource`, and writable `preferredDefaultAudioSink`/`Source`
  for switching outputs; `PwNode.isSink`, `isStream`, `description`,
  `nickname`, `properties`, `audio.volume`, `audio.volumes` (per channel),
  `audio.muted`; `PwNodePeakMonitor` for level meters (added in 0.3.0,
  [changelog][qs-ch030]); `PwObjectTracker` must bind a node before its
  audio properties are valid (pinned qmltypes; current `shell.qml` already
  does this). There is **no device, profile or route type**, so switching a
  card profile (HDMI vs analog, Bluetooth A2DP vs HFP) is not possible from
  QML; `wpctl set-profile ID INDEX` and `wpctl set-route ID INDEX` exist in
  the pinned `wpctl --help`.
- **`Quickshell.Services.UPower`**: `UPower`, `UPowerDevice` and the
  `PowerProfiles` singleton with `PowerProfile` enum and a
  `powerProfileHold` type (pinned qmltypes). Already used by Quick controls.
- **`Mpris`, `Notifications` (`NotificationServer`), `SystemTray`** with
  `QsMenuAnchor`/`QsMenuOpener` for tray menus, and `Polkit` (`PolkitAgent`,
  "Added support for creating Polkit agents", [changelog][qs-ch030]).
- **Brightness:** no module. Every Quickshell config checked shells out:
  end-4's and caelestia's `Brightness.qml` call `brightnessctl` and
  `ddcutil` (for external monitors) ([end-4][e4-bright],
  [caelestia][cl-bright]); this repo's `shell.qml` does the same with
  brightnessctl.

### 2.2 The missing agents

Neither password prompts nor Bluetooth PINs work from a UI alone: the
daemon calls back into a registered agent. NetworkManager asks a
`SecretAgent` for missing Wi-Fi/VPN secrets
([NM D-Bus API][nm-agent]); BlueZ asks an `Agent1` registered through
`AgentManager1` for PIN/passkey/confirmation ([BlueZ agent API][bz-agent]).

The pinned Quickshell binary and libraries contain the strings
`org.bluez.Device1` and `org.freedesktop.NetworkManager.Device.Wireless` but
not `org.bluez.Agent1`, `AgentManager1` or
`org.freedesktop.NetworkManager.SecretAgent` (grep over the store path). So
Quickshell drives the daemons but answers no prompts. Consequences:

- Wi-Fi with a PSK works natively (`connectWithPsk`, field in the popup).
  Enterprise, VPN and captive-portal secrets need an agent: nm-applet is
  one (`AppletAgent` is an `NM_TYPE_SECRET_AGENT_OLD` subclass, identifier
  `org.freedesktop.nm-applet`, [applet-agent.c][nma-agent]).
- `pair()` on a device that needs a passkey or confirmation needs an agent;
  blueman-applet provides one (blueman's `AgentManager` binding and the
  applet's agent plugin are in the pinned `blueman-2.4.6` package,
  `blueman/bluez/AgentManager.py`, `blueman/plugins/applet/AuthAgent.py`).
  Devices that need no user input ("just works") may pair without one;
  this was not tested.

Both applets already run, bound to `mango-session.target`
(`modules/mango/default.nix`). That is why the recommendation keeps them.

### 2.3 Popular Quickshell shells

Popularity from components research §5 (GitHub stars); implementation read
from source.

- **end-4 dots-hyprland ("illogical-impulse").** `services/Network.qml` is
  "Network service with nmcli": it runs `nmcli monitor`, parses
  `nmcli -g ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY d w`, connects with
  `nmcli dev wifi connect` and sets passwords via
  `nmcli connection modify … wifi-sec.psk` (332 lines, [source][e4-net]).
  Bluetooth uses `Quickshell.Bluetooth` directly and sorts devices into
  connected / paired / unpaired ([BluetoothStatus.qml][e4-bt]). Audio filters
  `Pipewire.nodes` by `isSink`/`isStream` into device and app lists and
  switches with `preferredDefaultAudioSink` ([Audio.qml][e4-audio]).
  Hyprland-only (components research §5).
- **caelestia shell.** `services/Nmcli.qml` is a 1831-line `nmcli` wrapper
  (connect, `connection add` with PSK, hidden networks, forget,
  autoconnect) ([source][cl-nmcli]); `services/VPN.qml` adds VPN. Audio is
  native Pipewire with sinks, sources and per-stream volume
  ([Audio.qml][cl-audio]). Hyprland-only.
- **Dux Shell (ex-DankMaterialShell).** QML front end plus a Go daemon. The
  daemon has NetworkManager, iwd, systemd-networkd and wpa_supplicant
  backends, secret agents for NM and iwd, VPN (incl. Fortinet/GlobalProtect
  SAML), hotspot and modem code ([`core/internal/server/network`][dux-net]),
  and its own BlueZ agent ([`…/bluez/agent.go`][dux-bz]). The most complete
  feature set; it is a whole shell, not a set of popups.
- **Noctalia.** No longer Quickshell (components research §5). Its C++
  D-Bus layer has NetworkManager, iwd and wpa_supplicant services, an NM
  secret agent, an iwd secret agent, enterprise credentials and a VPN auth
  dialog ([`src/dbus/network`][noct-net]), plus a Bluetooth agent
  ([`src/dbus/bluetooth`][noct-bt]).
- **Small configs on the native API.** GitHub code search for
  `"import Quickshell.Networking"` returns about 3000 files, including
  sioodmy/nixus `NetworkView.qml` (194 lines: `Networking.devices`,
  `scannerEnabled`, `connectWithPsk`, `forget()`; [source][sio-net]) and
  nicknisi/dotfiles `NetMenu.qml` (353 lines, same calls; [source][nick-net]).
  These are the right size to borrow from.

The big shells predate `Quickshell.Networking` (0.3.0) and kept their
`nmcli` code; for a NetworkManager system that code is no longer needed.

### 2.4 AGS / Astal

Astal splits services into GObject libraries usable from GJS, Lua, Python or
Vala: Network ("NetworkManager wrapper library"), Bluetooth ("Controls
BlueZ over DBus"), WirePlumber, Battery ("DBus proxy for the upower
daemon"), PowerProfiles, Notifd, Tray, Mpris, Brightness
([Astal library references][astal-ref]). Feature-wise it matches Quickshell
and adds a brightness library. In the pinned nixpkgs, `ags` and `astal`
throw "'ags' and 'astal' ecosystem is no longer packaged in nixpkgs, use
upstream flake instead", and `hyprpanel` (an AGS shell) throws "has been
archived, consider using 'wayle' instead". Excluded by the nixpkgs-only
rule of `specs/010-mango-wm-session`, and a second toolkit next to
Quickshell.

### 2.5 Waybar plus external tools

What the rail does today, extended:

- **Tray applets.** nm-applet 1.36.0 and blueman 2.4.6 give full GTK menus
  from the tray (already in the rail's tray drawer). Features are complete;
  the look is GTK menus, not cards.
- **Mixer windows.** pwvucontrol 0.5.3 (GTK4, current `on-click`),
  pavucontrol 6.2, wiremix 0.11.0 (TUI). Full profile/port control.
- **Launcher menus** (fuzzel is already the launcher):
  - networkmanager_dmenu 2.7.2: connects to new Wi-Fi ("Requests passphrase
    if required"), and existing VPN, WireGuard, WWAN and Bluetooth
    connections; needs PyGObject and libnm; lists fuzzel among launchers
    ([README][nmdmenu]).
  - iwmenu 0.4.0: Wi-Fi over **iwd** D-Bus ([README][iwmenu]); does not
    apply here, `networking.networkmanager.enable = true`
    (`common/system/system.nix`).
  - bzmenu 0.4.0: Bluetooth through the launcher; its README needs a
    notification daemon "For pairing confirmations" ([README][bzmenu]).
  - pwmenu 0.4.0: PipeWire, menus for `output-devices`, `input-devices`,
    `output-streams`, `input-streams`; fuzzel with XDG icons
    ([README][pwmenu]).
- **Waybar's own `menu`.** Modules can open a GtkBuilder XML `GtkMenu` set
  by `"menu"`, `"menu-file"` and `"menu-actions"` ([wiki][wb-menu]).
  Static entries only, so it suits a power menu, not a network list.
- **GUI managers:** overskride 0.6.6 (GTK4 Bluetooth), iwgtk 0.9 (iwd only),
  bluetui 0.8.2 / bluetuith 0.2.7 (TUI), impala 0.9.0 (iwd TUI).

### 2.6 Other bars and centres

- **SwayNC** control centre widgets: title, DND, notifications, label,
  calendar, MPRIS, menubar, buttons-grid, volume ("Volume slider using
  PulseAudio") and backlight ([README][swaync]). No Wi-Fi or Bluetooth
  lists; a buttons-grid can only run commands.
- **nwg-panel** Controls: "brightness slider, volume slider (w/ per-app
  sliders), battery level", custom items, power menu; "GTK3-based panel for
  sway and Hyprland" ([README][nwgpanel]). No Wi-Fi/BT lists, and Mango is
  not a target.
- **eww** has no service libraries; every value is a script or `deflisten`
  stream, so a Wi-Fi list is `nmcli` parsing as in end-4. Last release
  2024-04 (components research §4).

## 3. Backends and their limits

| Backend              | Interface           | Limit for a popup                       |
|----------------------|---------------------|-----------------------------------------|
| NetworkManager       | D-Bus, libnm, nmcli | secrets need a SecretAgent              |
| iwd                  | D-Bus               | own agent API; not used on this machine |
| BlueZ                | D-Bus               | PIN/passkey needs an Agent1             |
| PipeWire/WirePlumber | native, wpctl       | QS has nodes only, no profiles/routes   |
| UPower               | D-Bus               | none for a popup                        |
| power-profiles-d.    | D-Bus (QS UPower)   | none; enabled in `modules/mango`        |
| backlight            | sysfs, logind       | no QS module; brightnessctl or logind   |

Notes:

- Writing `/sys/class/backlight/*/brightness` needs group access; the module
  installs swayosd's udev rule and adds the user to `video`
  (`modules/mango/default.nix`). logind's `Session.SetBrightness()` is the
  unprivileged alternative ([org.freedesktop.login1][logind]); brightnessctl
  already handles this, so no change is needed.
- Only one process can own `org.freedesktop.Notifications`
  ([Desktop Notifications spec][notif-spec]); a Quickshell
  `NotificationServer` and mako cannot both run.

## 4. Recommendation for this repo

Native in QML (`modules/mango/quickshell/shell.qml`, or split files once it
grows past one screen):

1. **Wi-Fi popup** opened from waybar's `network` `on-click` via
   `popupToggle "network"`. On open set `scannerEnabled = true`, off on
   close. List `networks` sorted by `connected`, `known`, `signalStrength`.
   Click: `connect()`; on `connectionFailed` with `NoSecrets` and a PSK
   `security`, show an inline password field and call `connectWithPsk`.
   Row actions: disconnect, forget. Footer: Wi-Fi toggle (moved from Quick
   controls) and "Network settings…" running `nm-connection-editor`.
   Enterprise, VPN and hidden networks fall through to nm-applet.
2. **Bluetooth popup** from a new waybar `bluetooth` module (waybar has
   one; check its options before use). `discovering` on while open; lists
   from `Bluetooth.devices` split as end-4 does; `connect()`, `pair()`
   (then `trusted = true`), `forget()`, battery percentage when available.
   blueman-applet stays as the pairing agent; "Bluetooth settings…" runs
   `blueman-manager`.
3. **Audio popup** from `wireplumber`'s `on-click`: master slider, output
   list (`isSink && !isStream`) and input list switching via
   `preferredDefaultAudioSink`/`Source`. Per-app sliders over `isStream`
   nodes only if the spec drops "per-app mixers" from out of scope.
   "Sound settings…" runs `pwvucontrol` for profiles and ports. Every node
   shown needs a `PwObjectTracker` binding.
4. **Quick controls** stays the overview. Optional: arrows on its Wi-Fi and
   Bluetooth toggles that open the popups above (GNOME pattern).
5. **Media card** (optional) from `Mpris.players`, small and native.

Delegate, unchanged: nm-applet and blueman-applet (agents and tray menus),
hyprpolkitagent, mako, swayosd, the fuzzel power menu.

Not recommended: porting end-4/caelestia network services (nmcli parsing
replaced by the native module), AGS/Astal (not in nixpkgs), launcher menus
(a second UI idiom next to the popups), adopting Dux Shell or Noctalia (the
pieces-vs-shell decision in components research §5 still stands; revisit
only if VPN/enterprise/hotspot UI is wanted, where both are far ahead).

Build check: the existing `qmlCheck` already lints with
`--unresolved-type disable` because `BluetoothAdapter` is not visible to
qmllint; expect the same for `WifiNetwork` and `BluetoothDevice` delegates.

## 5. Risks and open questions

- **Quickshell API churn.** `Quickshell.Networking` is one minor release
  old; type names in this file come from 0.3.2 and may change.
- **Pairing without an agent prompt.** If blueman-applet's agent is not
  registered (applet crashed), `pair()` on a keyboard that needs a passkey
  will fail silently from the popup. Not tested.
- **NoSecrets flow.** With nm-applet running, NetworkManager may ask
  nm-applet's agent for the PSK before `connectionFailed` reaches the popup,
  so a GTK dialog could appear instead of the inline field. Not tested;
  check which wins on first connect.
- **Profiles.** Bluetooth headset A2DP/HFP switching stays in pwvucontrol
  until Quickshell exposes PipeWire devices.
- **Not verified:** that waybar's `bluetooth` module options match its
  wiki today; the quickshell.org docs pages (404 at the URL tried).

[qs]: https://github.com/quickshell-mirror/quickshell
[qs-ch030]: https://github.com/quickshell-mirror/quickshell/blob/master/changelog/v0.3.0.md
[qs-netmod]: https://github.com/quickshell-mirror/quickshell/blob/master/src/network/module.md
[qs-net]: https://github.com/quickshell-mirror/quickshell/blob/master/src/network/network.hpp
[qs-wifi]: https://github.com/quickshell-mirror/quickshell/blob/master/src/network/wifi.hpp
[qs-btmod]: https://github.com/quickshell-mirror/quickshell/blob/master/src/bluetooth/module.md
[qs-btdev]: https://github.com/quickshell-mirror/quickshell/blob/master/src/bluetooth/device.hpp
[nm-agent]: https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.SecretAgent.html
[bz-agent]: https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst
[nma-agent]: https://gitlab.gnome.org/GNOME/network-manager-applet/-/blob/main/src/applet-agent.c
[e4-net]: https://github.com/end-4/dots-hyprland/blob/main/dots/.config/quickshell/ii/services/Network.qml
[e4-bt]: https://github.com/end-4/dots-hyprland/blob/main/dots/.config/quickshell/ii/services/BluetoothStatus.qml
[e4-audio]: https://github.com/end-4/dots-hyprland/blob/main/dots/.config/quickshell/ii/services/Audio.qml
[e4-bright]: https://github.com/end-4/dots-hyprland/blob/main/dots/.config/quickshell/ii/services/Brightness.qml
[cl-nmcli]: https://github.com/caelestia-dots/shell/blob/main/services/Nmcli.qml
[cl-audio]: https://github.com/caelestia-dots/shell/blob/main/services/Audio.qml
[cl-bright]: https://github.com/caelestia-dots/shell/blob/main/services/Brightness.qml
[dux-net]: https://github.com/duxlabs-dev/dux-shell/tree/main/core/internal/server/network
[dux-bz]: https://github.com/duxlabs-dev/dux-shell/blob/main/core/internal/server/bluez/agent.go
[noct-net]: https://github.com/noctalia-dev/noctalia/tree/main/src/dbus/network
[noct-bt]: https://github.com/noctalia-dev/noctalia/tree/main/src/dbus/bluetooth
[sio-net]: https://github.com/sioodmy/nixus/blob/main/user/quickshell/ui/NetworkView.qml
[nick-net]: https://github.com/nicknisi/dotfiles/blob/main/config/quickshell/NetMenu.qml
[astal-ref]: https://aylur.github.io/astal/guide/libraries/references
[nmdmenu]: https://github.com/firecat53/networkmanager-dmenu
[iwmenu]: https://github.com/e-tho/iwmenu
[bzmenu]: https://github.com/e-tho/bzmenu
[pwmenu]: https://github.com/e-tho/pwmenu
[wb-menu]: https://github.com/Alexays/Waybar/wiki/Module:-Custom:-Menu
[swaync]: https://github.com/ErikReider/SwayNotificationCenter
[nwgpanel]: https://github.com/nwg-piotr/nwg-panel
[logind]: https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html
[notif-spec]: https://specifications.freedesktop.org/notification-spec/latest/
