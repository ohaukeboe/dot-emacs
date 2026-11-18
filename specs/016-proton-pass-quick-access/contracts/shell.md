# Contract: the popup in the Mango session

What this repository exposes: an option, an IPC target, a key binding and
the popup's keys.

## Option

```nix
modules.mango.pass.clipboardClearSeconds
# type: types.ints.between 10 600, default: 90
```

Seconds a copied secret stays on the clipboard. Declared in
`modules/mango/default.nix`; contributes nothing when `modules.mango.enable`
is off.

## IPC

```text
quickshell -c mango ipc call pass toggle
```

Opens the popup on the focused monitor, or closes it if it is open. Opening
replaces any other open Rail popup. The Rail's `openTarget` is `"pass"` while
it is open, so `ipc call shell openTarget` and `ipc call shell close` work as
for every other target.

## Key binding

`Super+Space` runs the IPC call above. It no longer starts `proton-pass`,
which is started from the launcher.
`Super+Shift+Space` (1Password) is unchanged.

## Keys in the popup

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

The keys match the COSMIC popup's defaults (`cosmic-pass`
`specs/001-quick-access-launcher/contracts/keyboard.md`) except `Ctrl+J`,
`Ctrl+K` and `Ctrl+,` (specs/017). `Ctrl+O` closes the popup like the
other copies; `Ctrl+Shift+R` retries only for `locked`, `error` and
`cli_missing`.

Pointer: a click on a row is `Enter` on it; an item row's "Fields" is `Tab`
on it; the header's back button is `Esc` in the field list; a secret row's
"Reveal" / "Hide" is `Ctrl+R` on it; the refresh button is `F5`. A click outside the popup is `Esc` from
the item list. When `can_login` is set, `Enter` starts the sign-in and the
popup shows a button that does the same.

## Status lines

The popup always shows why it has no rows. One of, by snapshot state:

| State                          | Shown                                          |
|--------------------------------|------------------------------------------------|
| `checking`, or first refresh   | "Loading items…"                               |
| `signed_out`                   | "Signed out of Proton Pass" and Sign in        |
| `logging_in`                   | the sign-in lines                              |
| `locked`                       | "…locked; run pass-cli session unlock"         |
| `cli_missing`                  | "pass-cli is not installed"                    |
| `error`                        | `session_detail` and Sign in                   |
| rows empty, query not empty    | "No matches"                                   |
| backend not running            | "Backend stopped; restarting"                  |
| `v` is not 1                   | "Backend and shell disagree; rebuild"          |

`stale`, `notice` and `cli_warning` are shown as given, under the list.
