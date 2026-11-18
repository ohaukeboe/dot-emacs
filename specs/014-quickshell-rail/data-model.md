# Data Model: Quickshell Rail

All state is runtime QML state; nothing is persisted by this feature.

## Tag state (`Tags` singleton)

Source: `mmsg watch all-tags` ([contract](contracts/rail-ipc.md)).

| Field       | Type               | Meaning                                |
|-------------|--------------------|----------------------------------------|
| `monitors`  | map name → `Tag[]` | Last snapshot, replaced whole per line |
| `connected` | bool               | The watch process is running           |

`Tag`:

| Field     | Type | Rule                                               |
|-----------|------|----------------------------------------------------|
| `index`   | int  | 1 to `tag_num`, in order                           |
| `active`  | bool | From `is_active`; at most one per monitor          |
| `urgent`  | bool | From `is_urgent`                                   |
| `clients` | int  | From `client_count`; shown only when > 0 or active |

Validation: a line that fails `JSON.parse` or has no `all_tags` array is
ignored, so the last good snapshot is kept. A monitor that is missing from a
snapshot shows an empty island.

Transitions: process exits → `connected = false` → restart after 1 s →
`connected = true` on the first line.

## Rail state (`Rail` singleton, extended)

| Field        | Type        | Change in this spec                                 |
|--------------|-------------|-----------------------------------------------------|
| `openTarget` | string      | Unchanged: `""`, `controls`, `calendar`, `usage`    |
| `openOutput` | string      | Set from the click's screen, or the cursor for IPC  |
| `openRect`   | rect / null | New: opening capsule in screen coords; null for IPC |
| `limits`     | object/null | Moved from `Usage.qml`; parsed `limits.json`        |
| `stale`      | bool        | Moved from `Usage.qml`                              |

Removed: the `railState` runtime file and both waybar signals.

Later, popups grow out of the island that holds the clicked item, which they
draw again as the card's header (`ClockIsland.qml`, `StatusIsland.qml`).
`openRect` is gone: the popup places the island where the rail does, for
clicks and IPC alike. The tray drawer's `revealed` flag moved to `Rail` as
`trayRevealed`, so both copies of the island have the same width.

## Rail window (`Bar`, one per screen)

Derived only, with no own state beyond the tray drawer's `revealed` flag,
which starts closed:

- tags = `Tags.monitors[screen.name] ?? []`, filtered to occupied or active;
- `sessionPercent` = `Rail.limits.session.used_percentage`, or 0 when
  `resets_at` has passed; the pill is hidden when `Rail.limits` is null;
- `open(t)` = `Rail.openTarget === t && Rail.showsOn(screen.name)`.
