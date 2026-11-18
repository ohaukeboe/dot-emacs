pragma ComponentBehavior: Bound

// The picker's header (Picker.qml): the clock island as the search field of
// the list, sources and clipboard layouts. The tiles layout has no filter
// and keeps the clock. Typing filters, Up/Down or C-p/C-n move, Enter or
// Alt+1 to Alt+9 pick, Esc cancels; the clipboard adds Ctrl+Enter to copy
// only and Delete to forget, the sources Left/Right across the cards.
import QtQuick

SearchIsland {
  id: island
  target: "picker"
  openWidth: Picker.contentWidth + 32
  searchable: Picker.layout !== "tiles"

  onOpened: query.reset()

  SearchField {
    id: query
    anchors.fill: parent
    prompt: Picker.prompt
    placeholder: Picker.layout === "sources" ? "Type to filter windows…" : "Type to search…"
    onTextChanged: Picker.query = text
    onMoved: (delta) => {
      if (Picker.layout === "sources") Picker.step(delta < 0 ? Qt.Key_Up : Qt.Key_Down);
      else Picker.move(delta);
    }
    onAccepted: (ctrl) => {
      if (ctrl && Picker.layout === "clipboard") Picker.chooseAlt(Picker.index);
      else Picker.choose(Picker.index);
    }
    onPicked: (index) => Picker.choose(index)
    onCancelled: Rail.close()
    onKeyPressed: (event) => {
      if (Picker.layout === "clipboard" && event.key === Qt.Key_Delete) {
        Picker.forget(Picker.index);
        event.accepted = true;
      } else if (Picker.layout === "sources" && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
        // Across the cards; in the rows these move the cursor.
        if (Picker.step(event.key)) event.accepted = true;
      }
    }

    Detail {
      visible: Picker.layout !== "sources"
      text: Picker.results.length + " of " + Picker.items.length
    }

    Detail {
      text: island.time
    }
  }
}
