pragma ComponentBehavior: Bound

// The rail's tray drawer (specs/014-quickshell-rail research R7): a chevron
// that reveals the status-notifier items to its left, so it stays put as the
// right-anchored island grows. Left click activates an item (or
// opens its menu when it has nothing else), right click opens its menu.
// Takes no room while no app has a shown tray item.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Row {
  id: tray
  // Held as var: qmllint sees the ObjectModel as opaque, so `.values` would warn.
  readonly property var items: SystemTray.items
  // Quick controls cover Wi-Fi; nm-applet keeps running only as
  // NetworkManager's secret agent.
  readonly property var shown: items.values.filter(i => i.id !== "nm-applet")
  visible: shown.length > 0
  height: Config.railHeight

  Repeater {
    model: tray.shown

    // Closed cells shrink to nothing and fade, so the drawer slides open
    // and shut and the island resizes with it.
    Rectangle {
      id: cell
      required property SystemTrayItem modelData
      width: Rail.trayRevealed ? Config.railItem : 0
      Behavior on width { Anim { duration: Config.normal } }
      visible: width > 0
      opacity: width / Config.railItem
      clip: true
      height: Config.railItem
      anchors.verticalCenter: parent?.verticalCenter
      radius: Config.pillRadius
      color: "transparent"

      // Held as var: qmllint does not know DBusMenuHandle is a QsMenuHandle.
      readonly property var trayMenu: modelData.menu
      // The symbolic variant where the theme has one, as waybar's
      // -gtk-icon-style: symbolic did; pixmap icons as they are.
      readonly property string themed:
        modelData.icon.startsWith("image://icon/") ? modelData.icon.slice(13).split("?")[0] : ""

      IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: cell.themed !== ""
          ? Quickshell.iconPath(cell.themed + "-symbolic", cell.modelData.icon)
          : cell.modelData.icon
      }

      QsMenuAnchor {
        id: menu
        menu: cell.trayMenu
        anchor.item: cell
        anchor.rect.y: cell.height + 6
      }

      HoverArea {
        id: hover
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton || cell.modelData.onlyMenu) {
            if (cell.modelData.hasMenu) menu.open();
          } else {
            cell.modelData.activate();
          }
        }
      }

      RailTooltip {
        target: cell
        hovered: hover.containsMouse
        text: cell.modelData.tooltipTitle || cell.modelData.title
      }
    }
  }

  Rectangle {
    id: chevron
    width: Config.railItem
    height: Config.railItem
    anchors.verticalCenter: parent.verticalCenter
    radius: Config.pillRadius
    color: "transparent"

    Glyph {
      anchors.centerIn: parent
      text: Icons.chevronLeft
      color: Config.dim
      font.family: Config.railIconFont
      font.pixelSize: Config.iconMedium
      rotation: Rail.trayRevealed ? 180 : 0
      Behavior on rotation { Anim {} }
    }

    HoverArea {
      anchors.fill: parent
      onClicked: Rail.trayRevealed = !Rail.trayRevealed
    }
  }
}
