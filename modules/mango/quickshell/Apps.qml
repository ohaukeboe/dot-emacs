pragma Singleton
pragma ComponentBehavior: Bound

// The launcher's state, shared by its search field in the clock island
// (LauncherIsland.qml) and its list (Launcher.qml): the query, the picked
// row, the matching desktop entries and the launch counts. An empty query
// lists the most launched apps first; the counts live in Quickshell's state
// dir. Apps start in their own systemd scope, so restarting the shell does
// not take them down with it.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: apps

  property string query: ""
  // Row in results that Enter starts.
  property int index: 0
  // Desktop-entry id to launch count.
  property var launches: ({})

  onQueryChanged: index = 0

  // Name prefix beats word prefix beats name substring beats the other
  // fields; 0 hides the entry.
  function score(entry, q) {
    if (q === "") return 1;
    const name = entry.name.toLowerCase();
    if (name.startsWith(q)) return 4;
    if (name.split(/\s+/).some(w => w.startsWith(q))) return 3;
    if (name.includes(q)) return 2;
    const rest = [entry.genericName, entry.id].concat(entry.keywords).join(" ").toLowerCase();
    return rest.includes(q) ? 1 : 0;
  }

  readonly property var results: {
    const q = query.trim().toLowerCase();
    const scored = [];
    for (const entry of DesktopEntries.applications.values) {
      if (entry.noDisplay) continue;
      const s = score(entry, q);
      if (s > 0) scored.push({ entry: entry, s: s, n: launches[entry.id] ?? 0 });
    }
    scored.sort((a, b) => b.s - a.s || b.n - a.n || a.entry.name.localeCompare(b.entry.name));
    return scored.map(r => r.entry);
  }

  function move(delta) {
    index = Math.max(0, Math.min(results.length - 1, index + delta));
  }

  // inTerminal (Ctrl+Enter) runs a graphical app in a terminal too, to see its output.
  function launch(entry, inTerminal) {
    if (!entry) return;
    const counts = Object.assign({}, launches);
    counts[entry.id] = (counts[entry.id] ?? 0) + 1;
    launches = counts;
    store.setText(JSON.stringify(counts));
    const command = entry.runInTerminal || inTerminal
      ? [Config.terminal, "-e"].concat(entry.command) : entry.command;
    Rail.run([Config.systemdRun, "--user", "--scope", "--collect", "--quiet", "--"].concat(command));
    Rail.close();
  }

  function launchPicked(inTerminal) {
    launch(results[index], inTerminal);
  }

  FileView {
    id: store
    path: Quickshell.statePath("launches.json")
    printErrors: false
    onLoaded: {
      try {
        apps.launches = JSON.parse(text());
      } catch (e) {
        apps.launches = {};
      }
    }
  }
}
