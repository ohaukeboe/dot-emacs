# Contract delta: popup keys and `serve` intents

Two contracts change. This file states the change; the files themselves
are updated during implementation and stay the single source.

## 1. `cosmic-pass` `specs/004-serve-mode/contracts/serve-protocol.md`

Add to the intent table:

| `t`             | Other fields | `Msg`          |
|-----------------|--------------|----------------|
| `copy_username` |              | `CopyUsername` |
| `copy_totp`     |              | `CopyTotp`     |
| `copy_url`      |              | `CopyUrl`      |
| `retry`         |              | `Startup`      |

Guarantees 1 to 5 apply unchanged; guarantee 3 (no copied value in a
snapshot) covers the new copies.

## 2. `specs/016-proton-pass-quick-access/contracts/shell.md`

The keys table becomes:

| Key                    | Item list               | Field list              |
|------------------------|-------------------------|-------------------------|
| typing                 | filter                  | (none)                  |
| `Up`, `Ctrl+P`         | previous item           | previous field          |
| `Down`, `Ctrl+N`       | next item               | next field              |
| `PageUp`, `PageDown`   | a page of items         | a page of fields        |
| `Enter`                | copy main value, close  | copy field, close       |
| `Ctrl+U`               | copy username, close    | copy username, close    |
| `Ctrl+O`               | copy one-time code      | copy one-time code      |
| `Ctrl+L`               | copy website, close     | copy website, close     |
| `Tab`                  | open the field list     | (none)                  |
| `Right`                | field list if no query  | (none)                  |
| `Left`, `Shift+Tab`    | (text cursor / none)    | back to the item list   |
| `Ctrl+R`               | (none)                  | reveal or hide          |
| `Esc`                  | close                   | back to the item list   |
| `F5`                   | refresh                 | refresh                 |
| `Ctrl+Shift+S`         | sign in, when offered   | (none)                  |
| `Ctrl+Shift+R`         | retry: locked/error/CLI | (none)                  |

`Ctrl+O` closes the popup like the other copies. `Ctrl+J`, `Ctrl+K` and
`Ctrl+,` are not bound. The note under the table loses nothing; add: "The
keys match the COSMIC popup's defaults (`cosmic-pass`
`specs/001-quick-access-launcher/contracts/keyboard.md`) except `Ctrl+J`,
`Ctrl+K` and `Ctrl+,`."
