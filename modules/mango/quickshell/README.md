# Quickshell design system

Everything Quickshell draws here (the rail, its popups, the picker, the OSD,
notifications, the lock screen and the greeter) is built from the tokens in
`Config.qml` and the components below. New UI uses them instead of literal
sizes and colours, so it looks like the rest without tuning.

Rules of thumb:

- No literal colour, font size, radius or animation length in a view. Take a
  token, or add one to `Config.qml` if the value is new and will recur.
- Before drawing a `Rectangle` with a radius and a colour, look for the
  component that already is that surface.
- Check a change on screen with the `verify-quickshell` skill.

## Tokens (`Config.qml`)

### Colour

| Token      | Use                                                        |
|------------|------------------------------------------------------------|
| `frame`    | The screen frame behind the islands                        |
| `app`      | Content wells: previews, thumbnails                        |
| `island`   | Islands: rail capsules, popup cards, tooltips              |
| `raised`   | A surface on an island: cards, rows, tracks, idle buttons  |
| `raised2`  | A surface on a `raised` card                               |
| `raised3`  | A surface on a `raised2` surface                           |
| `field`    | A text field's background                                  |
| `fg`       | Text and icons; also the accent fill of anything "on"      |
| `dim`      | Secondary text and icons                                   |
| `onAccent` | Text and icons on an `fg` fill                             |

There is no separate accent colour. Selected, active and critical things are
filled with `fg` and drawn in `onAccent`.

### Shape

| Token          | Value        | Use                                    |
|----------------|--------------|----------------------------------------|
| `cardRadius`   | 22           | Popup cards, notification cards        |
| `islandRadius` | 18           | Islands, raised cards, tiles           |
| `pillRadius`   | 14           | Rows, small surfaces, tooltips         |
| `chipRadius`   | 8            | Small tiles, the default hover tint    |
| (none)         | `height / 2` | Capsules and circles                   |

### Type

Text is `railFont`, icons are `iconFont` (`railIconFont` on the rail itself).

| Token         | Size | Use                                           |
|---------------|------|-----------------------------------------------|
| `fontCaption` | 11   | Key hints, footers (`Hint`)                   |
| `fontSmall`   | 12   | Status lines, pill labels (`Detail`)          |
| `fontBody`    | 13   | Body text (`RailText`)                        |
| `fontLabel`   | 14   | Row labels, search input                      |
| `fontTitle`   | 15   | Card and popup titles (`Title`)               |
| `fontHeading` | 16   | Detail page heading (`PageHeader`)            |
| `fontDisplay` | 112  | The lock and login clock (`DisplayClock`)     |
| `iconSmall`   | 14   | Glyphs in 24 to 28 px controls                |
| `iconMedium`  | 16   | Rail icons, glyphs beside text                |
| `icon`        | 18   | Glyphs in controls (`Glyph`)                  |

Weights: `Bold` for titles and the active item, `DemiBold` for labels,
normal for the rest.

### Motion

| Token    | ms  | Use                                              |
|----------|-----|--------------------------------------------------|
| `fast`   | 120 | Hover, fades, small moves (`Anim`'s default)     |
| `normal` | 180 | Content that opens or resizes (`Reveal`)         |
| `slow`   | 240 | Islands that bloom into a popup                  |

Everything eases with `Easing.OutCubic`: write `Behavior on x { Anim {} }`.

### Layout

Spacing is a multiple of 2: 2 between rows of a list, 6 to 8 between
controls, 10 to 12 between groups, 12 as a card's padding when it holds
controls and 8 when it holds rows. The rail's own measures are `railTop`,
`railHeight`, `railItem`, `railEdge` and `edgeGap`.

## Components

### Surfaces

| Component       | What it is                                                      |
|-----------------|-----------------------------------------------------------------|
| `Island`        | A capsule: the root of every rail island and screen island      |
| `RailPopup`     | A popup card that grows out of an island                        |
| `Card`          | A raised surface sized to its children (`padding`, `spacing`)   |
| `FloatingCard`  | An island card with a shadow, over the screen (360 wide)        |
| `Shadow`        | The shadow under a floating card, as a `layer.effect`           |
| `Reveal`        | Content that opens and closes with a slide and fade             |
| `BatteryIsland` | Battery glyph and level on an island (lock screen, greeter)     |
| `PowerIsland`   | Suspend, reboot and power off, each on a second click           |
| `PasswordCard`  | The lock screen's and greeter's icon, status and password field |

### Text

| Component      | What it is                                         |
|----------------|----------------------------------------------------|
| `RailText`     | Body text; the base of all text                    |
| `Title`        | A card or popup title                              |
| `SectionLabel` | The dim heading over a group of rows               |
| `Detail`       | Dim secondary text                                 |
| `Hint`         | Dim caption text for key hints                     |
| `Glyph`        | An icon from `Icons`                               |
| `PageHeader`   | Back button and heading of a detail page           |
| `DisplayClock` | The large clock and date (lock screen, greeter)    |

### Controls

| Component       | What it is                                                 |
|-----------------|------------------------------------------------------------|
| `HoverArea`     | A click area with the hover tint; use it for every click   |
| `IconButton`    | A round icon button, filled when `on`                      |
| `Pill`          | A small labelled button or toggle                          |
| `Segmented`     | A capsule of exclusive choices                             |
| `CapsuleSlider` | A slider with its icon inside                              |
| `Meter`         | A thin progress bar                                        |
| `TextBox`       | A text field with a background                             |
| `QueryInput`    | A bare one-line input with a placeholder                   |
| `SearchField`   | A popup's search capsule: glyph, prompt, query, list keys  |
| `SearchIsland`  | The clock island that opens into a popup's `SearchField`   |
| `ToggleRow`     | A toggle, its label and status, and an arrow to a page     |
| `ListRow`       | A list entry: label, detail, optional side action          |
| `LetterTile`    | A first-letter tile for a row without an icon              |
| `RailTooltip`   | A tooltip under a rail item                                |

## Adding a component

Add one when the same block appears a second time. Give it a comment that
says what it is, build it from tokens only, and add it to the tables above.
Files are flat in this directory, so the name is the import.
