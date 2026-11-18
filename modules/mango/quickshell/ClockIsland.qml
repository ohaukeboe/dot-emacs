pragma ComponentBehavior: Bound

// The rail's middle island: date and clock; opens the calendar. Drawn by
// Bar.qml and again by the calendar's RailPopup as the header of its card.
// It is also the OSD: while Rail.osdKind is set the island widens and shows
// the level in place of the clock.
import QtQuick
import Quickshell

Island {
  id: island
  property string output
  readonly property bool osd: Rail.osdKind !== ""

  width: osd ? 320 : clock.implicitWidth + 32
  color: Rail.isOpen("calendar", output) ? Config.raised : Config.island
  clip: true
  Behavior on width { Anim { duration: Config.normal } }

  SystemClock {
    id: time
    precision: SystemClock.Minutes
  }

  RailText {
    id: clock
    anchors.centerIn: parent
    opacity: island.osd ? 0 : 1
    Behavior on opacity { Anim {} }
    font.family: Config.railFont
    textFormat: Text.StyledText
    text: "<font color='" + Config.dim + "'>" + Qt.formatDate(time.date, "ddd d MMM")
      + "</font>&nbsp;&nbsp;<b>" + Qt.formatTime(time.date, "HH:mm") + "</b>"
  }

  Item {
    id: level
    readonly property string icon: {
      switch (Rail.osdKind) {
      case "volume": return Rail.osdMuted ? Icons.volumeOff : Icons.level(Icons.volumeLevels, Rail.osdValue);
      case "mic": return Rail.osdMuted ? Icons.micOff : Icons.mic;
      case "brightness": return Icons.brightness;
      case "keyboard": return Icons.keyboard;
      }
      return "";
    }
    anchors.fill: parent
    anchors.leftMargin: 6
    anchors.rightMargin: 14
    opacity: island.osd ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { Anim {} }

    // A 24 px capsule with the icon inside, as CapsuleSlider at rail size.
    Rectangle {
      id: track
      visible: Rail.osdSteps === 0
      anchors.left: parent.left
      anchors.right: percent.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      height: 24
      radius: height / 2
      color: Config.raised

      Rectangle {
        width: Math.max(track.height, track.width * Rail.osdValue)
        height: track.height
        radius: track.radius
        color: Rail.osdMuted ? Config.dim : Config.fg
        Behavior on width { Anim {} }
      }

      Glyph {
        x: 5
        anchors.verticalCenter: parent.verticalCenter
        text: level.icon
        font.family: Config.railIconFont
        font.pixelSize: Config.iconSmall
        color: Config.onAccent
      }
    }

    // A stepped level (keyboard backlight): icon, then one pill per step.
    Row {
      visible: Rail.osdSteps > 0
      anchors.left: parent.left
      anchors.leftMargin: 4
      anchors.right: percent.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4

      Glyph {
        id: stepIcon
        width: 24
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: level.icon
        font.family: Config.railIconFont
        font.pixelSize: Config.iconSmall
      }

      Repeater {
        model: Rail.osdSteps

        Rectangle {
          required property int index
          width: (parent.width - stepIcon.width - Rail.osdSteps * 4) / Rail.osdSteps
          height: 10
          radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: index < Math.round(Rail.osdValue * Rail.osdSteps) ? Config.fg : Config.raised
        }
      }
    }

    RailText {
      id: percent
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 36
      horizontalAlignment: Text.AlignRight
      font.family: Config.railFont
      font.bold: true
      font.features: { "tnum": 1 }
      text: Rail.osdMuted ? "Mute"
        : Rail.osdSteps > 0 ? Math.round(Rail.osdValue * Rail.osdSteps) + "/" + Rail.osdSteps
        : Math.round(Rail.osdValue * 100) + "%"
    }
  }

  HoverArea {
    anchors.fill: parent
    onClicked: Rail.toggle("calendar", island.output)
  }
}
