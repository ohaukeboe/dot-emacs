# Contract: `cosmic-pass serve`

The authoritative copy lives in `cosmic-pass`:
[`specs/004-serve-mode/contracts/serve-protocol.md`](https://github.com/ohaukeboe/cosmic-pass/blob/main/specs/004-serve-mode/contracts/serve-protocol.md),
shipped in commit `ed1162d` and locked in this repository's `flake.lock`.

This file lists only what the shell (`modules/mango/quickshell/Pass.qml`,
`PassPopup.qml`) uses, so a change upstream can be checked against it.

## Invocation

```text
cosmic-pass serve --clipboard-clear-secs <Config.passClearSecs>
```

## Intents the shell sends

`show`, `hide`, `query`, `next`, `prev`, `page_down`, `page_up`, `select`,
`copy_primary`, `open_fields`, `activate`, `reveal`, `escape`, `refresh`,
`login`. It never sends `back`; `escape` covers it in fields mode.

## Snapshot fields the shell reads

| Field             | Used for                                         |
|-------------------|--------------------------------------------------|
| `v`               | version check; anything but `1` shows a mismatch |
| `visible`         | `false` closes the popup                         |
| `session`         | the status line                                  |
| `session_detail`  | the status line for `error`                      |
| `can_login`       | `Enter` signs in; the Sign in button             |
| `login.url`       | opened once in the browser                       |
| `login.lines`     | the sign-in lines                                |
| `mode`            | item list or field list                          |
| `selected`        | the highlighted row                              |
| `rows[]`          | `title`, `subtitle`, `vault`                     |
| `item`            | `title`, `subtitle`, `vault` in the header       |
| `fields[]`        | `label`, `secret`, `value`, `revealing`, `totp`  |
| `fields[].totp`   | `code`, `remaining`                              |
| `busy.refreshing` | "Loading items…" instead of "No items"           |
| `stale`           | shown under the list                             |
| `notice`          | shown under the list                             |
| `cli_warning`     | shown under the list                             |
