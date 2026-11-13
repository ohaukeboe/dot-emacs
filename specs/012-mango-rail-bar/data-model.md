# Data Model: Mango Rail Bar

No persisted data. The "entities" are the configuration pieces the module
renders and the state the popups read live.

## Rail (waybar `settings.main`)

| Field            | Value                                             |
|------------------|---------------------------------------------------|
| `position`       | `left`                                            |
| `width`          | `32` (FR-002)                                     |
| `modules-left`   | `mango/workspaces`                                |
| `modules-center` | `clock`                                           |
| `modules-right`  | `group/tray`, `network`, `wireplumber`,           |
|                  | `power-profiles-daemon`, `battery`,               |
|                  | `custom/controls`                                 |

Rules: no module sets `rotate`; every status module shows `{icon}` only and
has a tooltip; colours come from `bg`, `card`, `accent` in
`modules/mango/default.nix` (FR-013).

## Workspace button (from `mango/workspaces`)

| State         | Shown as                  | Source class            |
|---------------|---------------------------|-------------------------|
| active        | accent pill with number   | `.active`               |
| occupied      | grey dot, no number       | no `.empty`             |
| urgent        | dot with accent outline   | `.urgent`               |
| empty         | hidden                    | `hide-empty: true`      |

## Quick controls (Quickshell popup)

| Control    | Reads / writes                             | Hidden when     |
|------------|--------------------------------------------|-----------------|
| Volume     | `Pipewire.defaultAudioSink.audio.volume`   | no sink         |
| Brightness | `brightnessctl -m`, `brightnessctl set N%` | no backlight    |
| Mic mute   | `Pipewire.defaultAudioSource.audio.muted`  | no source       |
| Wi-Fi      | `Networking` Wi-Fi enabled                 | no Wi-Fi device |
| Bluetooth  | `Bluetooth.defaultAdapter.enabled`         | no adapter      |
| Profile    | `PowerProfiles.profile` (3-way)            | ppd not running |
| Battery    | `UPower.displayDevice` percent, state      | no battery      |
| Power      | runs `mango-power-menu`, closes popup      | never           |

Wi-Fi, Bluetooth and the volume row carry a `›` that swaps the card to a
detail page (FR-015, FR-016). Each page has a `‹` back control; closing the
popup always reopens it on the tiles.

| Page      | Lists (sorted)                              | Actions                     |
|-----------|---------------------------------------------|-----------------------------|
| Wi-Fi     | `WifiDevice.networks`: connected, saved,    | connect, disconnect,        |
|           | signal; scanner on while the page is open   | inline PSK, forget          |
| Bluetooth | adapter `devices`: connected, paired, name  | scan, connect, disconnect,  |
|           |                                             | pair (then connect), forget |
| Sound     | `Pipewire.nodes`: output and input devices, | set default device; per-app |
|           | then app streams (`isStream`)               | volume and mute             |

Password and PIN prompts the popup cannot answer come from nm-applet and
blueman-applet, which stay running as the session's agents.

State transitions: `closed --toggle--> open on the monitor under the pointer`;
`open --toggle | Escape | click outside | power button--> closed`. Opening
one popup closes the other.

## Calendar (Quickshell popup)

Month grid with ISO week numbers, today highlighted, previous/next month
buttons. Same open/close transitions as quick controls.
