pragma ComponentBehavior: Bound

// The login screen: the lock screen's look (Lock.qml) on greetd. greetd runs
// it in cage as the greeter user (modules/mango/quickshell.nix), and the
// wrapper there passes two variables:
//   MANGO_GREETER_USER      the user who logs in
//   MANGO_GREETER_SESSIONS  a JSON list of { id, name, command }, default first
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Greetd

ShellRoot {
  id: root
  readonly property string user: Quickshell.env("MANGO_GREETER_USER") ?? ""
  readonly property var sessions: JSON.parse(Quickshell.env("MANGO_GREETER_SESSIONS") ?? "[]")
  property int sessionIndex: 0
  // "", "checking", "prompt", "wrong", "error" or "starting"; the status line.
  property string phase: ""
  // The last PAM message: a follow-up prompt (one-time code) or a notice.
  property string message: ""
  // A follow-up prompt waits for the next thing typed.
  property bool awaiting: false
  property int failures: 0
  property string password

  // False when the text was not taken (empty, or a check is running).
  function login(text) {
    if (text === "" || root.phase === "checking" || root.phase === "starting")
      return false;
    if (root.awaiting) {
      root.awaiting = false;
      root.phase = "checking";
      Greetd.respond(text);
      return true;
    }
    if (!Greetd.available || root.sessions.length === 0) {
      root.phase = "error";
      return false;
    }
    root.password = text;
    root.message = "";
    root.phase = "checking";
    Greetd.createSession(root.user);
    return true;
  }

  Connections {
    target: Greetd
    // The password answers the first prompt; any later one is asked for.
    function onAuthMessage(message, error, responseRequired, echoResponse) {
      root.message = message;
      if (!responseRequired) return;
      if (root.password !== "") {
        Greetd.respond(root.password);
        root.password = "";
      } else {
        root.awaiting = true;
        root.phase = "prompt";
      }
    }
    // greetd ends the session on a failure; the next login starts a new one.
    function onAuthFailure(message) {
      root.password = "";
      root.awaiting = false;
      root.phase = "wrong";
      root.failures += 1;
    }
    function onReadyToLaunch() {
      root.phase = "starting";
      Greetd.launch(root.sessions[root.sessionIndex].command, [], true);
    }
    function onError(error) {
      root.password = "";
      root.awaiting = false;
      root.phase = "error";
    }
  }

  FloatingWindow {
    color: Config.frame

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
        icon: Icons.account
        title: root.user.charAt(0).toUpperCase() + root.user.slice(1)
        hint: "Enter log in · Esc clear"
        status: {
          switch (root.phase) {
          case "checking": return root.message || "Checking…";
          case "prompt": return root.message;
          case "starting": return "Starting " + root.sessions[root.sessionIndex].name + "…";
          case "wrong": return "Wrong password, " + root.failures
            + (root.failures === 1 ? " attempt" : " attempts");
          case "error": return "Could not reach greetd";
          }
          return power.prompt || "Type your password";
        }
        onTextChanged: if (text !== "" && (root.phase === "wrong" || root.phase === "error")) root.phase = ""
        onAccepted: text => {
          if (root.login(text)) card.clear();
        }

        Segmented {
          visible: root.sessions.length > 1
          implicitHeight: 32
          options: root.sessions.map(s => s.name)
          current: root.sessionIndex
          onPicked: index => {
            root.sessionIndex = index;
            card.focusInput();
          }
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
