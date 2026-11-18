# Data Model: Proton Pass Quick Access

The backend owns all data. Its model is `cosmic-pass`'s existing one
(`specs/001-quick-access-launcher/data-model.md` in that repository) and is
not changed by this feature. This file lists what the shell holds and what
is stored where.

## In the shell (`Pass.qml`)

| Property   | Type    | Meaning                                                  |
|------------|---------|----------------------------------------------------------|
| `snapshot` | object  | The last snapshot, see `contracts/serve-protocol.md`     |
| `alive`    | bool    | The backend process is running                           |
| `openedUrl`| string  | The sign-in URL already handed to the browser, or `""`   |

Rules:

- `snapshot` is replaced whole by each line read; nothing is merged, and
  nothing derived from it is kept in another property.
- The shell keeps no item, field, query history or usage of its own.
- When the process exits, `snapshot` is reset to empty and `alive` is false,
  so a revealed value cannot outlive the backend that sent it.
- `openedUrl` is reset when `snapshot.login` becomes `null`.

## State transitions the shell drives

```text
closed --Super+Space--> open/list      send show; field cleared and focused
open/list --Tab--> open/fields         send open_fields
open/fields --Esc--> open/list         send escape
open/list --Esc, toggle, outside--> closed    send hide
open/* --Enter--> (backend copies) --visible:false--> closed
any --backend exits--> closed/open with "Backend stopped"; restart after 2 s
```

`Rail.openTarget` is the truth for open or closed. The shell sends `show`
when it becomes `"pass"` and `hide` when it stops being `"pass"`, whatever
the cause, and closes the popup when a snapshot says `visible: false`.

## At rest

| What                               | Where                         | Owner   |
|------------------------------------|-------------------------------|---------|
| Item summaries, usage records      | Encrypted cache file          | backend |
| Cache key                          | The user's keyring            | backend |
| Proton session                     | `pass-cli`'s own store        | pass-cli|
| Clearing time                      | Nix option, on the command line | Nix   |
| Field values                       | Nowhere                       |         |

The Mango and COSMIC sessions share the cache file and the Proton session
(FR-024); only one backend runs per session (research R6).
