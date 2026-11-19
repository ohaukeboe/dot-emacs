# Contract: Displays card

## IPC

Call form: `qs -c mango ipc call displays toggle`, with `qs` by store
path. Added to the targets of
`specs/014-quickshell-rail/contracts/rail-ipc.md`.

| Target     | Function   | Returns | Effect                 |
|------------|------------|---------|------------------------|
| `displays` | `toggle()` | nothing | Open, or close if open |

- Opens on the display under the pointer, like every IPC toggle.
- Opening it closes any other popup, and the reverse. Closing during the
  keep question reverts.
- `shell openTarget` returns `displays` while it is open.
- The launcher entry "Displays" runs the same call.

## Keys

| Key         | In idle                          | In the keep question |
|-------------|----------------------------------|----------------------|
| `Enter`     | Apply, when something is pending | Keep                 |
| `Esc`       | close, pending changes dropped   | Revert               |
| `Tab`       | select the next display          | nothing              |
| `Shift+Tab` | select the previous display      | nothing              |

A click outside the card acts as `Esc`.

## Reading

`wlr-randr --json`. The card uses, per output: `name`, `make`, `model`,
`serial`, `enabled`, `modes[]` (`width`, `height`, `refresh`,
`preferred`, `current`), `position` (`x`, `y`), `transform`, `scale`,
`adaptive_sync`. Other fields are ignored. Output that is not valid JSON
leaves the card on its last good state with the status "Could not read
the displays".

## Applying

One call. Every connected display has one group, in the order read. For a
display that copies another, `--pos` is defined in
[specs/020 contracts/displays.md](../../020-duplicate-display/contracts/displays.md).

```text
wlr-randr
  --output <name> --on --mode <w>x<h>@<refresh>Hz --pos <x>,<y>
      --scale <scale> --transform <transform>
      [--adaptive-sync enabled|disabled]
  --output <name> --off
```

- `<refresh>` is the mode's value as read, all digits.
- `--adaptive-sync` is present only when it differs from the applied
  layout (research R8).
- Positions are already normalised to 0,0 (FR-019).
- The exit code does not tell what changed: Mango commits display by
  display. See specs/019-honest-refresh-rate/contracts/displays.md.
- Revert is the same call built from the previous layout, with
  `--adaptive-sync` for every display whose value differs from the
  current one.

## mango-display-setup

```text
mango-display-setup [--copy] [NAME]
```

- Unchanged without `--copy`: prints the entry for the connected displays.
- With `--copy`: puts the same text on the clipboard and prints nothing.
  Exit 0 on success. The card then shows "Copied. Paste into
  machines/machines.nix".
- `NAME` defaults to `new-setup`.

## Which setup matches

`kanshictl status`; the card reads the text after `Current profile: `.
`undocked` is shown as "Undocked". A missing line, an empty name or a
failed call is shown as "No saved setup matches".
