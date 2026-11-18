pragma Singleton
pragma ComponentBehavior: Bound

// State shared by the rail (Bar.qml) and every popup: which popup is open
// and on which screen, the tray drawer, the open detail page, the usage
// limits, and the Pipewire, network and Bluetooth lists the pages show.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Networking

Singleton {
  id: shell

  // "" (closed), "controls", "calendar", "usage", "launcher", "picker" or
  // "pass" (Proton Pass quick access); one popup at a time.
  property string openTarget: ""
  property string openOutput: ""
  property string pendingTarget: ""
  // Detail page to show once an IPC open lands (onOpenTargetChanged resets page).
  property string pendingPage: ""
  // Tray drawer open. Shared, so the island a popup redraws as its header
  // is as wide as the rail's.
  property bool trayRevealed: false
  // Quick-controls detail page: "" (tiles), "phone", or "wifi", "bluetooth",
  // "output" and "input", which are the tiles with that list open.
  property string page: ""
  // Usage popup breakdown: "day" or "model".
  property string usageView: "day"
  // Phone picked on the phone page for this session; "" for the default.
  property string phoneId: ""

  // screenName comes from a rail click; IPC calls pass none.
  function toggle(target, screenName) {
    if (openTarget === target) {
      openTarget = "";
      return;
    }
    if (screenName !== undefined) {
      openOutput = screenName;
      openTarget = target;
      return;
    }
    // The pointer is on the screen the key was pressed for, so its monitor is the one.
    pendingTarget = target;
    cursorQuery.running = true;
  }

  // Idempotent open for IPC: opens target (if not already) on detail page.
  function open(target, detail) {
    if (openTarget === target) {
      page = detail;
      return;
    }
    pendingPage = detail;
    toggle(target);
  }

  function close() {
    openTarget = "";
  }

  function isOpen(target, screenName) {
    return openTarget === target && showsOn(screenName);
  }

  // Unknown output (null from mmsg): show on every screen rather than none.
  function showsOn(name) {
    return openOutput === "" || openOutput === name
      || !Quickshell.screens.some(s => s.name === openOutput);
  }

  function run(command) {
    Quickshell.execDetached(command);
  }

  onOpenTargetChanged: {
    page = "";
    usageView = "day";
    if (openTarget === "controls") brightnessRead.running = true;
  }

  onPageChanged: {
    const adapter = Bluetooth.defaultAdapter;
    if (page !== "bluetooth" && adapter && adapter.discovering)
      adapter.discovering = false;
  }

  // Claude usage limits (contracts/usage-record.md in specs/013), read once
  // for the rail's ring and the usage popup.
  readonly property string usageDir:
    (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/agent-usage"
  property var limits: null
  property real now: Date.now() / 1000
  // A window past its reset reads 0 until the status line rewrites it.
  function windowPercent(w) {
    return !w || (w.resets_at ?? 0) < now ? 0 : Math.round(w.used_percentage ?? 0);
  }
  readonly property int sessionPercent: windowPercent(limits?.session)
  readonly property int weeklyPercent: windowPercent(limits?.weekly)

  FileView {
    path: shell.usageDir + "/limits.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        shell.limits = JSON.parse(text());
      } catch (e) {
        shell.limits = null;
      }
    }
    onLoadFailed: shell.limits = null
    onFileChanged: reload()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: shell.now = Date.now() / 1000
  }

  Process {
    id: cursorQuery
    command: [Config.mmsg, "get", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        let monitor = "";
        try {
          monitor = JSON.parse(this.text).monitor || "";
        } catch (e) {}
        shell.openOutput = monitor;
        shell.openTarget = shell.pendingTarget;
        shell.page = shell.pendingPage;
        shell.pendingPage = "";
      }
    }
  }

  // The OSD, drawn by the clock island (ClockIsland.qml). The media keys
  // change a level through the "osd" IPC target (shell.qml), and the island
  // shows it for 1.5 s. osdKind is "" (hidden), "volume", "mic",
  // "brightness" or "keyboard"; osdSteps is the segment count of a stepped
  // level such as the keyboard backlight, 0 for a plain bar.
  property string osdKind: ""
  property real osdValue: 0
  property bool osdMuted: false
  property int osdSteps: 0
  function showOsd(kind, value, muted, steps) {
    osdKind = kind;
    osdValue = value;
    osdMuted = muted;
    osdSteps = steps;
    osdTimer.restart();
  }
  Timer {
    id: osdTimer
    interval: 1500
    onTriggered: shell.osdKind = ""
  }

  // Pipewire volumes are linear; step on wpctl's cube-root scale, which is
  // also what the rail shows, snapped to whole steps and capped at 100%.
  function stepVolume(delta) {
    const audio = Pipewire.defaultAudioSink?.audio;
    if (!audio) return;
    const perceived = Math.max(0, Math.min(1, Math.round((Math.cbrt(audio.volume) + delta) * 20) / 20));
    audio.volume = Math.pow(perceived, 3);
    showOsd("volume", perceived, audio.muted, 0);
  }
  function toggleMute(input) {
    const node = input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink;
    const audio = node?.audio;
    if (!audio) return;
    const muted = !audio.muted;
    audio.muted = muted;
    showOsd(input ? "mic" : "volume", Math.cbrt(audio.volume), muted, 0);
  }

  // brightnessctl -m prints "device,class,current,percent%,max".
  property int brightness: -1
  function setBrightness(percent) {
    brightness = Math.max(1, Math.round(percent));
    run([Config.brightnessctl, "--class=backlight", "set", brightness + "%"]);
  }
  // change is brightnessctl's: "5%+" or "5%-". The minimum of 1 keeps the
  // panel lit; the read that follows shows the result.
  property bool brightnessOsd: false
  function stepBrightness(change) {
    brightnessStep.command = [Config.brightnessctl, "-q", "--class=backlight", "--min-value=1", "set", change];
    brightnessStep.running = true;
  }
  Process {
    id: brightnessStep
    onExited: (code) => {
      shell.brightnessOsd = code === 0;
      brightnessRead.running = true;
    }
  }
  Process {
    id: brightnessRead
    command: [Config.brightnessctl, "-m", "--class=backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        const fields = this.text.trim().split(",");
        shell.brightness = fields.length >= 4 ? parseInt(fields[3]) : -1;
        if (shell.brightnessOsd && shell.brightness >= 0)
          shell.showOsd("brightness", shell.brightness / 100, false, 0);
        shell.brightnessOsd = false;
      }
    }
    onExited: (code) => { if (code !== 0) shell.brightness = -1; }
  }

  // Held as var: qmllint sees these ObjectModels as opaque, so `.values` would warn.
  readonly property var netDevices: Networking.devices
  readonly property var pwNodes: Pipewire.nodes
  readonly property var wifiDevice:
    netDevices.values.find(d => d.type === DeviceType.Wifi) ?? null
  // Connected first, then saved, then strongest.
  readonly property var wifiNetworks: (wifiDevice?.networks.values ?? []).slice().sort((a, b) =>
    (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
  readonly property var btDevices: (Bluetooth.defaultAdapter?.devices.values ?? []).slice().sort((a, b) =>
    (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

  // Pairing prompt from the Bluetooth agent (bt-agent.py), or null. A code
  // to type on the device ("display") has no answer, so it goes once the
  // device is paired.
  property var btRequest: null
  readonly property var btPrompt: btRequest && !(btRequest.kind === "display"
    && btDevices.some(d => d.dbusPath === btRequest.device && d.paired)) ? btRequest : null
  // value "" rejects.
  function btAnswer(value) {
    if (!btRequest) return;
    btAgent.write(btRequest.id + (value ? " " + value : "") + "\n");
    btRequest = null;
  }
  Process {
    id: btAgent
    command: [Config.btAgent]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (line) => {
        let request;
        try {
          request = JSON.parse(line);
        } catch (e) {
          return;
        }
        shell.btRequest = request.kind === "cancel" ? null : request;
        if (shell.btRequest) shell.open("controls", "bluetooth");
      }
    }
    onExited: {
      shell.btRequest = null;
      btRestart.start();
    }
  }
  // bluetoothd restarts are handled in the agent; this covers the agent dying.
  Timer {
    id: btRestart
    interval: 5000
    onTriggered: btAgent.running = true
  }

  readonly property var audioNodes: pwNodes.values.filter(n => n.audio)
  readonly property var audioOutputs: audioNodes.filter(n => !n.isStream && n.isSink)
  readonly property var audioInputs: audioNodes.filter(n => !n.isStream && !n.isSink)
  readonly property var audioStreams: audioNodes.filter(n => n.isStream)
  // Filter chains (echo cancel) are virtual streams, not apps. Properties
  // fill in once the tracker below binds the streams.
  readonly property var appStreams:
    audioStreams.filter(n => n.properties["node.virtual"] !== "true")

  Binding {
    when: shell.wifiDevice !== null
    target: shell.wifiDevice
    property: "scannerEnabled"
    value: shell.openTarget === "controls" && shell.page === "wifi"
  }

  readonly property bool audioListOpen:
    openTarget === "controls" && (page === "output" || page === "input")

  // Streams first need binding for their app names and volumes, devices for
  // their object.serial, which streamTarget matches.
  PwObjectTracker {
    objects: shell.audioListOpen ? shell.audioNodes : []
  }

  // Audio devices hidden from the output and microphone lists, by node name,
  // which stays the same across reboots.
  property var hiddenAudio: []
  function setAudioHidden(node, hide) {
    hiddenAudio = hiddenAudio.filter(n => n !== node.name).concat(hide ? [node.name] : []);
    hiddenStore.setText(JSON.stringify(hiddenAudio));
  }
  FileView {
    id: hiddenStore
    path: Quickshell.statePath("hidden-audio.json")
    printErrors: false
    onLoaded: {
      try {
        shell.hiddenAudio = JSON.parse(text());
      } catch (e) {
        shell.hiddenAudio = [];
      }
    }
  }

  // Apps pinned to a device: WirePlumber links a stream to the node its
  // "target.object" metadata names (a node name or object.serial) and
  // remembers the choice for the app. Quickshell can neither read nor write
  // metadata, so this goes through pw-metadata. Stream id -> value.
  property var streamTargets: ({})
  function streamTarget(stream) {
    const v = streamTargets[stream.id];
    if (!v) return null;
    return audioNodes.find(n => !n.isStream
      && (n.name === v || n.properties["object.serial"] === v)) ?? null;
  }
  // device null: follow the default again.
  function routeStream(stream, device) {
    run(device
      ? [Config.pwMetadata, String(stream.id), "target.object", device.name]
      : [Config.pwMetadata, "-d", String(stream.id), "target.object"]);
  }
  Process {
    running: shell.audioListOpen
    // Lists every entry on start, then each change.
    command: [Config.pwMetadata, "-m", "-n", "default"]
    onStarted: shell.streamTargets = {}
    stdout: SplitParser {
      onRead: (line) => {
        const m = line.match(/^update: id:(\d+) key:'target\.object' value:'(.*)' type:/);
        if (!m) return;
        const targets = Object.assign({}, shell.streamTargets);
        if (m[2] === "" || m[2] === "-1") delete targets[m[1]];
        else targets[m[1]] = m[2];
        shell.streamTargets = targets;
      }
    }
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
  }
}
