# Contract: Popup IPC

The Quickshell config `mango` (HM `programs.quickshell.configs.mango`,
`activeConfig = "mango"`) runs as a user service bound to
`mango-session.target` and exposes two `IpcHandler` targets.

| Target     | Function   | Effect                 |
|------------|------------|------------------------|
| `controls` | `toggle()` | Open, or close if open |
| `calendar` | `toggle()` | Open, or close if open |

- Call form: `qs -c mango ipc call <target> toggle`.
- The popup opens on the monitor under the pointer, from
  `mmsg get cursorpos` (`{"x":…,"y":…,"monitor":"DP-3"}`); the pointer is
  on the rail that was clicked (research R5). If `monitor` is null or
  unknown, the popup shows on every screen rather than none.
- Opening one target closes the other.
- The call returns immediately; it never blocks waybar.

## Callers

| Caller            | Event      | Call              |
|-------------------|------------|-------------------|
| `custom/controls` | `on-click` | `controls toggle` |
| `clock`           | `on-click` | `calendar toggle` |

`qs` is referenced by store path (Constitution I), not by bare name.
