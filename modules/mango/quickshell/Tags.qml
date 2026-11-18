pragma Singleton
pragma ComponentBehavior: Bound

// Mango's tag state for the rail's workspaces island (specs/014-quickshell-rail
// research R1). `mmsg watch all-tags` prints one full snapshot per line: one
// at start, then one per change. The stream restarts when it ends, e.g. when
// Mango reloads.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: tags

  // Monitor name to [{index, active, urgent, clients, layout}], in tag order.
  property var monitors: ({})
  property bool connected: false

  // Occupied tags and the active one; empty tags are not shown.
  function visible(monitor) {
    return (monitors[monitor] ?? []).filter(t => t.clients > 0 || t.active);
  }

  function view(monitor, index) {
    Quickshell.execDetached([Config.mmsg, "dispatch", "viewcrossmon," + index + "," + monitor]);
  }

  // Add or remove the tag from the view. toggleview has no crossmon form, so
  // focus the monitor first; sh keeps the two dispatches in order.
  function toggleView(monitor, index) {
    Quickshell.execDetached(["sh", "-c", '"$0" dispatch "focusmon,$1" && "$0" dispatch "toggleview,$2"',
      Config.mmsg, monitor, String(index)]);
  }

  // A line that does not parse or has no all_tags keeps the last snapshot.
  function apply(line) {
    let data;
    try {
      data = JSON.parse(line);
    } catch (e) {
      return;
    }
    if (!Array.isArray(data?.all_tags)) return;
    const next = {};
    for (const m of data.all_tags)
      next[m.monitor] = (m.tags ?? []).map(t => ({
        index: t.index,
        active: t.is_active === true,
        urgent: t.is_urgent === true,
        clients: t.client_count ?? 0,
        // Mango's layout symbol for the tag: "T", "S", "DW", ... (mmsg get layouts).
        layout: t.layout ?? "",
      })).sort((a, b) => a.index - b.index);
    monitors = next;
    connected = true;
  }

  Process {
    id: watch
    command: [Config.mmsg, "watch", "all-tags"]
    running: true
    stdout: SplitParser {
      onRead: (line) => tags.apply(line)
    }
    onExited: {
      tags.connected = false;
      restart.start();
    }
  }

  Timer {
    id: restart
    interval: 1000
    onTriggered: watch.running = true
  }
}
