pragma ComponentBehavior: Bound

// The picture on a display that copies another
// (specs/020-duplicate-display, research R2): a window over everything on
// the copy that shows its source's screen, pointer included, as large as
// fits. Displays.copies says which display copies which. The copy itself is
// parked where the pointer cannot go, so nothing here takes input.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: win
  required property var modelData

  readonly property string source: Displays.copies.find(p => p.copy === modelData.name)?.source ?? ""

  screen: modelData
  visible: source !== ""
  // Black whatever the palette: these are the bars beside a picture of
  // another shape (FR-002), not a surface of the shell.
  color: "black"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "mango-mirror"
  mask: Region {}

  ScreencopyView {
    anchors.centerIn: parent
    captureSource: Quickshell.screens.find(s => s.name === win.source) ?? null
    live: true
    paintCursor: true
    constraintSize: Qt.size(win.width, win.height)
  }
}
