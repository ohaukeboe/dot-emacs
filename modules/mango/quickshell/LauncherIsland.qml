pragma ComponentBehavior: Bound

// The launcher's header (Super+d): the clock island as its search field.
// The field's keys drive the list below (Launcher.qml) through Apps.
import QtQuick

SearchIsland {
  id: island
  target: "launcher"
  openWidth: Config.launcherWidth

  onOpened: {
    Apps.query = "";
    query.reset();
  }

  SearchField {
    id: query
    anchors.fill: parent
    onTextChanged: Apps.query = text
    // Enter starts the picked app, in a terminal with Ctrl.
    onMoved: (delta) => Apps.move(delta)
    onAccepted: (ctrl) => Apps.launchPicked(ctrl)
    onPicked: (index) => Apps.launch(Apps.results[index], false)
    onCancelled: Rail.close()

    Detail {
      text: island.time
    }
  }
}
