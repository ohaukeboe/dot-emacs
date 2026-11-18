pragma ComponentBehavior: Bound

// The clock island as the launcher's header: on open it widens out of the
// rail's clock into the search field, keeping the time at its right end,
// and on close it narrows back into the clock. Up, Down and Enter drive the
// list below (Launcher.qml) through Apps.
import QtQuick
import Quickshell

Island {
  id: island
  property string output
  readonly property bool open: Rail.isOpen("launcher", output)

  width: open ? Config.launcherWidth : clock.implicitWidth + 32
  // Taller once open, so the search row has room above it in the card.
  height: open ? Config.railHeight + 16 : Config.railHeight
  clip: true
  Behavior on width { Anim { duration: Config.slow } }
  Behavior on height { Anim { duration: Config.slow } }

  onOpenChanged: {
    if (!open) return;
    query.text = "";
    Apps.query = "";
    query.forceActiveFocus();
  }

  SystemClock {
    id: time
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
    text: "<font color='" + Config.dim + "'>" + Qt.formatDate(time.date, "ddd d MMM")
      + "</font>&nbsp;&nbsp;<b>" + Qt.formatTime(time.date, "HH:mm") + "</b>"
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    // RailPopup leaves 8 px under the island before the list's divider;
    // this centres the row between the card's top edge and that divider.
    anchors.topMargin: 8
    opacity: island.open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { Anim {} }

    Glyph {
      id: searchIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: Icons.search
      color: Config.dim
      font.pixelSize: Config.iconMedium
    }

    QueryInput {
      id: query
      anchors.left: searchIcon.right
      anchors.right: clockSmall.left
      anchors.leftMargin: 10
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      onTextChanged: Apps.query = text

      // Up/Down or C-p/C-n move, Enter starts (Ctrl+Enter in a terminal),
      // Alt+1 to Alt+9 start that row.
      Keys.onPressed: (event) => {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_P) Apps.move(-1);
        else if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_N) Apps.move(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Apps.launchPicked(ctrl);
        else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
          Apps.launch(Apps.results[event.key - Qt.Key_1], false);
        else return;
        event.accepted = true;
      }
      Keys.onEscapePressed: Rail.close()
      placeholder: "Type to search…"
    }

    Detail {
      id: clockSmall
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Qt.formatTime(time.date, "HH:mm")
      font.family: Config.railFont
    }
  }
}
