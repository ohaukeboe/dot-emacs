# Research: Mango Islands Shell

Decisions for `plan.md`. Each has the decision, why, and what was rejected.
Items marked **Verify first** rest on an assumption that the first task of
its story must confirm on the live machine before building on it.

## R1. Islands stay in waybar

**Decision**: Keep waybar as the rail and get the three capsules from CSS:
`window#waybar` transparent, and `.modules-left`, `.modules-center`,
`.modules-right` each with the island colour, a 18 px radius and an 8 px top
margin. The frame colour shows through from `swaybg`.

**Rationale**: waybar already has `mango/workspaces`, the tray drawer and
every status module. The capsule look is a stylesheet change.

**Alternatives**: Draw the rail in Quickshell. Rejected: it means rewriting
workspaces (parsing `mmsg` output), the tray and five status modules, and the
glossary fixes Quickshell's role as "only the rail's popups".

## R2. One palette attrset

**Decision**: Replace the `bg`/`card`/`accent` bindings in
`modules/mango/default.nix` with one `palette` attrset (`frame`, `app`,
`island`, `raised`, `fg`, `dim`, `onAccent`). Every consumer in the module
reads it: Mango config, `swaybg`, waybar CSS, the QML (through
`replaceVars`), foot, fuzzel, mako and swaylock. The accent is `fg`; there is
no separate accent colour.

**Rationale**: FR-004 and Constitution IV. A missing key is an evaluation
error.

**Alternatives**: A typed `modules.mango.palette` option. Rejected: nothing
outside the module sets it, so an option adds surface without a user.
Emacs keeps its own `#171717` in `config.org`; sharing it would couple the
Emacs config to a NixOS module that two machines do not enable.

## R3. "Open" state on the rail

**Decision**: The gear, clock and usage pill become waybar `custom/*`
modules with `return-type = "json"` and a `signal`. Each module's `exec`
asks Quickshell which popup is open (`qs -c mango ipc call shell openTarget`)
and adds the class `open` when it is its own. Quickshell sends the signal to
waybar (`pkill -RTMIN+<n> waybar`) whenever `openTarget` changes.

**Rationale**: waybar cannot style a built-in module from outside state;
custom modules with a class can. The clock's `exec` prints the date and time
itself on a 5 s interval, so nothing is lost by replacing the built-in.

**Alternatives**: Drawing the accent state from Quickshell over the rail.
Rejected: it needs the capsule's pixel position on every monitor.

## R4. Usage limits come from the status line, not the credentials

**Decision**: Claude Code already pipes a JSON document to the status-line
command on every render. On subscription plans it carries `rate_limits`
(`five_hour` and `seven_day`, each with `used_percentage` and `resets_at`).
`context-statusline` writes that object, with a timestamp, to
`$XDG_STATE_HOME/agent-usage/limits.json` (atomic rename).

**Rationale**: FR-015 and FR-016 with no credential access at all: no token
is read, refreshed, logged or sent, and no undocumented endpoint is called.
It is also the number the CLI itself shows (SC-003).

**Trade-off**: the limits only update while a Claude Code session is
running. Usage only moves when Claude is used, so the gap is use from
claude.ai or another machine; the popup's "updated" time makes that visible.

**Alternatives**: The reference's approach, Anthropic's OAuth usage endpoint
with the token from `~/.claude/.credentials.json`. Rejected as the default:
it reads a secret the agent sandbox hides on purpose, needs token refresh,
and the endpoint is not documented. Kept as the fallback if verification
fails.

**Verify first**: dump one status-line input on this machine and confirm
the `rate_limits` field names and that `resets_at` is epoch seconds.

## R5. Token counts from transcripts, by a timer

**Decision**: A small Python collector (built with
`writers.writePython3Bin`, so flake8 runs at build) reads
`~/.claude/projects/**/*.jsonl` files modified in the last 8 days, counts
each assistant message once (keyed on message id and request id, because a
streamed message is written several times), and writes
`$XDG_STATE_HOME/agent-usage/tokens.json` with tokens per day and per model.
A systemd user timer runs it every 15 minutes; the popup's refresh button
starts the same unit.

**Rationale**: Same source the reference uses. Two files, one writer each,
so the status line and the collector never race.

**Alternatives**: jq over the transcripts. Rejected: de-duplicating streamed
messages across files in jq is unreadable. Claude's `stats-cache.json`:
rejected, its format is internal and it lags.

## R6. Where the usage code lives

**Decision**: The status-line tap, collector and timer go in a new Home
Manager module `workstation/agents/usage.nix` behind `agents.usage.enable`.
`modules/mango` knows only the two files and the unit name
(`contracts/usage-record.md`). No file means no pill.

**Rationale**: Constitution V: modules meet at a declared contract, not at
each other's internals. The pill hiding itself also covers SC-006.

## R7. Usage pill is a waybar module, the popup is Quickshell

**Decision**: `custom/claude-usage` reads `limits.json` with jq and prints
text, percentage and class. The ring is waybar's `format-icons` over the
eight Nerd Font circle-slice glyphs. The popup is a third `RailPopup` target,
`usage`.

**Rationale**: Reuses the pattern from spec 012. An eight-step ring next to
an exact number is close enough to the artboard; this is the one visible
deviation from the design and is recorded here.

**Alternatives**: A true ring needs a drawn widget, which waybar cannot host.

## R8. KDE Connect through its own QML plugin

**Decision**: `kdeconnect-kde` ships a QML module, `org.kde.kdeconnect`
(checked in the store: `DevicesModel`, `NotificationsModel`, and D-Bus
interface factories for battery, find-my-phone, clipboard and SFTP). Add its
`lib/qt-6/qml` to the Quickshell service's `QML_IMPORT_PATH` and bind the
phone card and detail page to those types.

