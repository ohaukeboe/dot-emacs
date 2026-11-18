pragma ComponentBehavior: Bound

// A round toggle, a label with a status line, and an arrow to a detail page.
import QtQuick
import QtQuick.Layouts

RowLayout {
  id: row
  property string label
  property string detail
  property string icon
  property bool on: false
  // Detail page the row opens; "" for no arrow.
  property string page: ""
  // The page is a list Controls.qml shows under this row: a click toggles
  // it and the arrow turns down while it is open.
  property bool inline: false
  readonly property bool expanded: inline && Rail.page === page
  signal toggled()

  Layout.fillWidth: true
  spacing: 6

  IconButton {
    size: 44
    icon: row.icon
    on: row.on
    onClicked: row.toggled()
  }

  Item {
    Layout.fillWidth: true
    implicitHeight: 44

    ColumnLayout {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.right: arrow.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      RailText {
        Layout.fillWidth: true
        text: row.label
        font.pixelSize: Config.fontLabel
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Detail {
        Layout.fillWidth: true
        visible: text !== ""
        text: row.detail
        elide: Text.ElideRight
      }
    }

    Glyph {
      id: arrow
      visible: row.page !== ""
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: Icons.chevronRight
      color: Config.dim
      rotation: row.expanded ? 90 : 0
      Behavior on rotation { Anim {} }
    }

    HoverArea {
      anchors.fill: parent
      radius: Config.pillRadius
      enabled: row.page !== ""
      onClicked: Rail.page = row.expanded ? "" : row.page
    }
  }
}
