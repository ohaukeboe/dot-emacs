pragma ComponentBehavior: Bound

// The app launcher's list under its search field in the clock island
// (Super+d; LauncherIsland.qml): the matching apps from Apps, the picked one
// highlighted. The pointer picks a row and a click starts it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

ColumnLayout {
  id: launcher
  spacing: 8

  readonly property int rows: 8
  readonly property int rowHeight: 44

  Connections {
    target: Apps
    function onIndexChanged() {
      list.positionViewAtIndex(Apps.index, ListView.Contain);
    }
  }

  Hint {
    Layout.leftMargin: 8
    text: Apps.query.trim() !== "" ? "RESULTS"
      : Object.keys(Apps.launches).length > 0 ? "MOST USED" : "APPLICATIONS"
    font.weight: Font.DemiBold
    font.letterSpacing: 0.6
  }

  ListView {
    id: list
    Layout.preferredWidth: Config.launcherWidth - 32
    Layout.preferredHeight: launcher.rows * launcher.rowHeight + (launcher.rows - 1) * spacing
    spacing: 2
    clip: true
    model: Apps.results
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property bool picked: index === Apps.index
      readonly property string icon: Quickshell.iconPath(modelData.icon, true)

      width: ListView.view.width
      height: launcher.rowHeight
      radius: Config.pillRadius
      color: picked ? Config.raised : "transparent"

      HoverArea {
        anchors.fill: parent
        onPositionChanged: Apps.index = row.index
        onClicked: Apps.launch(row.modelData, false)
      }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 12

        IconImage {
          visible: row.icon !== ""
          implicitSize: 26
          source: row.icon
        }

        // No themed icon: the name's first letter on a tile.
        LetterTile {
          visible: row.icon === ""
          label: row.modelData.name
          picked: row.picked
        }

        RailText {
          text: row.modelData.name
          font.pixelSize: Config.fontLabel
          font.weight: Font.Medium
          elide: Text.ElideRight
          Layout.maximumWidth: 300
        }

        Detail {
          Layout.fillWidth: true
          text: row.modelData.genericName
          elide: Text.ElideRight
        }

        // The key that starts this row.
        Hint {
          text: row.picked ? "Enter" : row.index < 9 ? "Alt+" + (row.index + 1) : ""
        }
      }
    }

    RailText {
      anchors.centerIn: parent
      visible: list.count === 0
      text: "No matching apps"
      color: Config.dim
    }
  }

  Row {
    Layout.leftMargin: 10
    spacing: 16
    Repeater {
      model: ["Enter open", "Ctrl+Enter in terminal", "C-n/C-p move", "Esc close"]
      Hint {
        required property string modelData
        text: modelData
      }
    }
  }
}
