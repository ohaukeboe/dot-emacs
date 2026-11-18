pragma Singleton
pragma ComponentBehavior: Bound

// Proton Pass quick access (specs/016-proton-pass-quick-access): runs
// `cosmic-pass serve` for the whole session and keeps the last snapshot it
// printed. PassPopup.qml draws that snapshot and sends intents back through
// send(). Contract: specs/016-proton-pass-quick-access/contracts/.
// The snapshot can hold a revealed secret: it is replaced whole by each
// line, copied into no other property and never logged.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: pass

  property var snapshot: ({})
  readonly property bool alive: backend.running
  // The sign-in URL already handed to the browser, so it opens once.
  property string openedUrl: ""
  // Restarts in a row without a snapshot in between; the loop stops at 5.
  property int failures: 0

  function send(intent) {
    if (backend.running) backend.write(JSON.stringify(intent) + "\n");
  }

  // A stopped backend gets another chance when the popup next opens.
  function wake() {
    if (backend.running) return;
    failures = 0;
    backend.running = true;
  }

  Process {
    id: backend
    command: [Config.passBackend, "serve", "--clipboard-clear-secs", Config.passClearSecs]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (line) => {
        let next;
        try {
          next = JSON.parse(line);
        } catch (e) {
          return;
        }
        pass.snapshot = next;
        pass.failures = 0;
      }
    }
    onExited: {
      pass.snapshot = {};
      if (++pass.failures < 5) restart.start();
    }
  }
  Timer {
    id: restart
    interval: 2000
    onTriggered: backend.running = true
  }

  onSnapshotChanged: {
    // The backend hides itself after a copy or Esc from the list.
    if (snapshot.visible === false && Rail.openTarget === "pass") Rail.close();
    const url = snapshot.login?.url ?? "";
    if (url !== "" && url !== openedUrl) {
      openedUrl = url;
      Qt.openUrlExternally(url);
    } else if (!snapshot.login) {
      openedUrl = "";
    }
  }

  // Rail.openTarget is the truth for open or closed, whatever closed it.
  Connections {
    target: Rail
    function onOpenTargetChanged() {
      if (Rail.openTarget === "pass") {
        pass.wake();
        pass.send({ t: "show" });
      } else if (pass.snapshot.visible) {
        pass.send({ t: "hide" });
      }
    }
  }
}
