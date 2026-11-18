pragma ComponentBehavior: Bound

// A thin progress bar; `value` runs from 0 to 1.
import QtQuick
import QtQuick.Layouts

Rectangle {
  id: meter
  property real value: 0
  property color fill: Config.fg

  Layout.fillWidth: true
  implicitHeight: 8
  radius: height / 2
  color: Config.raised

  Rectangle {
    width: parent.width * Math.max(0, Math.min(1, meter.value))
    height: parent.height
    radius: parent.radius
    color: meter.fill
  }
}
