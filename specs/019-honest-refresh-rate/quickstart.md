# Quickstart: Honest Refresh Rate

Validation by hand. Needs the laptop in the dock with the Odyssey G80SD
connected as on 2026-11-18 (3840×2160 at 60 Hz; 120 Hz refused). Without
it, H1 to H6 cannot be shown; H8 and H9 still can.

## Build checks

```bash
nix fmt
nix flake check
just qs-check
nix build '.#nixosConfigurations.<hostname>.config.system.build.toplevel'
```

The last one runs `qmlCheck` and `mango-display-layout-test`, which
holds the cases for the not-taken line ([data-model.md](data-model.md)).

## Reference: what the session refuses

```bash
wlr-randr --output DP-7 --mode 3840x2160@120.000000Hz --dryrun; echo $?
```

Prints `failed to apply configuration` and `1`. If it prints `0`, the
connection now carries 120 Hz and H4 has nothing to show. Run it
sparingly: each dry run makes the Odyssey's background blink.

## By hand

Open the card: `qs -c mango ipc call displays toggle`.

- **H1 to H3**: removed with story 2.
- **H4**: select the Odyssey, pick 120 Hz and press Enter. The rate
  shows 60 Hz, the
  header says "Odyssey G80SD cannot run at 120 Hz here", and no keep
  question appears.
- **H5**: as H4, but first drag the ASUS to the other side. The keep
  question appears, the rate shows 60 Hz, the line names the Odyssey, and
  Revert moves the ASUS back.
- **H6**: after H4, press "Copy as setup" and paste. The entry says 60 Hz
  for the Odyssey.
- **H7**: open the card, select each display with Tab, wait 10 s. No
  display blinks, no window moves.
- **H8**: panel: pick 60 Hz, Enter, Keep. As before this feature: the
  question, then 60 Hz.
- **H9**: panel: pick 60 Hz, Enter, wait. Reverts to 120 Hz between 10
  and 11 s.

Maps to: H4 story 1, SC-002 and SC-003; H5
story 1 scenarios 3 and 4; H6 FR-010; H7 SC-005 and research R5; H8 and H9 SC-004
and specs/018 unchanged.

H5 depends on the order in which the session changes the displays: if
the Odyssey comes first and fails, the ASUS may still move. Either way
the card must end showing the real state.
