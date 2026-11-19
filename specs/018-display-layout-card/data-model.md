# Data Model: Display Layout Card

Nothing is stored. These are the values the `Displays` singleton holds
while the card is open.

## Display

One entry of `wlr-randr --json`. Since specs/020-duplicate-display also
`copyOf`, see [its data model](../020-duplicate-display/data-model.md).

| Field                     | Type               | Notes                             |
|---------------------------|--------------------|-----------------------------------|
| `name`                    | string             | connector (`eDP-1`); the key      |
| `make`, `model`, `serial` | string or null     | label is `model`, else `name`     |
| `modes`                   | list               | size, refresh, preferred          |
| `enabled`                 | bool               |                                   |
| `mode`                    | index into `modes` | only meaningful when enabled      |
| `x`, `y`                  | int                | logical pixels, top-left          |
| `scale`                   | real               |                                   |
| `transform`               | string             | `normal`, `90`, ... `flipped-270` |
| `adaptiveSync`            | bool               |                                   |

Derived, in `displayLayout.mjs`:

- **logical size**: `floor(width / scale)` by `floor(height / scale)`,
  swapped for a 90 or 270 transform (research R5).
- **resolutions**: the distinct `width` x `height` pairs of `modes`,
  largest first. **refresh rates**: the modes of the chosen resolution,
  highest first. Choosing a resolution picks its highest rate.
- A display that was off when read has no current mode; turning it on in
  the card selects its preferred mode, scale 1, no rotation.

## Layout

A list of displays, one per connected output. Rules for a layout the card
may apply (`valid` in `displayLayout.mjs`):

1. At least one display is enabled (FR-014).
2. No two enabled displays overlap (FR-009).
3. With more than one enabled, each shares part of an edge with another,
   and all are connected through such edges (FR-009).
4. The smallest `x` and the smallest `y` of the enabled displays are 0
   (FR-019).

The card holds three:

| Layout   | What it is                    | Set when                       |
|----------|-------------------------------|--------------------------------|
| applied  | the real state                | every read (research R2)       |
| pending  | what the card draws and edits | copied from applied; each edit |
| previous | what Revert restores          | copied from applied at Apply   |

`dirty` is true when pending differs from applied.

## Card state

The property is `Displays.phase`.

| State      | Shown                    | Leaves on                          |
|------------|--------------------------|------------------------------------|
| closed     | nothing                  | open command                       |
| idle       | layout, settings, Apply  | edit; Apply when dirty; close      |
| applying   | controls inert           | `wlr-randr` exits                  |
| confirming | keep question, countdown | Keep; Revert; 10 s; close; hotplug |

Transitions:

- closed to idle: read, pending = applied, select the display the card is
  on.
- idle, Apply: previous = applied, run the apply call, go to applying.
- applying, exit 0: read, go to confirming, start the 10 s countdown.
- applying, other exit: stay in idle with pending kept, status "The
  change was refused" (FR-018).
- confirming, Keep or Enter: go to idle.
- confirming, Revert, Esc, countdown end, or the card closing: apply
  previous, read, go to idle or closed.
- confirming, hotplug: go to idle without reverting (FR-021).
- idle, hotplug or applied changed from outside: pending = applied,
  status says why.

## Selection and status

- `selected`: the `name` of one display; always set while open (FR-007).
  When that display is removed, the first enabled one is selected.
- `setup`: the profile name from `kanshictl status`, or empty
  (research R6).
- `status`: one line under the title; the setup name when there is
  nothing else to say.
