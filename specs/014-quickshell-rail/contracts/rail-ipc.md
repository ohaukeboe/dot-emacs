# Contract: Rail IPC (supersedes spec 013 popup-ipc)

Supersedes `specs/013-mango-islands-shell/contracts/popup-ipc.md`. Its
"Quickshell to waybar" and "Waybar modules" sections are removed with waybar.

## Popup IPC (unchanged)

Call form: `qs -c mango ipc call <target> <function>`, with `qs` by store
path.

| Target     | Function       | Returns | Effect                       |
|------------|----------------|---------|------------------------------|
| `controls` | `toggle()`     | nothing | Open, or close if open       |
| `calendar` | `toggle()`     | nothing | Open, or close if open       |
| `usage`    | `toggle()`     | nothing | Open, or close if open       |
| `displays` | `toggle()`     | nothing | Open, or close if open       |
| `shell`    | `openTarget()` | string  | `""` or the open target name |

Opening one target closes the others. An IPC toggle opens on the monitor
under the pointer, at the fixed position. A rail click opens under the
clicked capsule.

## Compositor input

| Command                                    | Use                         |
|--------------------------------------------|-----------------------------|
| `mmsg watch all-tags`                      | Tag state stream, see below |
| `mmsg dispatch viewcrossmon,<tag>,<mon>`   | Tag click (R2, verified)    |
| `mmsg get cursorpos`                       | Monitor for IPC toggles     |

`watch all-tags` prints one JSON object per line: a full snapshot at start
and one per change.

```json
{"all_tags":[{"monitor":"<name>","tags":[{"index":1,"is_active":true,
  "is_urgent":false,"layout":"T","client_count":2}]}]}
```

The rail reads `monitor`, `index`, `is_active`, `is_urgent` and
`client_count`, and ignores any other field. A malformed line is skipped.

## Removed

- `$XDG_RUNTIME_DIR/mango-popup`
- `RTMIN+8` and `RTMIN+9` signals to waybar
- `mango-rail-module`
