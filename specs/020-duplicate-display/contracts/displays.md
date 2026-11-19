# Contract: Duplicate display

Extends
[specs/018 contracts/displays.md](../018-display-layout-card/contracts/displays.md).
The IPC target is unchanged.

## Keys

Added to the idle column; nothing changes in the keep question.

| Key     | In idle                                                      |
|---------|--------------------------------------------------------------|
| `Right` | the arrangement switch moves one choice right; first if none |
| `Left`  | one choice left; last if none                                |
| `Tab`   | selects the next display, copies included                    |

`Left` and `Right` do nothing while a list of choices is open, with one
connected display, and at the end of the switch.

## Reading

`wlr-randr --json` as before, then `unpark`
([data-model.md](../data-model.md), "Parked position").

## Applying

One call, as before. For a copy the group is:

```text
--output <name> --on --mode <w>x<h>@<refresh>Hz
    --pos <source x>,<source y + slot × 8192>
    --scale <scale> --transform <transform>
```

- Slots are given in the order the displays were read, starting at 1.
- The placed displays are normalised to 0,0 first, so every placed
  display has `y` below 8192 and every copy at or above it.
- Revert is the same call from the previous layout.

## The mirror

For each display the applied layout names as a copy, the shell shows one
layer surface on it.

| Property   | Value                                                     |
|------------|-----------------------------------------------------------|
| namespace  | `mango-mirror`                                            |
| layer      | overlay                                                   |
| anchors    | all four edges; no exclusive zone; no keyboard focus      |
| background | black                                                     |
| content    | the source's picture with the pointer, fitted and centred |

It is there within 1 s of the read that shows the copy, and gone within
1 s of the read that shows none.

## mango-copy-guard

```text
mango-copy-guard COPY=SOURCE [COPY=SOURCE ...]
```

Runs until killed. Names are connector names. On start, and on every line
from `mmsg watch all-monitors` or `mmsg watch all-clients`:

1. Every client whose monitor is a `COPY` is sent to its `SOURCE`:
   `mmsg dispatch "tagmon,SOURCE,0" "client,ID"`.
2. When the active monitor is a `COPY`, focus goes on to the next monitor
   that is not a copy, in the direction focus arrived from (the order of
   `mmsg get all-monitors`), with `mmsg dispatch "focusmon,NAME"`. When
   the direction is not known, to its `SOURCE`.

Exit 2 with a usage line on an argument that is not `COPY=SOURCE`. The
shell starts it after an Apply or a read that shows a copy, and restarts
it when the pairs change. It ends by itself when the process that started
it is gone.

## mango-lid-sync

```text
mango-lid-sync state
```

New argument. Prints `open` or `closed` and exits 0; `open` on a machine
with no lid. The other forms are unchanged.

## mango-display-setup

Unchanged call. A display parked as a copy is written as enabled at
`y = 0`, right of every other display, in the order read. The entry so
describes the displays as extended (FR-029).

## Status lines

| When                              | Line                                 |
|-----------------------------------|--------------------------------------|
| a fourth copy is asked for        | At most three displays can duplicate |
| the layout is too tall for a copy | This layout is too tall to duplicate |
| a source went away                | The source is gone; duplicate ended  |
| Copy as setup with a copy applied | Copied without the duplicate         |