**Rationale**: Live models with change signals, the same ones KDE's own
applet uses; no polling and no output parsing. Pairing, battery,
notifications and dismiss are all there.

**Alternatives**: `kdeconnect-cli` through `Process`. It has ring, share,
clipboard, mount and notification listing, but no battery and no change
signals, so the card would poll. Kept as the fallback.

**Verify first**: that Quickshell loads the plugin (same Qt from the same
nixpkgs, so it should) and that `qmllint` accepts the import path.

## R9. The four phone actions

| Action    | How                                                             |
|-----------|-----------------------------------------------------------------|
| Ring      | Find-my-phone interface, `ring()`                               |
| Clipboard | Clipboard interface, `sendClipboard()`                          |
| Send file | Close the popup, `FileDialog` (QtQuick.Dialogs), then share URL |
| Browse    | SFTP interface `mountAndWait()`, then `xdg-open` the mount      |

**Rationale**: All in-process except `xdg-open`, referenced by store path.
The popup must close before the file dialog opens because the popup holds
exclusive keyboard focus.

**Risk**: a Qt file dialog opened from a layer-shell process. If it
misbehaves, fall back to `zenity --file-selection` plus
`kdeconnect-cli --share`.

## R10. Phone icon on the rail

**Decision**: `custom/phone` runs `kdeconnect-cli -a --id-only` and prints
the icon when the list is not empty. Quickshell signals waybar when its
device model's reachable count changes; the module also runs once at start.

**Rationale**: Event-driven without a second D-Bus client.

## R11. Split the QML

**Decision**: `shell.qml` is 742 lines before this feature. Split it into
one file per popup plus shared parts, with a single `Config.qml` singleton
holding every substituted value (palette and store paths). `replaceVars`
runs on that file only; `qmllint` runs over the directory.

**Rationale**: Two new popups' worth of QML in one file is not reviewable.
One substituted file keeps the "missing placeholder fails the build" check.

## R12. Out of palette today

Found while reading the module: waybar hard-codes `#c8c5c7`, `#555555` and
`#888888`, the QML hard-codes `fg` and `dim`, and foot sets its own
`171717`/`c8c5c7`. All move to `palette`. The frame changes from `#111416`
to `#111111`.

## R13. Firewall and daemon

`programs.kdeconnect.enable` in `common/system/system.nix` already opens the
ports; `services.kdeconnect` in `modules/mango` already starts the daemon
with the session. Only `indicator = false` changes (FR-024). FR-023's "off"
case is `services.kdeconnect.enable = false`: the QML import, phone card and
`custom/phone` are all generated under the same condition.

## R14. Findings during implementation

- **Status line fields (T013)**, from Claude Code's status line docs rather
  than a live capture: `rate_limits.five_hour` and `rate_limits.seven_day`,
  each with `used_percentage` (0 to 100) and `resets_at` (epoch seconds).
  Either window can be absent, and both appear only on Pro, Max and Ultra
  plans after the first response. The status line carries no plan name, so
  the usage popup shows no plan; FR-012 was amended to match.
- **Status line sandbox**: the tap writes
  `~/.local/state/agent-usage/limits.json` and ignores failures. If Claude
  Code runs its status line inside the sandbox, where `$HOME` is read-only,
  the pill stays hidden; check this first if it never appears.
- **Open state on the rail**: modules read a runtime file instead of calling
  `qs ipc call shell openTarget` (see `contracts/popup-ipc.md`). The open
  clock uses the `raised` fill rather than the accent, which read as too
  loud on the centre island; FR-006 was amended to match.
- **Usage ring**: waybar cannot draw arcs, and the Nerd Font circle-slice
  glyphs read as pies, not the artboard's ring. The build writes one SVG
  ring per 5 % step in each state (fg on island, onAccent when open); the
  module's `pN` class picks it as a CSS background image.
- **KDE Connect API**: `DevicesModel` roles used are `deviceId` and `name`;
  reachability and pairing come from `DeviceDbusInterface` (`isReachable`,
  `isPaired`, `isPairRequested`, `requestPairing()`, `unpair()`).
  `NotificationsModel` roles: `appName`, `title`, `notitext`,
  `dismissable`, `dbusInterface` (`dismiss()`). It has no timestamp role,
  so notification rows show no time, and rows follow the model's order.
- **Browse** calls the SFTP interface's `startBrowsing()`, which mounts and
  opens the mount in the daemon (what KDE's own applet does), instead of
  `mountAndWait()` plus `xdg-open`.
- **Send file** shares through `shareUrl()`, which returns nothing, so a
  failed transfer is reported by the KDE Connect daemon's own notification,
  not by `notify-send`. The `FileDialog` relies on the GTK 3 platform theme
  to open as its own window after the popup closes; if it does not show,
  check `QT_QPA_PLATFORMTHEME` in the Quickshell unit's environment.
- **Contrast (T037)**: `#948985` on `raised` is 4.11:1, so `dim` became
  `#9c918d` (4.55:1 on `raised`, 5.25:1 on `island`).
- **Status line limits only near a limit**: Claude Code 2.1.321 fills the
  status line's `rate_limits` from the `anthropic-ratelimit-unified-5h/7d-utilization`
  response headers, which the API sent only near a limit. After the limits
  reset on 2026-11-14 the record went stale at 20% real use. The R4 fallback
  is now the main source: `agent-usage.service` reads `/api/oauth/usage`
  with the token Claude Code keeps, every 5 minutes, and never refreshes it.
