pragma Singleton
pragma ComponentBehavior: Bound

// The displays card's state (DisplaysCard.qml, DisplayCanvas.qml;
// specs/018-display-layout-card): the connected displays as wlr-randr
// reports them, the layout being edited, and the keep-or-revert question
// after an Apply. Opened with
//   qs -c mango ipc call displays toggle
// It lives here and not in the card, because the card's window goes away
// with its display when that display is turned off. Nothing is stored:
// lasting layouts are display setups (modules/mango/displays.nix).
// A display can copy another (specs/020-duplicate-display): the layouts
// hold that as `copyOf`, read back from where the copy is parked. While a
// copy exists this also runs the guard that keeps focus and windows off
// it, keeps reading with the card closed, and repairs a copy that lost
// its source. Mirror.qml draws the picture.
import QtQuick
import Quickshell
import Quickshell.Io
import "displayLayout.mjs" as Geo

Singleton {
  id: displays

  // Three layouts (data-model.md): what is real, what the card shows, and
  // what Revert restores.
  property var applied: []
  property var pending: []
  property var previous: []
  // Name of the selected display.
  property string selected: ""
  // "closed", "idle", "applying" or "confirming".
  property string phase: "closed"
  // One line for the card's header; "" shows the matched setup instead.
  property string status: ""
  // The kanshi profile that matches the connected displays, or "".
  property string setup: ""
  property int secondsLeft: 0
  // Set by the canvas while a display is being dragged.
  property bool dragging: false

  readonly property bool open: Rail.openTarget === "displays"
  readonly property bool dirty: !Geo.same(pending, applied)
  readonly property var current: pending.find(d => d.name === selected) ?? null

  // The real copies, as { copy, source } names, and the same as one string
  // of COPY=SOURCE words for the guard.
  readonly property var copies: applied.filter(d => d.enabled && d.copyOf !== "")
    .map(d => ({ copy: d.name, source: d.copyOf }))
  readonly property string copyKey: copies.map(p => p.copy + "=" + p.source).join(" ")
  // Set by the canvas: the display a dragged tile would be dropped on.
  property string dropTarget: ""
  // The arrangement switch (data-model.md of specs/020, "Arrangement").
  property bool lidClosed: false
  readonly property var arrangeContext: ({ panel: Config.panel, lidClosed: lidClosed, selected: selected })
  readonly property var choices: Geo.choices(pending, Config.panel)
  readonly property string arrangement: Geo.arrangement(pending, arrangeContext)
  // Repairs in a row that did not help; stops a loop.
  property int repairs: 0

  // The next read replaces pending whatever it holds (open, apply, revert).
  property bool adopt: false
  // "apply" or "revert": what the running wlr-randr call is for.
  property string purpose: ""
  // What the last Apply asked for, until the read after it has been judged
  // (specs/019-honest-refresh-rate).
  property var asked: []
  // The next read decides what that Apply did.
  property bool judging: false
  // A read was asked for while one ran; its result may be from before.
  property bool reread: false

  onOpenChanged: {
    if (open) {
      phase = "idle";
      status = "";
      adopt = true;
      pending = applied;
      read();
      lid.running = true;
    } else if (phase === "confirming") {
      // Closed without an answer: as if the time ran out (FR-016).
      revert();
    } else {
      phase = "closed";
      pending = applied;
      dragging = false;
      dropTarget = "";
    }
  }

  // After a shell restart a copy is still parked: find it.
  Component.onCompleted: read()

  onCopyKeyChanged: {
    // The guard starts again with the new pairs once it has gone.
    if (guard.running) guard.running = false;
    else guard.running = copyKey !== "";
  }

  // The display a copy shows, or the display itself.
  function sourceOf(name) {
    return Geo.sourceOf(applied, name);
  }

  function read() {
    if (reader.running) reread = true;
    else reader.running = true;
  }

  // What the Apply did, from the state read after it. The exit code of
  // wlr-randr does not tell: Mango commits display by display, so a refused
  // change can be half made (specs/019, research R3).
  function judge(real) {
    if (!Geo.sameNames(real, previous)) {
      // The earlier state no longer fits the displays (FR-021).
      phase = open ? "idle" : "closed";
      status = "Displays changed; layout kept";
    } else {
      status = Geo.notTakenLine(asked, real);
      if (Geo.same(real, previous)) {
        phase = open ? "idle" : "closed";
      } else {
        phase = "confirming";
        secondsLeft = 10;
        countdown.restart();
      }
    }
    asked = [];
  }

  function select() {
    if (pending.some(d => d.name === selected)) return;
    const under = pending.find(d => d.name === Rail.openOutput && d.enabled);
    const first = under ?? pending.find(d => d.enabled) ?? pending[0];
    selected = first ? first.name : "";
  }

  function selectNext(delta) {
    if (pending.length === 0) return;
    const i = pending.findIndex(d => d.name === selected);
    selected = pending[(i + delta + pending.length) % pending.length].name;
  }

  // A fresh read of the real state (research R2).
  function took(next) {
    if (!Geo.broken(next)) {
      repairs = 0;
    } else if (repairs < 3 && !applier.running) {
      // A copy lost its source: put it back on the desktop, with no keep
      // question (research R7 of specs/020).
      repairs += 1;
      judging = false;
      asked = [];
      countdown.stop();
      applied = next;
      purpose = "repair";
      if (open) {
        phase = "applying";
        status = "The source is gone; duplicate ended";
      }
      applier.command = [Config.wlrRandr].concat(Geo.applyArgs(Geo.repair(next), next, Config.parkGap));
      applier.running = true;
      return;
    }
    const hotplug = !Geo.sameNames(next, applied);
    const changed = !Geo.same(next, applied);
    const wasDirty = dirty;
    const judged = judging;
    judging = false;
    applied = next;
    if (adopt) {
      adopt = false;
      pending = next;
      if (judged) judge(next);
    } else if (phase === "confirming") {
      if (hotplug) {
        // The earlier state no longer fits the displays (FR-021).
        countdown.stop();
        phase = "idle";
        pending = next;
        status = "Displays changed; layout kept";
      }
    } else if (phase === "idle" && (hotplug || changed)) {
      pending = next;
      if (wasDirty)
        status = hotplug ? "Displays changed; pending changes dropped"
          : "The layout changed; pending changes dropped";
    }
    select();
    if (open) profile.running = true;
  }

  // Edits. Each assigns a new list, so the card's bindings update.
  function change(name, values) {
    status = "";
    pending = Geo.settle(Geo.patch(pending, name, values), name);
  }

  function move(name, x, y, threshold) {
    pending = Geo.patch(pending, name, Geo.snap(pending, name, x, y, threshold));
  }

  // Dropped on another display, the tile joins that display's stack.
  function drop(name) {
    const target = dropTarget;
    dropTarget = "";
    if (target !== "") stack(name, target);
    pending = Geo.settle(pending, name);
    dragging = false;
  }

  function setResolution(name, w, h) {
    const d = pending.find(o => o.name === name);
    if (d) change(name, { mode: Geo.rates(d, w, h)[0] });
  }

  function setMode(name, index) {
    change(name, { mode: index });
  }

  function setScale(name, scale) {
    // A copy shows its source's picture; its own scale changes nothing.
    if (Geo.sourceOf(pending, name) !== name) return;
    change(name, { scale: scale });
  }

  function setRotation(name, degrees) {
    const d = pending.find(o => o.name === name);
    if (d) change(name, { transform: Geo.withRotation(d.transform, degrees) });
  }

  function setAdaptiveSync(name, on) {
    status = "";
    pending = Geo.patch(pending, name, { adaptiveSync: on });
  }

  function setEnabled(name, on) {
    const placed = pending.filter(d => Geo.placed(d));
    if (!on) {
      if (placed.length === 1 && placed[0].name === name && Geo.copiesOf(pending, name).length === 0) {
        status = "One display must stay on";
        return;
      }
      // A source hands the desktop to its first copy (FR-026 of specs/020).
      status = "";
      pending = Geo.disable(pending, name);
      return;
    }
    // Right of everything; settle then moves it against the nearest edge.
    let right = 0;
    for (const d of placed) right = Math.max(right, d.x + Geo.logicalSize(d).w);
    change(name, { enabled: true, x: right, y: 0 });
  }

  // Why a stack or Duplicate was not possible, as a line for the header.
  function refused(copiesAsked) {
    return copiesAsked > Geo.maxCopies ? "At most three displays can duplicate"
      : "This layout is too tall to duplicate";
  }

  // Edits of which display copies which (data-model.md of specs/020,
  // "Operations").
  function stack(name, target) {
    const next = Geo.stack(pending, name, target, Config.parkGap);
    if (next === pending) {
      const asked = pending.filter(d => d.enabled && d.copyOf !== "").length
        + 1 + Geo.copiesOf(pending, name).length;
      status = Geo.sourceOf(pending, name) === Geo.sourceOf(pending, target) ? "" : refused(asked);
      return;
    }
    status = "";
    pending = next;
  }

  function separate(name) {
    status = "";
    pending = Geo.separate(pending, name);
  }

  function makeSource(name) {
    status = "";
    pending = Geo.makeSource(pending, name);
  }

  // A choice of the arrangement switch.
  function arrange(choice) {
    if (phase !== "idle") return;
    const next = Geo.arrange(pending, choice, arrangeContext, Config.parkGap);
    if (next === pending) {
      status = arrangement === choice ? ""
        : choice === "panel" && lidClosed ? "The lid is closed"
        : choice === "duplicate" ? refused(pending.length - 1) : "";
      return;
    }
    status = "";
    pending = next;
    select();
  }

  // Left and right arrow: one choice along; from no choice, right picks
  // the first and left the last (FR-013 of specs/020).
  function arrangeStep(delta) {
    if (choices.length === 0) return;
    const i = choices.indexOf(arrangement);
    const next = i < 0 ? (delta > 0 ? 0 : choices.length - 1) : i + delta;
    if (next >= 0 && next < choices.length) arrange(choices[next]);
  }

  function apply() {
    if (phase !== "idle" || !dirty || applier.running) return;
    if (!Geo.valid(pending, Config.parkGap)) {
      status = "This layout cannot be applied";
      return;
    }
    previous = applied;
    asked = pending;
    purpose = "apply";
    phase = "applying";
    status = "";
    applier.command = [Config.wlrRandr].concat(Geo.applyArgs(pending, applied, Config.parkGap));
    applier.running = true;
  }

  function keep() {
    if (phase !== "confirming") return;
    countdown.stop();
    status = "";
    phase = "idle";
  }

  function revert() {
    if (phase !== "confirming") return;
    countdown.stop();
    purpose = "revert";
    phase = "applying";
    applier.command = [Config.wlrRandr].concat(Geo.applyArgs(previous, applied, Config.parkGap));
    applier.running = true;
  }

  function copySetup() {
    if (!copier.running) copier.running = true;
  }

  Process {
    id: reader
    command: [Config.wlrRandr, "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        let next = null;
        try {
          next = Geo.unpark(Geo.fromRandr(JSON.parse(this.text)), Config.parkGap);
        } catch (e) {}
        if (displays.reread) {
          // Asked again while this ran: this result may be from before.
          displays.reread = false;
          Qt.callLater(displays.read);
          return;
        }
        if (next === null || next.length === 0) {
          if (displays.open) displays.status = "Could not read the displays";
          if (displays.judging) {
            displays.judging = false;
            displays.phase = displays.open ? "idle" : "closed";
          }
          return;
        }
        displays.took(next);
      }
    }
  }

  // One call for every display. Its exit code is not trusted after an
  // Apply: judge() compares the state read next with the one before.
  Process {
    id: applier
    onExited: (code) => {
      displays.adopt = true;
      if (displays.purpose === "apply") {
        displays.judging = true;
      } else {
        displays.phase = displays.open ? "idle" : "closed";
        if (displays.purpose === "revert")
          displays.status = code === 0 ? "Reverted" : "Could not revert";
      }
      displays.read();
    }
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: {
      displays.secondsLeft -= 1;
      if (displays.secondsLeft <= 0) displays.revert();
    }
  }

  // wlr-randr has no event stream: look again while the card is open.
  Timer {
    interval: 2000
    repeat: true
    running: displays.open && !displays.dragging && displays.phase !== "applying"
    onTriggered: displays.read()
  }

  // Also with the card closed: a copy may have lost its source.
  Connections {
    target: Quickshell
    function onScreensChanged() {
      displays.read();
    }
  }

  // With the card closed, nothing else tells that a display setup was
  // applied over a copy, which leaves its mirror on a display that has its
  // own desktop again. So look while a copy exists.
  Timer {
    interval: 2000
    repeat: true
    running: !displays.open && displays.copyKey !== ""
    onTriggered: displays.read()
  }

  // mango-copy-guard (modules/mango/scripts.nix), while a copy exists.
  Process {
    id: guard
    command: [Config.copyGuard].concat(displays.copyKey === "" ? [] : displays.copyKey.split(" "))
    onExited: guardAgain.restart()
  }

  Timer {
    id: guardAgain
    interval: 1000
    onTriggered: guard.running = displays.copyKey !== ""
  }

  // Duplicate and Extend leave the panel off under a closed lid.
  Process {
    id: lid
    command: [Config.lidSync, "state"]
    stdout: StdioCollector {
      onStreamFinished: displays.lidClosed = this.text.trim() === "closed"
    }
  }

  // "Current profile: <name>" (research R6).
  Process {
    id: profile
    command: [Config.kanshictl, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = /^Current profile:[ \t]*(.*)$/m.exec(this.text);
        displays.setup = found ? found[1].trim() : "";
      }
    }
  }

  // mango-display-setup reads the real state, so this is the applied layout.
  Process {
    id: copier
    command: [Config.displaySetup, "--copy"]
    onExited: (code) => {
      displays.status = code !== 0 ? "Could not copy"
        : displays.copyKey !== "" ? "Copied without the duplicate"
        : displays.dirty ? "Copied the applied layout, not the pending changes"
        : "Copied. Paste into machines/machines.nix";
    }
  }
}
