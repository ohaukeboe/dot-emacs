pragma ComponentBehavior: Bound

// A popup that grows out of the rail island holding the item that opened it
// (the "island bloom"). This full-screen overlay covers the rail, so it draws
// the island again at the rail's own place as the card's header, and the card
// grows from that island's shape down and away from the screen edge, at
// least as wide as the island. Closing shrinks it back into the island, and
// the window stays mapped until it is done. IPC opens look the same: the
// island sits where the rail puts it. Scrolls when taller than the screen
// leaves room for.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: popup
  required property var modelData
  required property string target
  // The island to grow from: an Island such as ClockIsland or StatusIsland.
  required property Component island
  default property alias content: contentBox.data
  // Right-aligned with the island instead of centred under it; the status
  // island is also placed at the right edge rather than in the middle.
  property bool endAligned: false

  readonly property bool open: Rail.openTarget === target && Rail.showsOn(modelData.name)
  // 0 closed, 1 open; overshoots past 1 briefly while opening.
  property real shown: open ? 1 : 0
  Behavior on shown {
    NumberAnimation {
      duration: popup.open ? Config.slow : 150
      easing.type: popup.open ? Easing.OutBack : Easing.InCubic
      easing.overshoot: 1.2
    }
  }

  screen: modelData
  visible: shown > 0
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.namespace: "mango-popup"

  MouseArea {
    anchors.fill: parent
    enabled: popup.open
    onClicked: Rail.close()
  }

  Item {
    id: stage
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: Rail.close()

    // The island row, then this gap, then the content.
    // The island may grow taller than the rail's once open (LauncherIsland).
    readonly property int headerHeight: Math.max(header.height, Config.railHeight) + 8
    // The card's rest when open; it starts and ends as the header island.
    readonly property rect full: {
      const w = Math.max(contentBox.childrenRect.width + 32, header.width);
      const h = Math.min(headerHeight + contentBox.childrenRect.height + 16,
        height - Config.railTop - Config.edgeGap);
      const want = popup.endAligned ? header.x + header.width - w : header.x + (header.width - w) / 2;
      return Qt.rect(Math.max(Config.edgeGap, Math.min(width - w - Config.edgeGap, want)),
        Config.railTop, w, h);
    }

    function lerp(from, to) {
      return from + (to - from) * popup.shown;
    }

    Rectangle {
      id: card
      x: stage.lerp(header.x, stage.full.x)
      y: stage.lerp(header.y, stage.full.y)
      width: stage.lerp(header.width, stage.full.width)
      height: stage.lerp(header.height, stage.full.height)
      radius: stage.lerp(Config.islandRadius, Config.cardRadius)
      color: Config.island
      clip: true

      layer.enabled: true
      layer.effect: Shadow {
        // No shadow around the island while it is still rail-sized.
        shadowOpacity: Math.min(1, popup.shown)
      }

      // Swallows clicks on the card's empty space so they do not close it.
      MouseArea { anchors.fill: parent }

      // Sized from the open card, so the content keeps its layout while the
      // card grows; it fades in once the card is mostly open.
      Flickable {
        x: 16
        y: stage.headerHeight
        width: stage.full.width - 32
        height: stage.full.height - stage.headerHeight - 16
        contentWidth: contentBox.childrenRect.width
        contentHeight: contentBox.childrenRect.height
        interactive: contentHeight > height
        clip: true
        opacity: popup.open && popup.shown > 0.6 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: popup.open ? 140 : 70 } }

        Item { id: contentBox }
      }
    }

    // The island, where the rail draws it, over the card that is its
    // background. Its items work as on the rail.
    Loader {
      id: header
      sourceComponent: popup.island
      x: popup.endAligned ? stage.width - width - Config.edgeGap : (stage.width - width) / 2
      y: Config.railTop
    }

    Binding {
      when: header.item !== null
      target: header.item
      property: "output"
      value: popup.modelData.name
    }

    Binding {
      when: header.item !== null
      target: header.item
      property: "color"
      value: "transparent"
    }
  }
}
