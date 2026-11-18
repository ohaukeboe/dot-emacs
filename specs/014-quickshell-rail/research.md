# Research: Quickshell Rail

Probed on the running laptop session: `mango-0.18.5` (the
`programs.mango.package` the laptop config pins) and `quickshell-0.3.2` (the
`programs.quickshell.package`).

## R1. Tag state comes from `mmsg watch all-tags`

**Decision**: A `Tags` singleton runs `mmsg watch all-tags` as a long-lived
`Process` and parses each stdout line with a `SplitParser`. Each line is a
full snapshot:

```json
{"all_tags":[{"monitor":"eDP-1","tags":[{"index":1,"is_active":false,
  "is_urgent":false,"layout":"T","client_count":1}, …]}]}
```

The stream prints one snapshot at start, then one per change. A tag is
occupied when `client_count > 0`. When the process exits, a 1 s timer starts
it again (FR-009, SC-006).

**Rationale**: Probed in the session: one line at start, the same shape as
`mmsg get all-tags`, and it carries everything FR-006 to FR-008 need, per
monitor. It is event-driven and needs no protocol code.

**Alternatives considered**:
- `Quickshell.WindowManager` (ext-workspace-v1). Mango advertises
  `ext_workspace_manager_v1`, but a probe listed 0 windowsets. The protocol
  also has no occupancy, so "hide empty tags" would still need `mmsg`.
- Polling `mmsg get all-tags`. Rejected: FR-009 forbids polling, and SC-003
  needs changes to show without delay.

## R2. Clicking a tag

**Decision**: `mmsg dispatch viewcrossmon,<index>,<monitor>`. If that
dispatch does not take a monitor name, fall back to
`mmsg dispatch focusmon,<monitor>` and then `view,<index>,0`. This is the
same call as the `SUPER+<n>` bindings in `modules/mango/default.nix`.

**Rationale**: `viewcrossmon` is in the 0.18.5 binary. Spelling out the
monitor means a click on the second monitor's rail never switches the
focused monitor's tag.

**Verified (T002)**: `mmsg dispatch viewcrossmon,1,eDP-1` returns
`{"success":true}` and makes tag 1 active on `eDP-1`, so the order is tag
first, then monitor. This was tested with one monitor only; the
second-monitor case is part of quickstart check 13.

## R3. Rail window

**Decision**: `Bar.qml` is one `PanelWindow` per screen inside a `Variants`
over `Quickshell.screens`:

- anchored `top | left | right`, transparent, on the `Top` layer;
- `implicitHeight` 36, margins top 8, left 12 and right 12;
- `exclusiveZone` 36 + 8, so windows start where they start today;
- namespace `mango-rail`.

The three islands are `Rectangle`s in the `island` colour with radius 18.
They sit left, centred and right in a plain `Item`, not a layout, so the
centre island stays centred on the screen whatever the side widths are.

**Rationale**: these are waybar's numbers from `programs.waybar.settings.main`
and its CSS. `Config.railEdge` (8 + 36 + 8) already assumes them. `Variants`
over screens is how the popups already follow monitors (FR-002).

**Alternatives considered**: three separate `PanelWindow`s, one per island.
Rejected: three exclusive zones, and harder hover across islands.

## R4. Popups anchor to the capsule

**Decision**: `Rail.toggle(target)` gains two optional arguments,
`toggle(target, screenName, rect)`. `rect` is the opening capsule's rectangle
in screen coordinates, from `item.mapToItem(null, …)`:

- With them, the `mmsg get cursorpos` lookup is skipped.
- `RailPopup` centres the card under `rect`, clamped to `Config.edgeGap` from
  the screen edges. End-aligned popups align the card's right edge to the
  capsule's right edge instead.
- IPC calls (key bindings, scripts) pass no rect. They keep today's path:
  cursor lookup, then the fixed centre or right-edge position (FR-016).

**Rationale**: FR-014. The rail is now in the same process as the popups, so
the geometry is one function call away. This removes the reason spec 013 R3
gave for not drawing the accent from Quickshell.

## R5. Open state and the removed IPC

**Decision**: rail items bind `Rail.openTarget === "<target>"` and
`Rail.showsOn(screen.name)` directly. The `mango-popup` runtime `FileView`,
both `pkill -RTMIN+n waybar` calls, `Config.pkill` and the `@pkill@`
placeholder are deleted. `shell.openTarget()` IPC stays for scripts.

