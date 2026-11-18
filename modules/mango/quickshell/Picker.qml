pragma Singleton
pragma ComponentBehavior: Bound

// A dmenu-style choice drawn in the clock island's popup (PickerList.qml,
// with its search field in the island, PickerIsland.qml),
// for scripts through mango-pick. mango-pick passes the lines, a FIFO to
// answer on and a layout (specs/015-picker-layouts): the list (default),
// tiles (the power menu, PickerTiles.qml), sources (the screencast portal's
// chooser, PickerSources.qml) or clipboard (the history, PickerClip.qml).
// The picked value, "alt<TAB>value" for the alternate pick (mango-pick exits
// 10), or an empty line on cancel goes back through that FIFO.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: picker

  property string prompt: ""
  // "list", "tiles", "sources" or "clipboard".
  property string layout: "list"
  property var items: []
  property string query: ""
  // Row in results that Enter picks.
  property int index: 0
  // Tiles only: the tile that waits for a second pick, or -1.
  property int armed: -1
  // The FIFO the waiting mango-pick reads; "" when nothing is waiting.
  property string replyPath: ""
  // Clipboard only: line counts of decoded entries, by cliphist id.
  property var lineCounts: ({})
  // Sources only: Mango's windows by foreign_toplevel_id, as { appId, tags }.
  property var clients: ({})

  readonly property var results: {
    const q = query.trim().toLowerCase();
    if (q === "") return items;
    if (layout === "sources")
      return items.filter(l => {
        const s = source(l);
        return s.kind === "screen" || (s.title + " " + s.appId).toLowerCase().includes(q);
      });
    return items.filter(l => label(l).toLowerCase().includes(q));
  }

  onQueryChanged: index = 0

  // The width of the layout's content; the island's field is as wide.
  readonly property int contentWidth: layout === "clipboard" ? 672 : layout === "sources" ? 492 : Config.listWidth
  // Sources only: the screen cards, which come before the window rows.
  readonly property int screenCount: results.filter(l => l.startsWith("Monitor:")).length

  // Sources only: an arrow key's move. Cards sit two per row; Up/Down step a
  // row of cards, then into the rows. False when the key moves nothing.
  function step(key) {
    const i = index;
    const n = screenCount;
    const last = results.length - 1;
    let next = i;
    if (i < n) {
      if (key === Qt.Key_Left) next = Math.max(0, i - 1);
      else if (key === Qt.Key_Right) next = Math.min(n - 1, i + 1);
      else if (key === Qt.Key_Up) next = i >= 2 ? i - 2 : i;
      else next = i + 2 < n ? i + 2 : Math.min(n, last);
    } else if (key === Qt.Key_Up) {
      next = i === n ? Math.max(0, n - 1) : i - 1;
    } else if (key === Qt.Key_Down) {
      next = Math.min(last, i + 1);
    } else {
      return false;
    }
    index = next;
    return true;
  }

  // What a row shows: the text after a cliphist id and its tab.
  function label(line) {
    const tab = line.indexOf("\t");
    return tab >= 0 ? line.slice(tab + 1) : line;
  }

  // What a pick returns: a tile's label alone, otherwise the whole line.
  function returnValue(line) {
    return layout === "tiles" ? line.split("\t")[0] : line;
  }

  // A cliphist line: "<id><TAB><preview>"; images preview as
  // "[[ binary data <size> <format> <W>x<H> ]]".
  function clip(line) {
    const tab = line.indexOf("\t");
    const preview = line.slice(tab + 1);
    const m = preview.match(/^\[\[ binary data (.+) (\S+) (\d+)x(\d+) \]\]$/);
    return {
      id: tab >= 0 ? line.slice(0, tab) : line,
      preview: preview,
      kind: m ? "image" : "text",
      size: m ? m[1] : "",
      format: m ? m[2] : "",
      width: m ? Number(m[3]) : 0,
      height: m ? Number(m[4]) : 0,
    };
  }

  // An xdg-desktop-portal-wlr line (chooser.c): "Monitor: <name> <desc>" or
  // "Window: <title> (<id>)"; titles may hold parentheses, so the id is the
  // last group.
  function source(line) {
    const screen = line.match(/^Monitor: (\S+) ?(.*)$/);
    if (screen) return { kind: "screen", name: screen[1], description: screen[2] };
    const rest = line.replace(/^Window: /, "");
    const win = rest.match(/^(.*) \(([^()]*)\)$/);
    const client = win ? clients[win[2]] : undefined;
    return {
      kind: "window",
      title: win ? win[1] : rest,
      identifier: win ? win[2] : "",
      appId: client?.appId ?? "",
      tags: client?.tags ?? [],
    };
  }

  function open(title, lines, path, kind) {
    if (replyPath !== "") reply("");
    prompt = title;
    layout = ["tiles", "sources", "clipboard"].includes(kind) ? kind : "list";
    items = lines.split("\n").filter(l => l !== "");
    // Screen cards come before window rows, and Alt+N counts them first.
    if (layout === "sources")
      items = items.filter(l => l.startsWith("Monitor:")).concat(items.filter(l => !l.startsWith("Monitor:")));
    query = "";
    index = 0;
    armed = -1;
    lineCounts = {};
    clients = {};
    if (layout === "sources") clientsQuery.running = true;
    replyPath = path;
    if (items.length === 0) reply("");
    else if (Rail.openTarget !== "picker") Rail.toggle("picker");
  }

  function move(delta) {
    armed = -1;
    index = Math.max(0, Math.min(results.length - 1, index + delta));
  }

  function choose(i) {
    if (i < 0 || i >= results.length) return;
    reply(returnValue(results[i]));
    Rail.close();
  }

  // The alternate pick: the clipboard's copy without paste.
  function chooseAlt(i) {
    if (i < 0 || i >= results.length) return;
    reply("alt\t" + returnValue(results[i]));
    Rail.close();
  }

  // A tile pick: a tile with a confirm field arms first and returns on the
  // same pick again; a pick while another tile is armed only disarms.
  function pick(i) {
    if (i < 0 || i >= results.length) return;
    if (armed === i || armed === -1 && !results[i].split("\t")[2]) {
      choose(i);
    } else if (armed !== -1) {
      armed = -1;
    } else {
      index = i;
      armed = i;
    }
  }

  // Removes an entry from cliphist and from the rows; the picker stays open.
  function forget(i) {
    if (i < 0 || i >= results.length) return;
    const line = results[i];
    Quickshell.execDetached(["/bin/sh", "-c", 'printf "%s\\n" "$1" | "$2" delete', "sh", line, Config.cliphist]);
    const k = items.indexOf(line);
    items = items.slice(0, k).concat(items.slice(k + 1));
    index = Math.max(0, Math.min(i, results.length - 1));
  }

  function countLines(id, n) {
    const next = Object.assign({}, lineCounts);
    next[id] = n;
    lineCounts = next;
  }

  function reply(line) {
    const path = replyPath;
    replyPath = "";
    armed = -1;
    Quickshell.execDetached(["/bin/sh", "-c", 'printf "%s" "$1" > "$2"', "sh", line, path]);
  }

  Process {
    id: clientsQuery
    command: [Config.mmsg, "get", "all-clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        const next = {};
        try {
          for (const c of JSON.parse(this.text).clients ?? [])
            next[c.foreign_toplevel_id] = { appId: c.appid ?? "", tags: c.tags ?? [] };
        } catch (e) {}
        picker.clients = next;
      }
    }
  }

  // Any other way the popup closes (Esc, a click outside, another popup)
  // cancels, so mango-pick never waits on a closed picker.
  Connections {
    target: Rail
    function onOpenTargetChanged() {
      if (Rail.openTarget !== "picker" && picker.replyPath !== "") picker.reply("");
    }
  }
}
