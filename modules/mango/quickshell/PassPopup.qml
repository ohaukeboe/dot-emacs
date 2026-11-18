pragma ComponentBehavior: Bound

// Proton Pass quick access (Pass.qml; specs/016-proton-pass-quick-access,
// keys in contracts/shell.md). Draws the backend's last snapshot: the item
// list with a search field, or the field list of one item, and a status
// line whenever there is nothing to list. Every key and click is sent to
// the backend as an intent; the search field owns the query and is never
// written back from a snapshot, so a late snapshot cannot eat a letter.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: popup
  spacing: 8

  readonly property var snap: Pass.snapshot
  readonly property bool fieldsMode: snap.mode === "fields"
  readonly property var rows: snap.rows ?? []
  readonly property var fields: snap.fields ?? []
  readonly property int visibleRows: 8
  readonly property int rowHeight: 48
  // Why there is nothing to list, or "" when there is.
  readonly property string status: {
    if (snap.v !== undefined && snap.v !== 1) return "Backend and shell disagree; rebuild";
    if (!Pass.alive) return Pass.failures >= 5 ? "Backend stopped; it starts again when this opens" : "Backend stopped; restarting";
    switch (snap.session) {
    case undefined:
    case "unknown":
    case "checking": return "Loading items…";
    case "signed_out": return "Signed out of Proton Pass";
    case "logging_in": return "Signing in…";
    case "locked": return "The Proton Pass session is locked; run pass-cli session unlock";
    case "cli_missing": return "pass-cli is not installed";
    case "error": return snap.session_detail ?? "Proton Pass failed";
    }
    if (fieldsMode) return fields.length === 0 ? "This item has no copyable fields" : "";
    if (rows.length > 0) return "";
    if (query.text !== "") return "No matches";
    return snap.busy?.refreshing ? "Loading items…" : "No items";
  }

  function takeFocus() {
    if (Rail.openTarget !== "pass") return;
    query.text = "";
    query.forceActiveFocus();
  }

  Component.onCompleted: takeFocus()

  Connections {
    target: Rail
    function onOpenTargetChanged() {
      popup.takeFocus();
    }
  }

  // Esc and Enter still do something useful with no backend to answer.
  function cancel() {
    if (Pass.alive && snap.visible) Pass.send({ t: "escape" });
    else Rail.close();
  }

  // Title row: the search field, or the open item and a way back.
  RowLayout {
    Layout.leftMargin: 4
    Layout.rightMargin: 4
    spacing: 10

    IconButton {
      visible: popup.fieldsMode
      icon: Icons.chevronLeft
      onClicked: Pass.send({ t: "escape" })
    }
    ColumnLayout {
      visible: popup.fieldsMode
      Layout.fillWidth: true
      spacing: 0
      RailText {
        Layout.fillWidth: true
        text: popup.snap.item?.title ?? ""
        font.pixelSize: Config.fontTitle
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Detail {
        Layout.fillWidth: true
        text: [popup.snap.item?.subtitle, popup.snap.item?.vault].filter(s => s).join(" · ")
        elide: Text.ElideRight
      }
    }

    // Collapsed, not hidden, in the field list: it keeps the keyboard focus
    // every key below is read through.
    QueryInput {
      id: query
      opacity: popup.fieldsMode ? 0 : 1
      Layout.fillWidth: !popup.fieldsMode
      Layout.preferredWidth: popup.fieldsMode ? 0 : -1
      placeholder: "Search Proton Pass…"
      readOnly: popup.fieldsMode
      onTextChanged: Pass.send({ t: "query", text: text })

      Keys.onPressed: (event) => {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const key = event.key;
        const session = popup.snap.session;
        let intent = null;
        // The COSMIC popup's keys (specs/017), except Ctrl+J, Ctrl+K and Ctrl+,.
        if (ctrl && shift && key === Qt.Key_S) {
          if (popup.snap.can_login) intent = { t: "login" };
        } else if (ctrl && shift && key === Qt.Key_R) {
          if (["locked", "error", "cli_missing"].includes(session)) intent = { t: "retry" };
        } else if (ctrl && key === Qt.Key_U) intent = { t: "copy_username" };
        else if (ctrl && key === Qt.Key_O) intent = { t: "copy_totp" };
        else if (ctrl && key === Qt.Key_L) intent = { t: "copy_url" };
        else if (key === Qt.Key_Up || ctrl && key === Qt.Key_P) intent = { t: "prev" };
        else if (key === Qt.Key_Down || ctrl && key === Qt.Key_N) intent = { t: "next" };
        else if (key === Qt.Key_PageUp) intent = { t: "page_up" };
        else if (key === Qt.Key_PageDown) intent = { t: "page_down" };
        else if (key === Qt.Key_F5) intent = { t: "refresh" };
        else if (ctrl && key === Qt.Key_R && popup.fieldsMode) intent = { t: "reveal" };
        else if (key === Qt.Key_Tab && !popup.fieldsMode) intent = { t: "open_fields" };
        else if (key === Qt.Key_Right && !popup.fieldsMode && query.text === "") intent = { t: "open_fields" };
        else if (popup.fieldsMode && (key === Qt.Key_Left || key === Qt.Key_Backtab)) intent = { t: "back" };
        // The collapsed field must not move a cursor nobody sees.
        else if (popup.fieldsMode && key === Qt.Key_Right) {}
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
          if (popup.fieldsMode) intent = { t: "activate", index: null };
          else if (popup.snap.can_login) intent = { t: "login" };
          else intent = { t: "copy_primary" };
        } else if (key === Qt.Key_Escape) {
          popup.cancel();
        } else {
          return;
        }
        if (intent) Pass.send(intent);
        event.accepted = true;
      }
    }

    IconButton {
      icon: Icons.refresh
      onClicked: Pass.send({ t: "refresh" })
    }
  }

  // The item list.
  ListView {
    id: items
    visible: !popup.fieldsMode && popup.status === ""
    Layout.preferredWidth: 480
    Layout.preferredHeight: Math.max(1, Math.min(count, popup.visibleRows)) * (popup.rowHeight + spacing) - spacing
    spacing: 2
    clip: true
    model: popup.rows
    currentIndex: popup.snap.selected ?? 0
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    boundsBehavior: Flickable.StopAtBounds

    delegate: ListRow {
      required property var modelData
      required property int index
      width: ListView.view.width
      label: modelData.title
      detail: [modelData.subtitle, modelData.vault].filter(s => s).join(" · ")
      action: "Fields"
      active: index === popup.snap.selected
      onClicked: {
        Pass.send({ t: "select", index: index });
        Pass.send({ t: "copy_primary" });
      }
      onActionClicked: {
        Pass.send({ t: "select", index: index });
        Pass.send({ t: "open_fields" });
        query.forceActiveFocus();
      }
    }
  }

  // The field list of the open item.
  ListView {
    id: fieldList
    visible: popup.fieldsMode && popup.status === ""
    Layout.preferredWidth: 480
    Layout.preferredHeight: Math.max(1, Math.min(count, popup.visibleRows)) * (popup.rowHeight + spacing) - spacing
    spacing: 2
    clip: true
    model: popup.fields
    currentIndex: popup.snap.selected ?? 0
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    boundsBehavior: Flickable.StopAtBounds

    delegate: ListRow {
      required property var modelData
      required property int index
      readonly property bool shown: modelData.value !== null || modelData.totp !== null
      width: ListView.view.width
      label: modelData.label
      // Bound straight to the snapshot; the value lives nowhere else.
      detail: modelData.totp ? modelData.totp.code + " · " + modelData.totp.remaining + "s"
        : modelData.value !== null ? modelData.value
        : modelData.revealing ? "…"
        : modelData.secret ? "••••••••" : "—"
      action: modelData.secret ? (shown ? "Hide" : "Reveal") : ""
      active: index === popup.snap.selected
      onClicked: Pass.send({ t: "activate", index: index })
      onActionClicked: {
        Pass.send({ t: "select", index: index });
        Pass.send({ t: "reveal" });
        query.forceActiveFocus();
      }
    }
  }

  // Why the list is empty, and what to do about it.
  ColumnLayout {
    visible: popup.status !== ""
    Layout.preferredWidth: 480
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    spacing: 8

    RailText {
      Layout.fillWidth: true
      text: popup.status
      wrapMode: Text.Wrap
    }
    Repeater {
      model: popup.snap.login?.lines ?? []
      Detail {
        required property string modelData
        Layout.fillWidth: true
        text: modelData
        wrapMode: Text.Wrap
      }
    }
    Pill {
      visible: popup.snap.can_login === true && Pass.alive
      label: "Sign in"
      onClicked: Pass.send({ t: "login" })
    }
  }

  // Lines that hold whether or not there are rows.
  Repeater {
    model: [popup.snap.stale, popup.snap.notice, popup.snap.cli_warning].filter(s => s)
    Detail {
      required property string modelData
      Layout.preferredWidth: 480
      Layout.leftMargin: 12
      Layout.rightMargin: 12
      text: modelData
      wrapMode: Text.Wrap
    }
  }

  Hint {
    Layout.leftMargin: 12
    text: popup.fieldsMode
      ? "Enter copy · Ctrl+R reveal · Esc back"
      : "Enter copy password · Ctrl+U username · Ctrl+O code · Tab all fields · F5 refresh"
  }
}
