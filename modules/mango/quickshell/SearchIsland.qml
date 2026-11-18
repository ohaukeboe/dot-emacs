pragma ComponentBehavior: Bound

// The clock island as a searching popup's header: on open it widens out of
// the rail's clock into the popup's search field, and on close it narrows
// back into the clock. Put a SearchField in it and reset it in `onOpened`;
// the field's signals drive the list in the card below. `openWidth` is the
// card's width, so the field lines up with the content.
import QtQuick
import Quickshell

Island {
  id: island
  property string output
  // The Rail target of the popup this heads.
  property string target
  property int openWidth: Config.listWidth + 32
  // False keeps the clock, for a popup that has nothing to search just now.
  property bool searchable: true
  readonly property bool open: searchable && Rail.isOpen(target, output)
  // For the end of the field, where the clock went.
  readonly property string time: Qt.formatTime(clockTime.date, "HH:mm")
  default property alias content: slot.data
  signal opened()

  width: open ? openWidth : clock.implicitWidth + 32
  // Taller once open, so the search field has room above it in the card.
  height: open ? slot.height + 12 : Config.railHeight
  clip: true
  Behavior on width { Anim { duration: Config.slow } }
  Behavior on height { Anim { duration: Config.slow } }

  onOpenChanged: if (open) opened()

  SystemClock {
    id: clockTime
    precision: SystemClock.Minutes
  }

  // The rail's clock, as ClockIsland draws it, so the bloom starts from it.
  RailText {
    id: clock
    anchors.centerIn: parent
    opacity: island.open ? 0 : 1
    Behavior on opacity { Anim {} }
    font.family: Config.railFont
    textFormat: Text.StyledText
    text: "<font color='" + Config.dim + "'>" + Qt.formatDate(clockTime.date, "ddd d MMM")
      + "</font>&nbsp;&nbsp;<b>" + island.time + "</b>"
  }

  // Lined up with the content below; RailPopup leaves 8 px under the island.
  // Children fill it.
  Item {
    id: slot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    height: 40
    opacity: island.open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { Anim {} }
  }
}