**Rationale**: FR-015 and FR-017. Bindings make the signal round-trip
unnecessary.

## R6. Usage ring

**Decision**: `Rail` gains the single `limits.json` `FileView` and its
`stale` flag, moved from `Usage.qml`, so the pill and the popup read one
source.

- The ring is a 16 px `Shape` with two `PathAngleArc`s: a track at 25 %
  opacity and the arc. The stroke width is 2.5 px at radius 6, the SVG
  geometry from `usageRing`.
- Colour: `fg`, or `onAccent` on the open pill.
- The pill is hidden when `limits` is null. The session value reads 0 once
  `resets_at` has passed, the same rule as the jq filter.

**Rationale**: QtQuick.Shapes draws the arc at any percentage, so the 21
prebuilt SVGs and their CSS go (FR-011, FR-017). Keeping one reader avoids
two parses of the same file.

## R7. Tray

**Decision**: `Tray.qml` repeats `SystemTray.items`. Each item is an
`IconImage` inside a `HoverArea` with radius 14:

- Left click calls `activate()`, or opens the menu when `onlyMenu` is true.
- Right click opens a `QsMenuAnchor` whose `menu` is `item.menu`, anchored
  to the icon.
- When `item.icon` is `image://icon/<name>`, the image source is
  `Quickshell.iconPath(name + "-symbolic", true)`, falling back to
  `item.icon`. Pixmap icons are drawn as they are.

The drawer is a chevron button that toggles a `Row`'s visibility. The tray
takes no width when `SystemTray.items` is empty (FR-012).

**Rationale**: Quickshell 0.3.2 exports `SystemTray`, `QsMenuAnchor` and
`QsMenuOpener` (probed in its qmltypes). The `-symbolic` lookup matches
waybar's `-gtk-icon-style: symbolic`.

**Verify first**: that `QsMenuAnchor` menus render on Mango, which is a
wlroots compositor using xdg-popup. If they do not, draw the menu as a
`RailPopup`-style card from `QsMenuOpener` entries.

## R8. Status icons and tooltips

**Decision**: the controls capsule binds the services that `Controls.qml`
already uses:

- Network: `Networking` devices. Wi-Fi strength picks one of four glyphs;
  ethernet and disconnected have their own glyphs.
- Sound: `Pipewire.defaultAudioSink.audio.volume` and `.muted`, with the
  three glyphs and the muted glyph.
- Battery: `UPower.displayDevice`. The icon is hidden unless
  `isLaptopBattery`. Warning style below 15 % while discharging.

The glyph sets are waybar's `format-icons`, moved into `Icons.qml`.

Tooltips are a small `RailTooltip.qml`. It is a `PopupWindow` anchored under
the hovered item, shown after 500 ms of hover, in island colour, radius 14,
12 px text (FR-013).

**Rationale**: no new services, and `PwObjectTracker` on the default sink
already exists in `Rail.qml`.

## R9. Phone icon

**Decision**: `PhoneIcon.qml` uses KDE Connect's `DevicesModel` (the same
filter as `Phone.qml`) and is visible while `reachableCount > 0`. The bar
loads it with `Loader { active: Config.kdeconnect; source: "PhoneIcon.qml" }`.
The Nix build deletes the file when KDE Connect is off, as it does for
`Phone.qml`. The `RTMIN+9` signal in `Phone.qml` goes.

**Rationale**: FR-013. It stays inert with KDE Connect off (spec 013 FR-023;
constitution V).

## R10. Clock

**Decision**: a `SystemClock` with `precision: SystemClock.Minutes`. The text
is a `RichText` `Text`: the dim `ddd d MMM`, then two spaces, then the bold
`HH:mm`, in sans 13 px.

**Rationale**: the same string `mango-rail-module clock` builds with `date`,
without a 5 s poll.

## R11. Supersession

**Decision**: the plan and this file record that spec 012 research R2
("rail stays waybar") is superseded. Spec 012's `research.md` gets a
one-line "Superseded by `specs/014-quickshell-rail` R1/R3" note under R2. The
glossary's **Rail** entry is rewritten (FR-018). Spec 013's
`contracts/popup-ipc.md` is superseded by this spec's contract.

**Rationale**: constitution IV. No ADR covers the rail, so none is
superseded. The choice is easy to reverse, so it stays in research rather
than becoming an ADR.
