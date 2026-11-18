# Contract: Popup IPC (extends spec 012)

> Superseded by `specs/014-quickshell-rail/contracts/rail-ipc.md`: waybar,
> its signals and `mango-rail-module` are gone; the IPC targets are unchanged.

Supersedes `specs/012-mango-rail-bar/contracts/popup-ipc.md` for the Mango
session. Call form: `qs -c mango ipc call <target> <function>`, with `qs`
by store path.

## Targets

| Target     | Function       | Returns | Effect                       |
|------------|----------------|---------|------------------------------|
| `controls` | `toggle()`     | nothing | Open, or close if open       |
| `calendar` | `toggle()`     | nothing | Open, or close if open       |
| `usage`    | `toggle()`     | nothing | Open, or close if open       |
| `shell`    | `openTarget()` | string  | `""` or the open target name |

Opening one target closes the others. Calls return immediately.

## Quickshell to waybar

Quickshell signals waybar so modules re-run their `exec`:

| Signal     | Sent when                         | Modules that listen             |
|------------|-----------------------------------|---------------------------------|
| `RTMIN+8`  | `openTarget` changes              | `custom/clock`,                 |
|            |                                   | `custom/claude-usage`           |
| `RTMIN+9`  | Reachable phone count changes     | `custom/phone`                  |

Modules learn the open popup from `$XDG_RUNTIME_DIR/mango-popup`, which
Quickshell rewrites with the open target name (empty when closed) before it
sends `RTMIN+8`. Reading the file is faster than a `qs ipc call` per module;
`shell.openTarget()` stays for scripts.

## Waybar modules

Each prints one line through `mango-rail-module <name>`: JSON
(`return-type = "json"`) except `custom/phone`, which prints plain text. An
empty `text` or line hides the module.

| Module                | `text`        | Classes                    | Click          |
|-----------------------|---------------|----------------------------|----------------|
| `custom/clock`        | date, time    | `open`                     | `calendar`     |
| `custom/claude-usage` | `42%` (shown  | `open`, `stale`, `pN`      | `usage`        |
|                       | as the ring)  |                            |                |
| `custom/phone`        | phone icon    | none                       | `controls`     |

- `custom/phone`, `network`, `wireplumber` and `battery` sit in
  `group/controls`, one
  `raised` capsule; each opens `controls`. There is no gear.
- `custom/claude-usage` sets `format = " "`, so the label is blank and the
  percentage shows only in the tooltip. It adds a `pN` class (session percentage rounded to
  5) that selects the ring drawn as its background, and prints an empty
  line when `limits.json` is missing.
- `custom/phone` prints an empty line when no paired device is reachable,
  and is not generated at all when KDE Connect is off.
- The clock also refreshes on a 5 second interval.
