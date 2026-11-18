pragma ComponentBehavior: Bound

// Proton Pass quick access (Pass.qml; specs/016-proton-pass-quick-access,
// keys in contracts/shell.md). Draws the backend's last snapshot under the
// search field in the island (PassIsland.qml): the item list, or the field
// list of one item, and a status line whenever there is nothing to list.
// Every click is sent to the backend as an intent.
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
    if (Pass.query !== "") return "No matches";
    return snap.busy?.refreshing ? "Loading items…" : "No items";
  }

  // The item list.
  ListView {
    id: items
    visible: !popup.fieldsMode && popup.status === ""
    Layout.preferredWidth: Config.listWidth
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
      }
    }
  }

  // The field list of the open item.
  ListView {
    id: fieldList
    visible: popup.fieldsMode && popup.status === ""
    Layout.preferredWidth: Config.listWidth
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
      }
    }
  }

  // Why the list is empty, and what to do about it.
  ColumnLayout {
    visible: popup.status !== ""
    Layout.preferredWidth: Config.listWidth
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
      Layout.preferredWidth: Config.listWidth
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
