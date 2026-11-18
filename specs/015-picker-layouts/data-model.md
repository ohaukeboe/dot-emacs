# Data Model: Picker Layouts

All state lives in the `Picker` singleton (`modules/mango/quickshell/Picker.qml`)
for the one open request.

## Picker request

| Field     | Type   | Notes                                                      |
|-----------|--------|------------------------------------------------------------|
| prompt    | string | Shown as the title or search label                         |
| layout    | enum   | `list` (default), `tiles`, `sources`, `clipboard`          |
| items     | list   | One Picker item per non-empty input line                   |
| query     | string | Filter text; unused by `tiles`                             |
| index     | int    | Selected item in the visible results                       |
| armed     | int    | `tiles` only: index of the armed item, or -1               |
| replyPath | string | FIFO the waiting `mango-pick` reads; `""` when none waits  |

Rules: an empty or unknown `layout` is `list`. A new request cancels a waiting
one. Zero items cancels at once.

## Picker item (per layout)

| Layout    | Parsed from line                       | Returned on pick       |
|-----------|----------------------------------------|------------------------|
| list      | the line; `Kind: name` dims the kind   | the line               |
| tiles     | `label<TAB>icon[<TAB>confirm]`         | `label`                |
| sources   | `Monitor: <name> <desc>` → screen      | the line               |
|           | `Window: <title> (<id>)` → window      | the line               |
| clipboard | `<cliphist id><TAB><preview>`          | the line               |

Derived fields:

- **screen**: `name`, `description`, `screen` (matching `Quickshell.screens`
  entry or null), resolution from it.
- **window**: `title`, `identifier`, `appId` and `tags` from the
  `mmsg get all-clients` entry whose `foreign_toplevel_id` equals
  `identifier` (absent when no match).
- **clip entry**: `id`, `kind` (`image` when the preview matches
  `[[ binary data … ]]`, else `text`), `format`, `width`, `height`, `size`
  for images; `lines` for text, filled lazily per visible row.

## States: tiles arming

```text
idle --pick(i), i unmarked--> reply(i)
idle --pick(i), i marked----> armed(i)
armed(i) --same pick(i)-----> reply(i)
armed(i) --any other input--> idle
```

A pick is a digit, Enter on the selection, or a click.

## States: request

```text
closed --open(request)--> open --pick------------> replied (exit 0, or 10 alt)
                          open --Esc/outside/new--> cancelled (exit 1)
```
