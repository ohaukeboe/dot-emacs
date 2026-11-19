pragma ComponentBehavior: Bound

// The displays card's layout area: every enabled display of
// Displays.pending as a rectangle, to one scale, where it sits in the
// layout. Drag one to move it; it snaps to the others' edges and settles
// where it touches one. Displays that are off wait in a row underneath.
// A display that copies another (specs/020-duplicate-display) has no tile
// of its own: its source's tile is drawn as a stack. Dropping a tile on
// the inner half of another makes it a copy of that one.
import QtQuick
import "displayLayout.mjs" as Geo

Rectangle {
  id: canvas

  readonly property int margin: 28
  // Room for the row of displays that are off.
  readonly property int offRow: offNames.length > 0 ? 52 : 0
  // The delegates are keyed by name, so an edit does not rebuild the one
  // that is being dragged.
  readonly property string onKey: Displays.pending.filter(d => Geo.placed(d)).map(d => d.name).join("\n")
  readonly property string offKey: Displays.pending.filter(d => !d.enabled).map(d => d.name).join("\n")
  readonly property var onNames: onKey === "" ? [] : onKey.split("\n")
  readonly property var offNames: offKey === "" ? [] : offKey.split("\n")
  // Scale and offset of the drawing; held still while a display is dragged.
  readonly property var liveFrame: Geo.frame(Displays.pending, width, height - offRow, margin)
  property var frame: ({ k: 0.1, ox: 0, oy: 0 })

  function follow() {
    if (!Displays.dragging) frame = liveFrame;
  }
  onLiveFrameChanged: follow()
  Component.onCompleted: follow()
  Connections {
    target: Displays
    function onDraggingChanged() { canvas.follow(); }
  }

  radius: Config.islandRadius
  color: Config.app
  clip: true

  Repeater {
    model: canvas.onNames

    Rectangle {
      id: tile
      required property string modelData
      readonly property var display: Displays.pending.find(d => d.name === modelData) ?? null
      readonly property var size: display ? Geo.logicalSize(display) : ({ w: 0, h: 0 })
      // The displays that copy this one; with any, the tile is a stack.
      readonly property var copies: Geo.copiesOf(Displays.pending, modelData)
      readonly property bool picked: Displays.selected === modelData
        || copies.some(c => c.name === Displays.selected)
      // A dragged tile is held over this one: release makes it a copy.
      readonly property bool target: Displays.dropTarget === modelData
      readonly property color ink: picked ? Config.onAccent : Config.fg
      // Where the drag started: pointer on the canvas, display in the layout.
      property var grab: null

      visible: display !== null
      x: canvas.frame.ox + (display?.x ?? 0) * canvas.frame.k + 1
      y: canvas.frame.oy + (display?.y ?? 0) * canvas.frame.k + 1
      width: Math.max(0, size.w * canvas.frame.k - 2)
      height: Math.max(0, size.h * canvas.frame.k - 2)
      z: grab !== null ? 1 : 0
      radius: Config.chipRadius
      color: picked ? Config.fg : Config.raised2
      border.width: target ? 2 : 0
      border.color: Config.fg
      Behavior on color { ColorAnimation { duration: Config.fast } }
      Behavior on x { enabled: !Displays.dragging; Anim { duration: Config.normal } }
      Behavior on y { enabled: !Displays.dragging; Anim { duration: Config.normal } }
      Behavior on width { enabled: !Displays.dragging; Anim { duration: Config.normal } }
      Behavior on height { enabled: !Displays.dragging; Anim { duration: Config.normal } }

      // The second sheet of a stack, behind the tile.
      Rectangle {
        visible: tile.copies.length > 0
        z: -1
        x: 6
        y: -6
        width: parent.width
        height: parent.height
        radius: Config.chipRadius
        color: Config.raised3
      }

      Column {
        anchors.centerIn: parent
        visible: !tile.target && width + 12 <= tile.width && height + 8 <= tile.height
        spacing: 2
        RailText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Geo.stackLabel(Displays.pending, tile.modelData)
          color: tile.ink
          font.weight: Font.DemiBold
        }
        Detail {
          anchors.horizontalCenter: parent.horizontalCenter
          text: (tile.copies.length > 0 ? "Duplicated · " : "")
            + tile.size.w + "×" + tile.size.h + " at " + (tile.display?.x ?? 0) + "," + (tile.display?.y ?? 0)
          color: tile.ink
          opacity: tile.picked ? 0.7 : 1
        }
      }

      Detail {
        anchors.centerIn: parent
        visible: tile.target
        text: "Duplicate here"
        color: tile.ink
      }

      HoverArea {
        anchors.fill: parent
        tint: tile.ink
        cursorShape: tile.grab !== null ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: (mouse) => {
          Displays.selected = tile.modelData;
          const p = mapToItem(canvas, mouse.x, mouse.y);
          tile.grab = { px: p.x, py: p.y, x: tile.display.x, y: tile.display.y };
        }
        onPositionChanged: (mouse) => {
          if (tile.grab === null) return;
          const p = mapToItem(canvas, mouse.x, mouse.y);
          const dx = p.x - tile.grab.px;
          const dy = p.y - tile.grab.py;
          if (!Displays.dragging && Math.abs(dx) + Math.abs(dy) < 4) return;
          Displays.dragging = true;
          const k = canvas.frame.k;
          // Over the inner half of another tile: no snapping, it will stack.
          Displays.dropTarget = Geo.dropTarget(Displays.pending, tile.modelData,
            (p.x - canvas.frame.ox) / k, (p.y - canvas.frame.oy) / k);
          Displays.move(tile.modelData, tile.grab.x + dx / k, tile.grab.y + dy / k,
            Displays.dropTarget !== "" ? 0 : 14 / k);
        }
        onReleased: {
          tile.grab = null;
          if (Displays.dragging) Displays.drop(tile.modelData);
        }
        onCanceled: {
          tile.grab = null;
          if (Displays.dragging) Displays.drop(tile.modelData);
        }
      }
    }
  }

  // Off: outlines, apart from the arrangement (FR-010).
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 10
    spacing: 8

    Repeater {
      model: canvas.offNames

      Rectangle {
        id: chip
        required property string modelData
        readonly property var display: Displays.pending.find(d => d.name === modelData) ?? null
        readonly property bool picked: Displays.selected === modelData

        width: Math.max(96, chipText.implicitWidth + 24)
        height: 36
        radius: Config.chipRadius
        color: "transparent"
        border.width: 1
        border.color: picked ? Config.fg : Config.dim

        Detail {
          id: chipText
          anchors.centerIn: parent
          text: (chip.display ? Geo.label(chip.display) : "") + " · Off"
          color: chip.picked ? Config.fg : Config.dim
        }

        HoverArea {
          anchors.fill: parent
          onClicked: Displays.selected = chip.modelData
        }
      }
    }
  }
}
