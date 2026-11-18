pragma ComponentBehavior: Bound

// The rail's right island: tray drawer, Claude usage ring and the controls
// capsule. Drawn by Bar.qml and again by the usage and quick-controls
// RailPopups as the header of their card.
import QtQuick
import QtQuick.Shapes
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Island {
  id: island
  property string output

  width: statusRow.implicitWidth + 12

  // A 28 px status icon: a glyph, or an accent-filled warning.
  component StatusIcon: Rectangle {
    id: icon
    property string glyph
    property bool dim: false
    property bool warn: false
    width: Config.railItem
    height: Config.railItem
    radius: Config.pillRadius
    color: warn ? Config.fg : "transparent"
    Glyph {
      anchors.centerIn: parent
      text: icon.glyph
      font.family: Config.railIconFont
      font.pixelSize: Config.iconMedium
      color: icon.warn ? Config.onAccent : icon.dim ? Config.dim : Config.fg
    }
  }

  Row {
    id: statusRow
    anchors.verticalCenter: parent.verticalCenter
    x: 6
    spacing: 4

    Tray {}

    // Session usage as a ring; the numbers are in the tooltip.
    Rectangle {
      id: usagePill
      readonly property bool open: Rail.isOpen("usage", island.output)
      readonly property color ink: open ? Config.onAccent : Config.fg
      visible: Rail.limits !== null
      anchors.verticalCenter: parent.verticalCenter
      width: Config.railItem
      height: Config.railItem
      radius: Config.pillRadius
      color: open ? Config.fg : "transparent"

      Shape {
        anchors.centerIn: parent
        width: 16
        height: 16
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Qt.alpha(usagePill.ink, 0.25)
          strokeWidth: 2.5
          fillColor: "transparent"
          PathAngleArc { centerX: 8; centerY: 8; radiusX: 6; radiusY: 6; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
          strokeColor: Rail.sessionPercent > 0 ? usagePill.ink : "transparent"
          strokeWidth: 2.5
          capStyle: ShapePath.RoundCap
          fillColor: "transparent"
          PathAngleArc {
            centerX: 8; centerY: 8; radiusX: 6; radiusY: 6
            startAngle: -90
            sweepAngle: 3.6 * Rail.sessionPercent
          }
        }
      }

      HoverArea {
        id: usageHover
        anchors.fill: parent
        tint: usagePill.ink
        onClicked: Rail.toggle("usage", island.output)
      }

      RailTooltip {
        target: usagePill
        hovered: usageHover.containsMouse
        text: "Session " + Rail.sessionPercent + "% · weekly " + Rail.weeklyPercent + "%"
      }
    }

    // Phone, network, sound and battery share one raised capsule; any of
    // them opens quick controls.
    Rectangle {
      id: controls
      anchors.verticalCenter: parent.verticalCenter
      width: controlRow.implicitWidth + 8
      height: Config.railItem
      radius: Config.pillRadius
      color: Config.raised

      readonly property var sink: Pipewire.defaultAudioSink
      readonly property var battery: UPower.displayDevice
      readonly property var wifi: Rail.wifiNetworks.find(n => n.connected) ?? null
      readonly property var wired:
        Rail.netDevices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
      readonly property bool lowBattery: battery.isLaptopBattery && battery.percentage <= 0.15
        && battery.state === UPowerDeviceState.Discharging

      // Pipewire volumes are linear; wpctl and waybar show the cube root.
      function perceived(volume) {
        return Math.cbrt(volume);
      }

      function hours(seconds) {
        const m = Math.round(seconds / 60);
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min";
      }

      readonly property string tip: {
        if (!hover.containsMouse) return "";
        const x = hover.mouseX - controlRow.x;
        const item = controlRow.childAt(x, controlRow.height / 2);
        if (item === netIcon)
          return wifi ? wifi.name + " (" + Math.round(wifi.signalStrength * 100) + "%)"
            : wired ? wired.name : "offline";
        if (item === soundIcon && sink)
          return (sink.description || sink.name) + " " + Math.round(perceived(sink.audio?.volume ?? 0) * 100) + "%";
        if (item === batteryIcon) {
          const left = battery.state === UPowerDeviceState.Charging ? battery.timeToFull : battery.timeToEmpty;
          return Math.round(battery.percentage * 100) + "%" + (left > 0 ? " " + hours(left) : "");
        }
        return "";
      }

      Row {
        id: controlRow
        anchors.centerIn: parent

        Loader {
          active: Config.kdeconnect
          source: Config.kdeconnect ? "PhoneIcon.qml" : ""
        }

        StatusIcon {
          id: netIcon
          dim: !controls.wifi && !controls.wired
          glyph: controls.wifi ? Icons.level(Icons.wifiLevels, controls.wifi.signalStrength)
            : controls.wired ? Icons.ethernet : Icons.offline
        }

        StatusIcon {
          id: soundIcon
          readonly property bool muted: controls.sink?.audio?.muted ?? true
          dim: muted
          glyph: muted ? Icons.volumeOff
            : Icons.level(Icons.volumeLevels, controls.perceived(controls.sink?.audio?.volume ?? 0))
        }

        StatusIcon {
          id: batteryIcon
          visible: controls.battery.isLaptopBattery
          warn: controls.lowBattery
          glyph: Icons.battery(controls.battery)
        }
      }

      HoverArea {
        id: hover
        anchors.fill: parent
        onClicked: Rail.toggle("controls", island.output)
      }

      RailTooltip {
        target: controls
        hovered: hover.containsMouse
        text: controls.tip
      }
    }
  }
}
