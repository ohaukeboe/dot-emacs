pragma ComponentBehavior: Bound

// One entry in a detail-page list: name, dim detail, optional side action.
import QtQuick
import QtQuick.Layouts

Rectangle {
  id: row
  property string label
  property string detail
  property bool active
  property string action: ""
  // One step lighter on a card that is itself Config.raised.
  property color activeColor: Config.raised
  signal clicked()
  signal actionClicked()

  implicitWidth: 308
  implicitHeight: 48
  radius: Config.pillRadius
  color: active ? activeColor : "transparent"

  HoverArea {
    anchors.fill: parent
    onClicked: row.clicked()
  }

  ColumnLayout {
    anchors.left: parent.left
    anchors.right: actionText.left
    anchors.leftMargin: 12
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0
    RailText {
      Layout.fillWidth: true
      text: row.label
      font.weight: row.active ? Font.Bold : Font.Normal
      elide: Text.ElideRight
    }
    Detail {
      visible: text !== ""
      text: row.detail
    }
  }

  Detail {
    id: actionText
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    text: row.action
    HoverArea {
      anchors.fill: parent
      anchors.margins: -6
      onClicked: row.actionClicked()
    }
  }
}
