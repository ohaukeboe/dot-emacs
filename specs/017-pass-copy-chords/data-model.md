# Data Model: Proton Pass Copy Chords

No new state in either repository. The only data change is four rows in
the `serve` intent table (authoritative in
`~/projects/cosmic-pass/specs/004-serve-mode/data-model.md`):

| `t`             | Argument | `Msg`          |
|-----------------|----------|----------------|
| `copy_username` |          | `CopyUsername` |
| `copy_totp`     |          | `CopyTotp`     |
| `copy_url`      |          | `CopyUrl`      |
| `retry`         |          | `Startup`      |

Rules carried over unchanged from the reducer:

- The target is `target_item()`: the highlighted row in list mode, the open
  item in fields mode.
- Username falls back to email; one-time code and website take the first.
- A missing value sets `notice` ("This item has no …") and copies nothing.
- A successful copy sets `visible` to `false`, as `copy_primary` does.

The snapshot gains no field.
