pragma ComponentBehavior: Bound

// A small labelled toggle (Join, Scan, Mute): accent-filled when `on`.
import QtQuick

Rectangle {
  id: pill
  property string label
  property bool on: false
  signal clicked()

  implicitWidth: Math.max(56, labelText.implicitWidth + 24)
  implicitHeight: 30
  radius: height / 2
  color: on ? Config.fg : Config.raised

  RailText {
    id: labelText
    anchors.centerIn: parent
    text: pill.label
    font.pixelSize: Config.fontSmall
    font.weight: Font.DemiBold
    color: pill.on ? Config.onAccent : Config.fg
  }

  HoverArea {
    anchors.fill: parent
    tint: pill.on ? Config.onAccent : Config.fg
    onClicked: pill.clicked()
  }
}
