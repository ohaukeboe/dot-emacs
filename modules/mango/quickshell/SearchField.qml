pragma ComponentBehavior: Bound

// The search field at the top of a popup: a capsule with the search glyph,
// an optional prompt, the query, and whatever the view puts at its end (a
// count, a button, the time). It reads the keys every list shares and
// reports them as signals: Up/Down or C-p/C-n as `moved`, Enter as
// `accepted`, Alt+1 to Alt+9 as `picked`, Esc as `cancelled`. A view's
// own keys go in `onKeyPressed`, which sees each key first and accepts the
// ones it takes.
import QtQuick
import QtQuick.Layouts

Rectangle {
  id: field
  property alias text: input.text
  property alias readOnly: input.readOnly
  // A dim label before the query, such as the picker's title.
  property string prompt
  property string placeholder: "Type to search…"
  default property alias trailing: row.data
  signal keyPressed(var event)
  signal moved(int delta)
  // ctrl: Ctrl was held, for a view with an alternate pick.
  signal accepted(bool ctrl)
  signal picked(int index)
  signal cancelled()

  function focusInput() {
    input.forceActiveFocus();
  }

  // Empties the query and takes the keyboard, as a popup does on open.
  function reset() {
    input.text = "";
    input.forceActiveFocus();
  }

  implicitWidth: 200
  implicitHeight: 40
  radius: height / 2
  color: Config.raised

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: 14
    anchors.rightMargin: 14
    spacing: 10

    Glyph {
      text: Icons.search
      color: Config.dim
      font.pixelSize: Config.iconMedium
    }

    RailText {
      visible: text !== ""
      text: field.prompt
      color: Config.dim
      font.weight: Font.DemiBold
    }

    QueryInput {
      id: input
      Layout.fillWidth: true
      placeholder: field.placeholder

      Keys.onPressed: (event) => {
        field.keyPressed(event);
        if (event.accepted) return;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_P) field.moved(-1);
        else if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_N) field.moved(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) field.accepted(ctrl);
        else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) field.picked(event.key - Qt.Key_1);
        else if (event.key === Qt.Key_Escape) field.cancelled();
        else return;
        event.accepted = true;
      }
    }
  }
}
