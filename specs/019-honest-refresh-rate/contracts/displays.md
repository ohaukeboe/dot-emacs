# Contract: Displays card, honest refresh rate

Changes the [specs/018 contract][018].
IPC, keys, reading and `mango-display-setup` are unchanged.

## Dry run

Not used. `wlr-randr --dryrun` makes the tested display's background
blink on Mango 0.18.5 (research R5), so the card never sends it.

## Applying (replaces the exit-code rule of specs/018)

The call is unchanged. Its exit code is no longer read as "applied" or
"nothing changed": Mango commits display by display, so a non-zero exit
can leave some displays changed (research R3). After the process exits
the card reads the real state once and decides:

| The real state                | The card                             |
|-------------------------------|--------------------------------------|
| equals the state before       | idle, shows it, Apply unavailable    |
| differs from the state before | keep question, 10 s, as in specs/018 |

In both rows, when the real state differs from what was asked, the header
shows the not-taken line ([data-model.md](../data-model.md)) until the
next edit, Keep, Revert or close.

Revert is unchanged. A failed Revert still shows "Could not revert".

## Refresh rate choice

Unchanged from specs/018: every reported rate of the shown resolution.

[018]: ../../018-display-layout-card/contracts/displays.md
