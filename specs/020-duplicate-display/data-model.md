# Data Model: Duplicate Display

Nothing is stored. This extends
[specs/018 data-model.md](../018-display-layout-card/data-model.md).

## Display

One new field.

| Field    | Type   | Notes                                                   |
|----------|--------|---------------------------------------------------------|
| `copyOf` | string | name of the source; "" for a display that is not a copy |

For a copy, `x` and `y` in the card's layouts are its source's. `scale`
is kept as read and never offered. `mode`, `transform`, `enabled` and
`adaptiveSync` are its own.

Derived, in `displayLayout.mjs`:

- **placed**: enabled and `copyOf` is "". Only placed displays have a
  rectangle, snap, settle and count for the arrangement's connectedness.
- **stack of `s`**: `s` and every display whose `copyOf` is `s`.
- **copies in order**: the copies of the whole layout, in the order the
  displays were read. The n-th one has slot n.

## Parked position

What `wlr-randr` holds for a copy (research R3, R4), with `gap` 8192:

```text
x = source.x
y = source.y + slot × gap        slot = 1, 2, 3
```

`unpark` (on read): a display with `y >= gap` is a copy of the enabled
display at `(x, y mod gap)` whose own `y` is below the gap. With no such
display it is an **orphan**: `copyOf` stays "" and `orphan` is true until
`repair` has placed it.

`park` (on apply): the reverse, slots given in order.

## Layout

The rules of specs/018, read for the placed displays, plus:

1. A copy's source is enabled and is not itself a copy (FR-003).
2. A copy is enabled. Turning a copy off clears `copyOf`.
3. At most 3 copies.
4. With any copy, the placed displays' bounding box is under `gap` tall,
   and every copy's logical height is under `gap`.
5. No orphan.

`same` compares `copyOf` along with the fields it already compares, and
ignores `x`, `y` and `scale` of a copy.

## Operations

All return a new layout that keeps the rules; each ends with `settle`.

| Operation                 | Does                                                     |
|---------------------------|----------------------------------------------------------|
| `stack(l, name, target)`  | `name` and its copies become copies of `target`'s source |
| `separate(l, name)`       | clears `copyOf`; placed right of the others (FR-007)     |
| `makeSource(l, name)`     | swaps roles; the stack stays, neighbours make room       |
| `setEnabled(l, name, on)` | a source going off promotes its first copy (FR-026)      |
| `repair(l)`               | promotes for a lost source; separates other orphans      |
| `arrange(l, choice, ctx)` | the layout a switch choice describes (FR-009)            |

`stack` does nothing when `target` is `name`, is off, or is already in
`name`'s stack, and when the result would break rule 3 or 4; the caller
then shows why.

## Arrangement

Not stored: derived from a layout by `arrangement(layout, panel)`.

| Value       | The layout it names                                    |
|-------------|--------------------------------------------------------|
| `extend`    | every display enabled, none a copy                     |
| `duplicate` | every display enabled, one source, the rest its copies |
| `panel`     | the panel enabled, every other display off             |
| `external`  | the panel off, every other enabled, none a copy        |
| ""          | anything else; the switch marks nothing                |

"Every display" leaves out a panel that is off while the lid is closed.
`choices(layout, panel)` lists what the switch offers: nothing with one
connected display; `extend` and `duplicate` with two or more; all four
when the panel and at least one other display are connected.

`arrange` takes `ctx = { panel, lidClosed, selected }`. For `duplicate`
the source is the panel when it is connected and the lid is open, else
the selected display, else the first enabled one (FR-010). A display that
already is as the choice describes keeps every value (FR-011).

## Card state

The states and transitions of specs/018 are unchanged. Added:

- `Displays.lidClosed`: read when the card opens.
- **Repair**, in any state and also while closed: a read that finds an
  orphan, or a copy whose source is off, applies `repair` at once with no
  keep question. In `confirming` it ends the question without reverting,
  like a hotplug (specs/018 FR-021).
- **Guard**: runs while the applied layout has a copy; restarted when the
  pairs change.

## Selection

`selected` may name a copy. `select()` after an Apply keeps it. A click
on a stack tile selects the source.
