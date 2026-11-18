pragma ComponentBehavior: Bound

// Content that opens and closes: it grows down from nothing and fades in,
// and shrinks and fades out, so whatever sits below it in a layout slides
// along and the popup around it resizes frame by frame. Children go in a
// ColumnLayout, so they size with Layout.fillWidth.
import QtQuick
import QtQuick.Layouts

Item {
  id: reveal
  property bool open: false
  // Space above the content, grown and shrunk with it. A layout adds its
  // spacing whole for any visible item and clamps negative margins to 0, so
  // closing would end in a jump by the spacing: give the layout around a
  // Reveal spacing 0 and put the space here instead.
  property real gap: 0
  default property alias content: box.data
  property alias spacing: box.spacing
  // 0 closed, 1 open.
  property real progress: open ? 1 : 0
  Behavior on progress { Anim { duration: Config.normal } }

  // Visible as soon as it starts opening, so its fields can take focus.
  visible: open || progress > 0
  Layout.fillWidth: true
  implicitHeight: (box.implicitHeight + gap) * progress
  opacity: progress
  clip: true

  // Anchored at the top only: it keeps its own height and is clipped.
  ColumnLayout {
    id: box
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: reveal.gap
    spacing: 0
  }
}
