pragma ComponentBehavior: Bound

// Claude usage popup (specs/013-mango-islands-shell): session and weekly
// limits, and tokens by day or by model. Reads the agent-usage records
// (contracts/usage-record.md); it never writes them.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
  id: usage
  width: 328
  spacing: 14

  // Limits are read once in Rail, which the rail's usage ring shares.
  readonly property var limits: Rail.limits
  property var tokens: null
  property real now: Date.now() / 1000

  function parse(view) {
    try {
      return JSON.parse(view.text());
    } catch (e) {
      return null;
    }
  }

  function compact(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e3) return Math.round(n / 1e3) + "K";
    return String(n);
  }

  function ago(at) {
    const minutes = Math.max(0, Math.round((now - at) / 60));
    if (minutes < 1) return "just now";
    if (minutes < 60) return minutes + " min ago";
    const hours = Math.round(minutes / 60);
    return hours < 48 ? hours + " h ago" : Math.round(hours / 24) + " days ago";
  }

  function resetText(at) {
    const left = at - now;
    if (left <= 0) return "Reset";
    if (left < 86400) {
      const h = Math.floor(left / 3600);
      const m = Math.floor((left % 3600) / 60);
      return "Resets in " + (h > 0 ? h + " h " : "") + m + " min";
    }
    return "Resets " + Qt.formatDateTime(new Date(at * 1000), "ddd HH:mm");
  }

  // A window past its reset reads 0 until the status line rewrites it.
  function window(w, label) {
    if (!w) return null;
    const expired = (w.resets_at ?? 0) < now;
    return {
      label: label,
      pct: expired ? 0 : Math.round(w.used_percentage ?? 0),
      reset: resetText(w.resets_at ?? 0),
    };
  }

  readonly property var windows:
    [window(limits?.session, "Session · 5 h"), window(limits?.weekly, "Weekly")].filter(w => w)
  readonly property bool stale: limits !== null && now - (limits.updated_at ?? 0) > 1800

  readonly property var rows: {
    if (!tokens) return [];
    if (Rail.usageView === "model") {
      const models = tokens.models ?? [];
      const top = Math.max(1, ...models.map(m => m.tokens));
      return models.map(m => ({ label: m.model.replace(/^claude-/, ""), value: m.tokens,
                                share: m.tokens / top, strong: false }));
    }
    const days = tokens.days ?? [];
    const top = Math.max(1, ...days.map(d => d.tokens));
    return days.map((d, i) => {
      const last = i === days.length - 1;
      const label = last ? "Today"
        : Qt.formatDate(new Date(d.date + "T12:00:00"), "ddd");
      return { label: label, value: d.tokens, share: d.tokens / top, strong: last };
    });
  }

  FileView {
    path: Rail.usageDir + "/tokens.json"
    watchChanges: true
    printErrors: false
    onLoaded: usage.tokens = usage.parse(this)
    onLoadFailed: usage.tokens = null
    onFileChanged: reload()
  }

  Timer {
    interval: 30000
    running: Rail.openTarget === "usage"
    repeat: true
    triggeredOnStart: true
    onTriggered: usage.now = Date.now() / 1000
  }

  // Header
  RowLayout {
    Layout.fillWidth: true
    spacing: 12

    Rectangle {
      implicitWidth: 44
      implicitHeight: 44
      radius: height / 2
      color: Config.fg
      Glyph {
        anchors.centerIn: parent
        text: Icons.asterisk
        color: Config.onAccent
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      Title {
        text: "Claude Code"
      }
      Detail {
        Layout.fillWidth: true
        text: usage.limits ? (usage.stale ? "Stale · updated " : "Updated ")
            + usage.ago(usage.limits.updated_at ?? 0)
          : "No limits yet: they arrive with the next Claude Code reply"
        wrapMode: Text.Wrap
      }
    }
    IconButton {
      icon: Icons.refresh
      onClicked: Rail.run([Config.systemctl, "--user", "start", "--no-block", "agent-usage.service"])
    }
  }

  // Limits
  Repeater {
    model: usage.windows
    ColumnLayout {
      id: limit
      required property var modelData
      Layout.fillWidth: true
      spacing: 6
      RowLayout {
        Layout.fillWidth: true
        RailText {
          Layout.fillWidth: true
          text: limit.modelData.label
          font.weight: Font.DemiBold
        }
        Title {
          text: limit.modelData.pct + "%"
        }
      }
      Meter {
        value: limit.modelData.pct / 100
      }
      Detail {
        text: limit.modelData.reset
      }
    }
  }

  Detail {
    visible: (usage.tokens?.error ?? "") !== ""
    Layout.fillWidth: true
    text: usage.tokens?.error ?? ""
    wrapMode: Text.Wrap
  }

  Segmented {
    visible: usage.tokens !== null
    options: ["By day", "By model"]
    current: Rail.usageView === "model" ? 1 : 0
    onPicked: (i) => Rail.usageView = i === 1 ? "model" : "day"
  }

  ColumnLayout {
    visible: usage.tokens !== null
    Layout.fillWidth: true
    spacing: 6

    Repeater {
      model: usage.rows
      RowLayout {
        id: row
        required property var modelData
        Layout.fillWidth: true
        spacing: 10
        RailText {
          Layout.preferredWidth: Rail.usageView === "model" ? 110 : 44
          text: row.modelData.label
          color: row.modelData.strong ? Config.fg : Config.dim
          font.pixelSize: Config.fontSmall
          font.weight: row.modelData.strong ? Font.Bold : Font.Normal
          elide: Text.ElideRight
        }
        Meter {
          implicitHeight: 6
          value: row.modelData.share
          fill: row.modelData.strong || Rail.usageView === "model" ? Config.fg : Config.dim
        }
        RailText {
          Layout.preferredWidth: 44
          horizontalAlignment: Text.AlignRight
          text: usage.compact(row.modelData.value)
          color: row.modelData.strong ? Config.fg : Config.dim
          font.pixelSize: Config.fontSmall
          font.weight: row.modelData.strong ? Font.Bold : Font.Normal
        }
      }
    }
  }

  // Footer
  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    RailText {
      Layout.fillWidth: true
      visible: usage.tokens !== null
      textFormat: Text.StyledText
      text: "<b>" + usage.compact(usage.tokens?.week_tokens ?? 0) + "</b>"
        + "<font color=\"" + Config.dim + "\"> tokens this week</font>"
    }
    Item {
      visible: usage.tokens === null
      Layout.fillWidth: true
    }
    Rectangle {
      visible: Config.claude !== ""
      implicitWidth: openRow.implicitWidth + 28
      implicitHeight: 36
      radius: height / 2
      color: Config.raised
      RowLayout {
        id: openRow
        anchors.centerIn: parent
        spacing: 8
        Glyph {
          text: Icons.terminal
          font.pixelSize: Config.iconMedium
        }
        RailText {
          text: "Open Claude"
          font.pixelSize: Config.fontSmall
          font.weight: Font.DemiBold
        }
      }
      HoverArea {
        anchors.fill: parent
        onClicked: {
          Rail.close();
          Rail.run([Config.terminal, "-e", Config.claude]);
        }
      }
    }
  }
}
