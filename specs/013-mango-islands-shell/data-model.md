# Data Model: Mango Islands Shell

No database. The model is one build-time attrset, two small state files, and
live objects owned by other daemons.

## Palette (build time, `modules/mango/default.nix`)

| Key        | Value    | Used for                                   |
|------------|----------|--------------------------------------------|
| `frame`    | `111111` | Wallpaper, gaps, lock screen background    |
| `app`      | `171717` | foot background, window border             |
| `island`   | `212121` | Rail capsules, popups, tooltips, mako      |
| `raised`   | `2c2c2c` | Off toggles, slider tracks, round buttons  |
| `fg`       | `cabab4` | Text, icons, accent fills, focus border    |
| `dim`      | `9c918d` | Secondary text, idle workspace dots        |
| `onAccent` | `171717` | Text and icons on an accent fill           |

Rule: no other colour literal in `modules/mango`. The phone card's inner
panel (`2a2a2a` on the canvas) uses `raised`.

## Limits record (`$XDG_STATE_HOME/agent-usage/limits.json`)

Writer: `context-statusline`. Schema: `contracts/usage-record.md`.

| Field                     | Type         | Notes                         |
|---------------------------|--------------|-------------------------------|
| `updated_at`              | epoch s      | When the status line wrote it |
| `session.used_percentage` | number 0–100 | 5-hour window                 |
| `session.resets_at`       | epoch s      |                               |
| `weekly.used_percentage`  | number 0–100 | 7-day window                  |
| `weekly.resets_at`        | epoch s      |                               |

States derived by readers:

- **absent**: file missing. No pill.
- **fresh**: `updated_at` within 30 minutes.
- **stale**: older. Pill keeps the value; popup marks the time.
- **expired**: `resets_at` has passed. That limit reads 0% until rewritten.

## Tokens record (`$XDG_STATE_HOME/agent-usage/tokens.json`)

Writer: the collector unit `agent-usage.service`.

| Field            | Type               | Notes                               |
|------------------|--------------------|-------------------------------------|
| `updated_at`     | epoch s            |                                     |
| `days[]`         | 7 items, old first | `date` (ISO), `tokens`              |
| `models[]`       | by tokens, desc    | `model`, `tokens`, over the 7 days  |
| `week_tokens`    | integer            | Sum of `days[].tokens`              |
| `error`          | string or absent   | Shown in the popup when set         |

`tokens` is input + output + cache creation + cache read, each assistant
message counted once.

## Phone (live, from KDE Connect)

| Attribute         | Source                                              |
|-------------------|-----------------------------------------------------|
| id, name, kind    | Devices model                                       |
| paired, reachable | Devices model                                       |
| battery, charging | Battery interface                                   |
| notifications     | Notifications model: app, title, text, dismissable  |

**Active phone**: the first reachable paired device in the model's order;
if none is reachable, the first paired one, shown as "Not reachable".

## Shell state (Quickshell, in memory)

| Property     | Values                                      |
|--------------|---------------------------------------------|
| `openTarget` | `""`, `controls`, `calendar`, `usage`       |
| `page`       | `""`, `wifi`, `bluetooth`, `sound`, `phone` |
| `usageView`  | `day`, `model`                              |

`page` and `usageView` reset when `openTarget` changes. One popup at a time.
