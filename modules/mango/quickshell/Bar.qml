pragma ComponentBehavior: Bound

// The rail (specs/014-quickshell-rail, look from specs/013-mango-islands-shell):
// three islands along the top edge of each screen. Workspaces on the left,
// the date and clock in the middle, and on the right the tray drawer, the
// Claude usage ring and the controls capsule (ClockIsland.qml,
// StatusIsland.qml). Their items open popups through Rail.toggle, and each
// popup grows out of the island that holds the item.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: bar
  required property var modelData
  readonly property string output: modelData.name

  // Each Mango layout symbol as window rectangles on a 16-unit square:
  // [x, y, w, h, opacity]. Drawn after the tags in the workspaces island;
  // an unknown symbol hides the glyph.
  readonly property var layoutGlyphs: {
    const grid = [[1, 2, 6.5, 5.5], [8.5, 2, 6.5, 5.5], [1, 8.5, 6.5, 5.5], [8.5, 8.5, 6.5, 5.5]];
    return {
      T: [[1, 2, 8, 12], [10, 2, 5, 5.5], [10, 8.5, 5, 5.5]],
      RT: [[7, 2, 8, 12], [1, 2, 5, 5.5], [1, 8.5, 5, 5.5]],
      CT: [[0, 2, 3.5, 12, 0.5], [4.5, 2, 7, 12], [12.5, 2, 3.5, 12, 0.5]],
      VT: [[1, 1, 14, 7], [1, 9, 6.5, 6], [8.5, 9, 6.5, 6]],
      S: [[0, 3, 2.5, 10, 0.5], [3.5, 2, 9, 12], [13.5, 3, 2.5, 10, 0.5]],
      VS: [[3, 0, 10, 2.5, 0.5], [2, 3.5, 12, 9], [3, 13.5, 10, 2.5, 0.5]],
      M: [[1, 2, 14, 12]],
      G: grid,
      VG: grid,
      K: [[1, 2, 8, 12], [10, 2, 5, 12]],
      VK: [[1, 1, 14, 7], [1, 9, 14, 6]],
      DW: [[1, 2, 7, 12], [9, 2, 6, 6], [9, 9, 2.5, 5], [12.5, 9, 2.5, 5]],
      F: [[1, 2, 4, 12], [6, 2, 4, 12], [11, 2, 4, 12]],
      VF: [[1, 1, 14, 4], [1, 6, 14, 4], [1, 11, 14, 4]],
    };
  }
  // The glyph's tooltip: each symbol's name from `mmsg get layouts`.
  readonly property var layoutNames: ({
    T: "Tile", RT: "Right tile", CT: "Center tile", VT: "Vertical tile",
    S: "Scroller", VS: "Vertical scroller", M: "Monocle", G: "Grid",
    VG: "Vertical grid", K: "Deck", VK: "Vertical deck", DW: "Dwindle",
    F: "Fair", VF: "Vertical fair",
  })

  screen: modelData
  // Full width from the top edge, islands inset inside it: the window's
  // height is the reserved zone, as waybar's height plus its top margin was.
  anchors { top: true; left: true; right: true }
  implicitHeight: Config.railTop + Config.railHeight
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "mango-rail"

  Item {
    id: content
    anchors.fill: parent
    anchors.topMargin: Config.railTop
    anchors.leftMargin: Config.edgeGap
    anchors.rightMargin: Config.edgeGap

    // Workspaces: a dot per occupied tag, a numbered pill for the active one,
    // then the active tag's layout glyph.
    Island {
      anchors.left: parent.left
      width: tagRow.implicitWidth + 16

      Row {
        id: tagRow
        anchors.centerIn: parent

        Repeater {
          model: Tags.visible(bar.output)

          Item {
            id: tag
            required property var modelData
            width: dot.width + 8
            height: Config.railHeight

            Rectangle {
              id: dot
              anchors.centerIn: parent
              width: tag.modelData.active ? 26 : 8
              height: tag.modelData.active ? 18 : 8
              radius: height / 2
              color: tag.modelData.active ? Config.fg : Config.dim
              border.width: tag.modelData.urgent ? 2 : 0
              border.color: Config.fg
              Behavior on width { Anim {} }
              Behavior on height { Anim {} }

              RailText {
                anchors.centerIn: parent
                visible: tag.modelData.active
                text: tag.modelData.index
                font.family: Config.railFont
                font.pixelSize: Config.fontCaption
                font.bold: true
                color: Config.onAccent
              }

              // The dim dots need a stronger tint to show.
              MouseArea {
                id: tagHover
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                // Middle-click adds or removes the tag from the view, as Super+Ctrl+n.
                // Not Ctrl+click: an unfocused layer surface gets no modifier state.
                onClicked: mouse => mouse.button === Qt.MiddleButton
                  ? Tags.toggleView(bar.output, tag.modelData.index)
                  : Tags.view(bar.output, tag.modelData.index)
              }
              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: tag.modelData.active ? Config.onAccent : Config.fg
                opacity: tagHover.containsMouse ? (tag.modelData.active ? 0.22 : 0.25) : 0
                Behavior on opacity { Anim {} }
              }
            }
          }
        }

        // The active tag's layout, past a divider; a click steps this
        // display's layout cycle, as Super+n. Hidden for a symbol with no glyph.
        Item {
          id: layoutCell
          readonly property string symbol: Tags.visible(bar.output).find(t => t.active)?.layout ?? ""
          readonly property var glyph: bar.layoutGlyphs[symbol] ?? []
          visible: glyph.length > 0
          width: 17 + Config.railItem
          height: Config.railHeight

          Rectangle {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 16
            color: Config.raised
          }

          Item {
            id: layoutButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Config.railItem
            height: Config.railItem

            Repeater {
              model: layoutCell.glyph

              Rectangle {
                required property var modelData
                x: 6 + modelData[0]
                y: 6 + modelData[1]
                width: modelData[2]
                height: modelData[3]
                radius: Math.min(width, height) / 4
                color: Config.dim
                opacity: modelData[4] ?? 1
              }
            }

            HoverArea {
              id: layoutHover
              anchors.fill: parent
              onClicked: Rail.run([Config.mangoLayout, "next", bar.output])
            }

            RailTooltip {
              target: layoutButton
              hovered: layoutHover.containsMouse
              text: bar.layoutNames[layoutCell.symbol] ?? ""
              hint: "Super+N"
            }
          }
        }
      }
    }

    ClockIsland {
      anchors.horizontalCenter: parent.horizontalCenter
      output: bar.output
    }

    StatusIsland {
      anchors.right: parent.right
      output: bar.output
    }
  }
}
