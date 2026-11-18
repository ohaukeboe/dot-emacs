pragma ComponentBehavior: Bound

// A 44 px capsule slider with its icon inside, as on the design canvas.
// Drag or scroll to change the value; a click on the icon emits iconClicked.
import QtQuick

Rectangle {
  id: slider
  property real value: 0
  property string icon
  property bool iconClickable: false
  signal moved(real value)
  signal iconClicked()

  implicitHeight: 44
  radius: height / 2
  color: Config.raised

  function setFrom(x) {
    const v = Math.max(0, Math.min(1, x / width));
    moved(v);
  }

  Rectangle {
    width: Math.max(slider.height, slider.width * slider.value)
    height: parent.height
    radius: parent.radius
    color: Config.fg
  }

  HoverArea {
    anchors.fill: parent
    onPressed: (mouse) => slider.setFrom(mouse.x)
    onPositionChanged: (mouse) => { if (pressed) slider.setFrom(mouse.x); }
    onWheel: (wheel) => slider.moved(Math.max(0, Math.min(1, slider.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
  }

  Glyph {
    x: 13
    anchors.verticalCenter: parent.verticalCenter
    text: slider.icon
    color: Config.onAccent
    HoverArea {
      visible: slider.iconClickable
      tint: Config.onAccent
      anchors.fill: parent
      anchors.margins: -8
      onClicked: slider.iconClicked()
    }
  }
}
