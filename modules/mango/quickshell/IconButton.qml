pragma ComponentBehavior: Bound

// A round icon button: raised when idle, accent-filled when `on`.
import QtQuick

Rectangle {
  id: button
  property string icon
  property bool on: false
  property int size: 36
  signal clicked()

  implicitWidth: size
  implicitHeight: size
  radius: size / 2
  color: on ? Config.fg : Config.raised

  Glyph {
    anchors.centerIn: parent
    text: button.icon
    font.pixelSize: Math.round(button.size * 0.45)
    color: button.on ? Config.onAccent : Config.fg
  }

  HoverArea {
    anchors.fill: parent
    tint: button.on ? Config.onAccent : Config.fg
    onClicked: button.clicked()
  }
}
