pragma ComponentBehavior: Bound

// The lock screen (ext-session-lock through WlSessionLock): a clock, a
// password card and the power buttons on every screen, checked against the
// mango-lock PAM service. mango-lock locks it over IPC:
//   qs -c mango ipc call lock lock
//   qs -c mango ipc call lock secure   (true once every screen is covered)
// If Quickshell dies while locked, the compositor keeps the screen blank.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

Scope {
  id: root
  // "", "checking", "wrong" or "error"; the card's status line.
  property string phase: ""
  property int failures: 0
  property string password

  // False when the password was not taken (empty, or a check is running).
  function unlock(password) {
    if (password === "" || pam.active) return false;
    root.password = password;
    root.phase = "checking";
    if (!pam.start()) {
      root.password = "";
      root.phase = "error";
    }
    return true;
  }

  IpcHandler {
    target: "lock"
    function lock(): void { session.locked = true; }
    function secure(): bool { return session.secure; }
  }

  PamContext {
    id: pam
    config: "mango-lock"
    onPamMessage: {
      if (responseRequired) {
        respond(root.password);
        root.password = "";
      }
    }
    onCompleted: result => {
      if (result === PamResult.Success) {
        root.phase = "";
        root.failures = 0;
        session.locked = false;
      } else {
        root.phase = "wrong";
        root.failures += 1;
      }
    }
    onError: {
      root.password = "";
      root.phase = "error";
    }
  }

  WlSessionLock {
    id: session

    WlSessionLockSurface {
      id: surface
      color: Config.frame

      // A new lock starts with no power button armed.
      Connections {
        target: session
        function onLockedChanged() { power.disarm(); }
      }

      BatteryIsland {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Config.railTop
        anchors.rightMargin: Config.edgeGap
      }

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 28

        DisplayClock {
          Layout.alignment: Qt.AlignHCenter
        }

        PasswordCard {
          id: card
          Layout.alignment: Qt.AlignHCenter
          icon: Icons.lock
          title: "Locked"
          hint: "Enter unlock · Esc clear"
          status: {
            switch (root.phase) {
            case "checking": return "Checking…";
            case "wrong": return "Wrong password, " + root.failures
              + (root.failures === 1 ? " attempt" : " attempts");
            case "error": return "Could not check the password";
            }
            return power.prompt || "Type your password";
          }
          onTextChanged: if (text !== "" && root.phase !== "checking") root.phase = ""
          onAccepted: text => {
            if (root.unlock(text)) card.clear();
          }
        }
      }

      PowerIsland {
        id: power
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
      }
    }
  }
}
