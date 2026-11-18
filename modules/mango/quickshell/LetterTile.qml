pragma ComponentBehavior: Bound

// The first letter of `label` on a small tile, for a row that has no icon.
import QtQuick

Rectangle {
  id: tile
  property string label
  // The row is highlighted, so the tile steps down to stay visible.
  property bool picked: false

  implicitWidth: 26
  implicitHeight: 26
  radius: Config.chipRadius
  color: picked ? Config.island : Config.raised

  RailText {
    anchors.centerIn: parent
    text: tile.label.charAt(0).toUpperCase()
    font.weight: Font.DemiBold
  }
}
