pragma ComponentBehavior: Bound

// The suspend, reboot and power-off buttons along the bottom of the lock
// screen and the greeter. A button acts on its second click: the first arms
// it, and `prompt` is the line asking for that click.
import QtQuick
import QtQuick.Layouts
import Quickshell

Island {
  id: island
  property string armed: ""
  readonly property var actions: [
    { action: "suspend", icon: Icons.sleep, prompt: "Click again to suspend" },
    { action: "reboot", icon: Icons.restart, prompt: "Click again to reboot" },
    { action: "poweroff", icon: Icons.power, prompt: "Click again to power off" }
  ]
  readonly property string prompt: actions.find(a => a.action === armed)?.prompt ?? ""

  function disarm() {
    armed = "";
  }

  function power(action) {
    if (armed !== action) {
      armed = action;
      return;
    }
    armed = "";
    Quickshell.execDetached([Config.systemctl, action]);
  }

  height: 52
  radius: height / 2
  width: buttons.implicitWidth + 8

  RowLayout {
    id: buttons
    anchors.centerIn: parent
    spacing: 6

    Repeater {
      model: island.actions
      IconButton {
        required property var modelData
        size: 44
        icon: modelData.icon
        on: island.armed === modelData.action
        onClicked: island.power(modelData.action)
      }
    }
  }
}
