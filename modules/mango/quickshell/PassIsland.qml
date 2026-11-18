pragma ComponentBehavior: Bound

// The Proton Pass popup's header (Super+Space; PassPopup.qml): the clock
// island as the search field, or the open item and a way back. Every key is
// sent to the backend as an intent (keys in specs/016's contracts/shell.md);
// the field owns the query and is never written back from a snapshot, so a
// late snapshot cannot eat a letter.
import QtQuick
import QtQuick.Layouts

SearchIsland {
  id: island
  target: "pass"

  readonly property var snap: Pass.snapshot
  readonly property bool fieldsMode: snap.mode === "fields"

  onOpened: query.reset()

  // Faded out, not hidden, in the field list: it keeps the keyboard focus
  // every key below is read through.
  SearchField {
    id: query
    anchors.fill: parent
    opacity: island.fieldsMode ? 0 : 1
    placeholder: "Search Proton Pass…"
    readOnly: island.fieldsMode
    onTextChanged: {
      Pass.query = text;
      Pass.send({ t: "query", text: text });
    }
    onMoved: (delta) => Pass.send({ t: delta < 0 ? "prev" : "next" })
    onAccepted: {
      if (island.fieldsMode) Pass.send({ t: "activate", index: null });
      else if (island.snap.can_login) Pass.send({ t: "login" });
      else Pass.send({ t: "copy_primary" });
    }
    // Esc still does something useful with no backend to answer.
    onCancelled: {
      if (Pass.alive && island.snap.visible) Pass.send({ t: "escape" });
      else Rail.close();
    }

    onKeyPressed: (event) => {
      const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
      const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
      const key = event.key;
      const session = island.snap.session;
      let intent = null;
      // The COSMIC popup's keys (specs/017), except Ctrl+J, Ctrl+K and Ctrl+,.
      if (ctrl && shift && key === Qt.Key_S) {
        if (island.snap.can_login) intent = { t: "login" };
      } else if (ctrl && shift && key === Qt.Key_R) {
        if (["locked", "error", "cli_missing"].includes(session)) intent = { t: "retry" };
      } else if (ctrl && key === Qt.Key_U) intent = { t: "copy_username" };
      else if (ctrl && key === Qt.Key_O) intent = { t: "copy_totp" };
      else if (ctrl && key === Qt.Key_L) intent = { t: "copy_url" };
      else if (key === Qt.Key_PageUp) intent = { t: "page_up" };
      else if (key === Qt.Key_PageDown) intent = { t: "page_down" };
      else if (key === Qt.Key_F5) intent = { t: "refresh" };
      else if (ctrl && key === Qt.Key_R && island.fieldsMode) intent = { t: "reveal" };
      else if (key === Qt.Key_Tab && !island.fieldsMode) intent = { t: "open_fields" };
      else if (key === Qt.Key_Right && !island.fieldsMode && query.text === "") intent = { t: "open_fields" };
      else if (island.fieldsMode && (key === Qt.Key_Left || key === Qt.Key_Backtab)) intent = { t: "back" };
      // The faded field must not move a cursor nobody sees.
      else if (island.fieldsMode && key === Qt.Key_Right) {}
      // The rest are the field's own: move, Enter and Esc.
      else return;
      if (intent) Pass.send(intent);
      event.accepted = true;
    }

    IconButton {
      size: 28
      color: Config.raised2
      icon: Icons.refresh
      onClicked: Pass.send({ t: "refresh" })
    }

    Detail {
      text: island.time
    }
  }

  RowLayout {
    anchors.fill: parent
    visible: island.fieldsMode
    spacing: 10

    IconButton {
      icon: Icons.chevronLeft
      onClicked: Pass.send({ t: "escape" })
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      RailText {
        Layout.fillWidth: true
        text: island.snap.item?.title ?? ""
        font.pixelSize: Config.fontTitle
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Detail {
        Layout.fillWidth: true
        text: [island.snap.item?.subtitle, island.snap.item?.vault].filter(s => s).join(" · ")
        elide: Text.ElideRight
      }
    }
    IconButton {
      icon: Icons.refresh
      onClicked: Pass.send({ t: "refresh" })
    }
  }
}
