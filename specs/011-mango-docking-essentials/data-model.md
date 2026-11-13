# Data Model: Mango Docking and Session Essentials

## Display setup

Declared per machine in `machines/machines.nix` as
`modules.mango.displays.setups.<name>`. Rendered to one kanshi profile each.

| Field     | Type                           | Rule                                  |
|-----------|--------------------------------|---------------------------------------|
| `<name>`  | attribute name                 | kanshi profile name; not `undocked`   |
| `outputs` | non-empty list of Output below | criteria unique within the setup      |

## Output (inside a setup)

| Field      | Type                    | Default  | Rule                              |
|------------|-------------------------|----------|-----------------------------------|
| `criteria` | non-empty string        | -        | "Make Model Serial" or a name     |
| `enable`   | bool                    | `true`   | -                                 |
| `mode`     | null or `WxH[@R]` match | `null`   | `null` = preferred mode           |
| `position` | `{ x, y }` unsigned int | `0, 0`   | no negative coords (XWayland)     |
| `scale`    | null or positive float  | `null`   | `null` = compositor default       |

Evaluation-time checks (assertions in `modules/mango/default.nix`):

- each setup has at least one output;
- no two outputs in a setup share `criteria`;
- no setup is called `undocked`;
- at least one output per setup is enabled;
- `mode` matches `^[0-9]+x[0-9]+(@[0-9.]+(Hz)?)?$` (a `types.strMatching`).

## Internal panel

`modules.mango.displays.internal`: the laptop panel's output name, a
non-empty string, default `"eDP-1"`. Used by the generated `undocked`
profile and by `mango-lid-sync`.

## Generated profiles

| Profile    | Source             | Matches                   | exec             |
|------------|--------------------|---------------------------|------------------|
| `undocked` | always             | the internal panel alone  | `mango-lid-sync` |
| `<name>`   | each setup entry   | exactly its outputs       | `mango-lid-sync` |
| (none)     | -                  | anything else: Mango auto | -                |

## Panel state (runtime, not stored)

| Lid    | Other output connected | Panel                                     |
|--------|------------------------|-------------------------------------------|
| open   | any                    | as the matched profile says (or on)       |
| closed | yes                    | off (`disable_monitor`), logind ignores   |
| closed | no                     | logind suspends (ADR 0001)                |
