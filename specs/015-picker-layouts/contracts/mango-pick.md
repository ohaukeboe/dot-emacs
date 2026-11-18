# Contract: mango-pick

```text
mango-pick [--layout LAYOUT] [PROMPT] < lines
```

- **stdin**: one item per line; empty lines are dropped. Line format per layout
  is in `../data-model.md` (Picker item).
- **LAYOUT**: `tiles`, `sources` or `clipboard`. Absent, empty or unknown:
  the list layout.
- **PROMPT**: defaults to `Select`.
- **stdout**: the picked item's return value and a newline: the whole line,
  except `tiles`, which returns the label field.
- **Exit status**:

| Status | Meaning                                                 |
|--------|---------------------------------------------------------|
| 0      | picked                                                  |
| 1      | cancelled, no items, or no answer within 300 s          |
| 10     | picked with the alternate key (clipboard: Ctrl+Enter)   |

## Shell IPC (internal; only mango-pick calls it)

```text
qs -c mango ipc call picker open PROMPT ITEMS REPLY_FIFO LAYOUT
```

The shell writes exactly one reply to `REPLY_FIFO` per request:

| Reply             | mango-pick does                     |
|-------------------|-------------------------------------|
| empty             | exit 1                              |
| `VALUE`           | print `VALUE`, exit 0               |
| `alt<TAB>VALUE`   | print `VALUE`, exit 10              |

## Callers

| Caller                   | Layout      | Handles status 10            |
|--------------------------|-------------|------------------------------|
| `mango-power-menu`       | `tiles`     | no                           |
| xdpw screencast chooser  | `sources`   | no (treats non-0 as cancel)  |
| `mango-clip-pick`        | `clipboard` | yes: copy without paste      |
