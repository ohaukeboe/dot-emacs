pragma ComponentBehavior: Bound

// A raised surface that sizes to its children, which go in a ColumnLayout.
// On a card that is itself raised, set `color: Config.raised2`.
import QtQuick
import QtQuick.Layouts

Rectangle {
  id: card
  default property alias content: column.data
  property int padding: 8
  property alias spacing: column.spacing

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight + 2 * padding
  radius: Config.islandRadius
  color: Config.raised

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: card.padding
    spacing: 2
  }
}
