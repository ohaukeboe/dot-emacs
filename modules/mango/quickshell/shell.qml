pragma ComponentBehavior: Bound

// The Mango rail and its popups (specs/012-mango-rail-bar, restyled in
// specs/013-mango-islands-shell, drawn here since specs/014-quickshell-rail).
// Rail items open the popups directly; key bindings and scripts use IPC:
//   qs -c mango ipc call controls toggle
//   qs -c mango ipc call calendar toggle
//   qs -c mango ipc call usage toggle
//   qs -c mango ipc call launcher toggle   (Super+d)
//   qs -c mango ipc call shell openTarget
//   qs -c mango ipc call shell open controls wifi   (page "" for the tiles)
//   qs -c mango ipc call shell close
//   qs -c mango ipc call shell tray true
//   mango-pick [--layout tiles|sources|clipboard] PROMPT < lines
//                                          (the "picker" target; exit 1 on
//                                          cancel, 10 on the alternate pick)
//   qs -c mango ipc call osd volumeUp   (and the rest of the "osd" target)
//   mango-lock   (the "lock" target, Lock.qml; Super+Escape)
// It also owns desktop notifications (Notifications.qml).
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  Notifications {}
  Lock {}

  Variants {
    model: Quickshell.screens
    Bar {}
  }

  IpcHandler {
    target: "controls"
    function toggle(): void { Rail.toggle("controls"); }
  }

  IpcHandler {
    target: "calendar"
    function toggle(): void { Rail.toggle("calendar"); }
  }

  IpcHandler {
    target: "usage"
    function toggle(): void { Rail.toggle("usage"); }
  }

  IpcHandler {
    target: "launcher"
    function toggle(): void { Rail.toggle("launcher"); }
  }

  // mango-pick only; it passes the FIFO it waits on for the answer and the
  // layout ("" for the list).
  IpcHandler {
    target: "picker"
    function open(prompt: string, items: string, reply: string, layout: string): void {
      Picker.open(prompt, items, reply, layout);
    }
  }

  // Super+Space: Proton Pass quick access (Pass.qml, PassPopup.qml).
  IpcHandler {
    target: "pass"
    function toggle(): void { Rail.toggle("pass"); }
  }

  IpcHandler {
    target: "shell"
    function openTarget(): string { return Rail.openTarget; }
    function open(target: string, page: string): void { Rail.open(target, page); }
    function close(): void { Rail.close(); }
    function tray(revealed: bool): void { Rail.trayRevealed = revealed; }
  }

  // The media keys; each change shows the OSD in the clock island.
  IpcHandler {
    target: "osd"
    function volumeUp(): void { Rail.stepVolume(0.05); }
    function volumeDown(): void { Rail.stepVolume(-0.05); }
    function mute(): void { Rail.toggleMute(false); }
    function micMute(): void { Rail.toggleMute(true); }
    function brightnessUp(): void { Rail.stepBrightness("5%+"); }
    function brightnessDown(): void { Rail.stepBrightness("5%-"); }
    // Shows a level set elsewhere (mango-kbd-backlight): level of steps.
    function keyboard(level: int, steps: int): void {
      Rail.showOsd("keyboard", steps > 0 ? level / steps : 0, false, steps);
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "controls"
      island: Component { StatusIsland {} }
      endAligned: true
      Controls {}
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "calendar"
      island: Component { ClockIsland {} }
      Calendar {}
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "launcher"
      island: Component { LauncherIsland {} }
      Launcher {}
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "picker"
      island: Component { ClockIsland {} }
      PickerList {}
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "pass"
      island: Component { ClockIsland {} }
      PassPopup {}
    }
  }

  Variants {
    model: Quickshell.screens
    RailPopup {
      target: "usage"
      island: Component { StatusIsland {} }
      endAligned: true
      Usage {}
    }
  }
}
