# Data Model: Honest Refresh Rate

Adds to [specs/018 data-model](../018-display-layout-card/data-model.md).
Nothing is stored.

## Asked layout

The pending layout at the moment of Apply.

- Set when Apply starts; cleared when the outcome is decided.
- Compared display by display with the applied layout read after the
  Apply process exits, with the same fields that decide `same` in
  specs/018 (mode, position, scale, transform, adaptive sync, on/off).

## Outcome of an Apply

Derived from three layouts: previous (before Apply), asked, and the real
one read after.

| Real vs previous | Real vs asked | Phase after | Line          |
|------------------|---------------|-------------|---------------|
| same             | differs       | idle        | not-taken     |
| differs          | same          | confirming  | none          |
| differs          | differs       | confirming  | not-taken     |
| same             | same          | idle        | none          |

- The exit code of the Apply process is not an input (research R3).
- In every row pending becomes the real layout.
- A hotplug between Apply and the read follows specs/018 FR-021.

## Not-taken line

For the displays whose real state differs from the asked one
(research R7):

- one display, mode differs: "<label> cannot run at <rate> Hz here"
- one display, other difference: "<label> did not take the change"
- several: "Some displays did not take the change"

## Unusable modes, probe queue, offered rates

Removed with story 2 (research R5). The card offers every reported rate.
