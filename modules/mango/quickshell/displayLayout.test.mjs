// Build-time test of displayLayout.mjs (mango-display-layout-test in
// modules/mango/quickshell.nix): node displayLayout.test.mjs
import assert from "node:assert/strict";
import * as L from "./displayLayout.mjs";

const mode = (width, height, refresh, flags = {}) =>
  Object.assign({ width, height, refresh, preferred: false, current: false }, flags);

// The laptop panel as wlr-randr reports it.
const panelJson = {
  name: "eDP-1", make: "Sharp Corporation", model: "LQ134N1JW52", serial: null, enabled: true,
  modes: [mode(1920, 1200, 120.002998, { preferred: true, current: true }),
    mode(1920, 1200, 60.002998), mode(1920, 1080, 120.002998)],
  position: { x: 0, y: 0 }, transform: "normal", scale: 1.0, adaptive_sync: false,
};
const dellJson = {
  name: "DP-3", make: "Dell Inc.", model: "DELL U2723QE", serial: "ABC123", enabled: true,
  modes: [mode(3840, 2160, 60, { preferred: true, current: true }), mode(2560, 1440, 59.951),
    mode(1920, 1080, 60)],
  position: { x: 1920, y: 0 }, transform: "normal", scale: 1.5, adaptive_sync: false,
};
const offJson = { name: "HDMI-A-1", make: null, model: null, serial: null, enabled: false,
  modes: [mode(1280, 720, 60), mode(1920, 1080, 60, { preferred: true })] };

const one = L.fromRandr([panelJson]);
const two = L.fromRandr([panelJson, dellJson]);
const withOff = L.fromRandr([panelJson, offJson]);
const at = (layout, name) => layout.find(d => d.name === name);
// How far below its source a copy is parked (parkGap in common.nix).
const gap = 8192;

// fromRandr
assert.equal(one.length, 1);
assert.deepEqual(
  { name: one[0].name, mode: one[0].mode, x: one[0].x, scale: one[0].scale, serial: one[0].serial },
  { name: "eDP-1", mode: 0, x: 0, scale: 1, serial: "" });
assert.equal(at(withOff, "HDMI-A-1").enabled, false);
assert.equal(at(withOff, "HDMI-A-1").mode, 1, "an off display gets its preferred mode");
assert.equal(at(withOff, "HDMI-A-1").scale, 1);
assert.equal(L.label(at(withOff, "HDMI-A-1")), "HDMI-A-1");
assert.equal(L.label(one[0]), "LQ134N1JW52");

// logicalSize
assert.deepEqual(L.logicalSize(one[0]), { w: 1920, h: 1200 });
assert.deepEqual(L.logicalSize(L.patch(one, "eDP-1", { scale: 1.25 })[0]), { w: 1536, h: 960 });
assert.deepEqual(L.logicalSize(at(two, "DP-3")), { w: 2560, h: 1440 });
assert.deepEqual(L.logicalSize(L.patch(one, "eDP-1", { transform: "90" })[0]), { w: 1200, h: 1920 });
assert.deepEqual(L.logicalSize(L.patch(one, "eDP-1", { transform: "flipped-270", scale: 1.5 })[0]),
  { w: 800, h: 1280 });

// resolutions, rates, rotation
assert.deepEqual(L.resolutions(one[0]), [{ w: 1920, h: 1200 }, { w: 1920, h: 1080 }]);
assert.deepEqual(L.rates(one[0], 1920, 1200), [0, 1]);
assert.equal(L.rotation("flipped-90"), 90);
assert.equal(L.rotation("normal"), 0);
assert.equal(L.withRotation("normal", 90), "90");
assert.equal(L.withRotation("180", 0), "normal");
assert.equal(L.withRotation("flipped-90", 0), "flipped");
assert.equal(L.withRotation("flipped", 270), "flipped-270");

// normalise
const shifted = L.normalise(L.patch(two, "DP-3", { x: -2560, y: -100 }));
assert.deepEqual([at(shifted, "DP-3").x, at(shifted, "DP-3").y], [0, 0]);
assert.deepEqual([at(shifted, "eDP-1").x, at(shifted, "eDP-1").y], [2560, 100]);

// valid
assert.equal(L.valid(two, gap), true);
assert.equal(L.valid(one, gap), true);
assert.equal(L.valid(L.patch(two, "DP-3", { x: 1000 }), gap), false, "overlap");
assert.equal(L.valid(L.patch(two, "DP-3", { x: 2000 }), gap), false, "gap");
assert.equal(L.valid(L.patch(two, "DP-3", { x: 1920, y: 1200 }), gap), false, "corner only");
assert.equal(L.valid(L.patch(one, "eDP-1", { enabled: false }), gap), false, "none enabled");
assert.equal(L.valid(L.patch(two, "eDP-1", { x: 10 }).map(d =>
  d.name === "DP-3" ? Object.assign({}, d, { x: 1930 }) : d), gap), false, "not at 0,0");

// same
assert.equal(L.same(two, L.fromRandr([panelJson, dellJson])), true);
assert.equal(L.same(two, L.patch(two, "DP-3", { y: 10 })), false);
assert.equal(L.same(withOff, L.patch(withOff, "HDMI-A-1", { scale: 2 })), true,
  "an off display's values do not count");
assert.equal(L.sameNames(two, withOff), false);

// applyArgs
assert.deepEqual(L.applyArgs(withOff, withOff, gap), [
  "--output", "eDP-1", "--on", "--mode", "1920x1200@120.002998Hz", "--pos", "0,0",
  "--scale", "1", "--transform", "normal",
  "--output", "HDMI-A-1", "--off"]);
assert.deepEqual(L.applyArgs(L.patch(one, "eDP-1", { adaptiveSync: true, scale: 1.25 }), one, gap), [
  "--output", "eDP-1", "--on", "--mode", "1920x1200@120.002998Hz", "--pos", "0,0",
  "--scale", "1.25", "--transform", "normal", "--adaptive-sync", "enabled"]);

// frame
const f = L.frame(two, 616, 240, 28);
assert.ok(Math.abs(f.k - 560 / 4480) < 1e-9);
assert.ok(Math.abs(f.ox - 28) < 1e-9);

// snap
assert.deepEqual(L.snap(two, "DP-3", 1930, 8, 20), { x: 1920, y: 0 });
assert.deepEqual(L.snap(two, "DP-3", 2500, 300, 20), { x: 2500, y: 300 });
assert.deepEqual(L.snap(two, "DP-3", -2550, -245, 20), { x: -2560, y: -240 });

// settle: dropped on top of the other
let s = L.settle(L.patch(two, "DP-3", { x: 100, y: 50 }), "DP-3");
assert.equal(L.valid(s, gap), true);
// settle: dropped far away comes back, on the side it was dropped
s = L.settle(L.patch(two, "DP-3", { x: -9000, y: 300 }), "DP-3");
assert.equal(L.valid(s, gap), true);
assert.equal(at(s, "DP-3").x, 0);
assert.equal(at(s, "eDP-1").x, 2560);
// settle: a legal drop stays where it is
s = L.settle(L.patch(two, "DP-3", { x: 1920, y: -240 }), "DP-3");
assert.deepEqual([at(s, "DP-3").x, at(s, "DP-3").y, at(s, "eDP-1").y], [1920, 0, 240]);
// settle: moving the middle display strands the third, which follows
const thirdJson = Object.assign({}, dellJson, { name: "DP-4", serial: "XYZ", position: { x: 4480, y: 0 } });
const three = L.fromRandr([panelJson, dellJson, thirdJson]);
assert.equal(L.valid(three, gap), true);
s = L.settle(L.patch(three, "DP-3", { x: 0, y: 1200 }), "DP-3");
assert.equal(L.valid(s, gap), true);
// settle: a scaled display beside an unscaled one
s = L.settle(L.patch(two, "eDP-1", { scale: 1.5 }), "eDP-1");
assert.equal(L.valid(s, gap), true);
// settle: turning one off leaves the other at 0,0 and ignores the off one
s = L.settle(L.patch(two, "eDP-1", { enabled: false }), "eDP-1");
assert.equal(L.valid(s, gap), true);
assert.deepEqual([at(s, "DP-3").x, at(s, "DP-3").y], [0, 0]);
// settle: turning the middle one off joins the outer two
s = L.settle(L.patch(three, "DP-3", { enabled: false }), "DP-3");
assert.equal(L.valid(s, gap), true);
// settle: rotation keeps the neighbours touching
s = L.settle(L.patch(three, "DP-3", { transform: "90" }), "DP-3");
assert.equal(L.valid(s, gap), true);
// settle: many random drops always give a valid layout
let seed = 7;
const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
let layout = three;
for (let i = 0; i < 500; i++) {
  const name = ["eDP-1", "DP-3", "DP-4"][Math.floor(random() * 3)];
  layout = L.settle(L.patch(layout, name, {
    x: Math.round(random() * 12000 - 4000), y: Math.round(random() * 8000 - 3000),
    scale: L.scales[Math.floor(random() * 4)],
    transform: ["normal", "90", "180", "270"][Math.floor(random() * 4)],
  }), name);
  assert.equal(L.valid(layout, gap), true, "random drop " + i);
}

// notTaken (specs/019-honest-refresh-rate)
assert.deepEqual(L.notTaken(two, two), []);
assert.equal(L.notTakenLine(two, two), "");
assert.deepEqual(L.notTaken(L.patch(two, "DP-3", { mode: 1 }), two).map(d => d.name), ["DP-3"]);
assert.equal(L.notTakenLine(L.patch(two, "DP-3", { mode: 1 }), two), "DELL U2723QE cannot run at 59.95 Hz here");
assert.equal(L.notTakenLine(L.patch(two, "eDP-1", { mode: 1 }), two), "LQ134N1JW52 cannot run at 60 Hz here");
assert.equal(L.notTakenLine(L.patch(two, "DP-3", { x: 4000 }), two), "DELL U2723QE did not take the change");
assert.equal(L.notTakenLine(L.patch(L.patch(two, "DP-3", { x: 4000 }), "eDP-1", { scale: 2 }), two),
  "Some displays did not take the change");
assert.equal(L.notTakenLine(L.patch(two, "DP-3", { enabled: false }), two), "DELL U2723QE did not take the change");
// notTaken: a display that appeared after Apply was asked nothing
assert.deepEqual(L.notTaken(one, two), []);

// Copies (specs/020-duplicate-display). In `three` the panel is at 0,0,
// DP-3 at 1920,0 and DP-4 at 4480,0.
const names = layout => layout.filter(L.placed).map(d => d.name);
const copyNames = layout => layout.filter(d => d.enabled && d.copyOf).map(d => d.name + "=" + d.copyOf);
// No copy is ever a source (FR-003), and the placed displays hold together.
const sound = (layout, what) => {
  assert.equal(L.valid(layout, gap), true, what + ": valid");
  for (const d of layout)
    if (d.enabled && d.copyOf) assert.equal(L.placed(at(layout, d.copyOf)), true, what + ": source is placed");
};
const parkedJson = (json, x, y) => Object.assign({}, json, { position: { x: x, y: y } });

// unpark: a display at its source's x, one and two gaps down
let read = L.unpark(L.fromRandr([panelJson, parkedJson(dellJson, 0, gap)]), gap);
assert.deepEqual([at(read, "DP-3").copyOf, at(read, "DP-3").x, at(read, "DP-3").y], ["eDP-1", 0, 0]);
assert.equal(at(read, "DP-3").orphan, false);
read = L.unpark(L.fromRandr([parkedJson(panelJson, 300, 40), parkedJson(dellJson, 300, 40 + 2 * gap)]), gap);
assert.equal(at(read, "DP-3").copyOf, "eDP-1");
// unpark: nothing above it is an orphan, left where the source was
read = L.unpark(L.fromRandr([panelJson, parkedJson(dellJson, 500, gap + 7)]), gap);
assert.deepEqual([at(read, "DP-3").copyOf, at(read, "DP-3").orphan, at(read, "DP-3").y], ["", true, 7]);
assert.equal(L.valid(read, gap), false, "an orphan");
assert.deepEqual(L.unpark(two, gap), two, "nothing parked");

// park and unpark are each other's reverse
const oneCopy = L.stack(two, "DP-3", "eDP-1", gap);
assert.deepEqual(copyNames(oneCopy), ["DP-3=eDP-1"]);
sound(oneCopy, "one copy");
assert.deepEqual(L.unpark(L.park(oneCopy, gap), gap), oneCopy);
const twoCopies = L.stack(L.stack(three, "DP-3", "eDP-1", gap), "DP-4", "eDP-1", gap);
assert.deepEqual(copyNames(twoCopies), ["DP-3=eDP-1", "DP-4=eDP-1"]);
assert.deepEqual(L.park(twoCopies, gap).map(d => d.y), [0, gap, 2 * gap]);
assert.deepEqual(L.unpark(L.park(twoCopies, gap), gap), twoCopies);

// applyArgs: a copy goes to its slot
assert.deepEqual(L.applyArgs(oneCopy, oneCopy, gap), [
  "--output", "eDP-1", "--on", "--mode", "1920x1200@120.002998Hz", "--pos", "0,0",
  "--scale", "1", "--transform", "normal",
  "--output", "DP-3", "--on", "--mode", "3840x2160@60Hz", "--pos", "0,8192",
  "--scale", "1.5", "--transform", "normal"]);
assert.equal(L.applyArgs(twoCopies, twoCopies, gap).filter(a => /^0,/.test(a)).join(" "), "0,0 0,8192 0,16384");

// valid: the rules for copies
assert.equal(L.valid(L.patch(oneCopy, "eDP-1", { copyOf: "DP-3" }), gap), false, "a copy of a copy");
assert.equal(L.valid(L.patch(two, "DP-3", { copyOf: "HDMI-A-1" }), gap), false, "a source that is not there");
const many = L.fromRandr([panelJson].concat([1, 2, 3, 4].map(i =>
  Object.assign({}, dellJson, { name: "DP-1" + i, serial: "S" + i, position: { x: 1920 + 2560 * (i - 1), y: 0 } }))));
assert.equal(L.valid(many, gap), true);
const four = many.map(d => d.name === "eDP-1" ? d : Object.assign({}, d, { copyOf: "eDP-1", x: 0, y: 0 }));
assert.equal(L.valid(four, gap), false, "four copies");
assert.equal(L.whyNot(four, gap), "At most three displays can duplicate");
// four displays in a column reach 8640: fine alone, too tall with a copy
const big = [mode(3840, 2160, 60, { current: true })];
const column = many.map((d, i) => Object.assign({}, d, i === 4
  ? { x: 3840, y: 0 } : { x: 0, y: i * 2160, scale: 1, modes: big, mode: 0 }));
assert.equal(L.valid(column, gap), true, "tall without a copy");
const tallCopy = L.patch(column, "DP-14", { copyOf: "eDP-1", x: 0, y: 0 });
assert.equal(L.whyNot(tallCopy, gap), "This layout is too tall to duplicate");
assert.equal(L.valid(tallCopy, gap), false, "tall with a copy");
assert.equal(L.stack(column, "DP-14", "eDP-1", gap), column, "a stack that would be too tall is refused");

// same: copyOf counts; a copy's scale and position do not
assert.equal(L.same(two, oneCopy), false);
assert.equal(L.same(oneCopy, L.patch(oneCopy, "DP-3", { scale: 2, x: 77 })), true);
assert.equal(L.notTaken(oneCopy, two).length > 0, true, "a copy that was not taken shows");

// settle and frame: a copy goes with its source and takes no room
s = L.settle(L.patch(L.stack(three, "DP-4", "DP-3", gap), "DP-3", { x: -5000, y: 0 }), "DP-3");
sound(s, "settle with a copy");
assert.deepEqual([at(s, "DP-4").x, at(s, "DP-4").y], [at(s, "DP-3").x, at(s, "DP-3").y]);
assert.deepEqual(L.frame(oneCopy, 616, 240, 28), L.frame(one, 616, 240, 28));

// stack
s = L.stack(three, "DP-4", "eDP-1", gap);
sound(s, "stack");
assert.deepEqual(names(s), ["eDP-1", "DP-3"]);
assert.equal(L.sourceOf(s, "DP-4"), "eDP-1");
assert.equal(L.stackLabel(s, "eDP-1"), "LQ134N1JW52 + DELL U2723QE");
// stack: the middle one leaves a gap that closes
s = L.stack(three, "DP-3", "eDP-1", gap);
sound(s, "stack the middle one");
assert.deepEqual(names(s), ["eDP-1", "DP-4"]);
// stack: on a copy lands on that copy's source
s = L.stack(L.stack(three, "DP-4", "eDP-1", gap), "DP-3", "DP-4", gap);
sound(s, "stack on a copy");
assert.deepEqual(copyNames(s), ["DP-3=eDP-1", "DP-4=eDP-1"]);
// stack: a source brings its copy
s = L.stack(L.stack(three, "DP-4", "DP-3", gap), "DP-3", "eDP-1", gap);
sound(s, "stack a stack");
assert.deepEqual(copyNames(s), ["DP-3=eDP-1", "DP-4=eDP-1"]);
// stack: on itself, on its own stack, on an off display, a fourth copy
assert.equal(L.stack(three, "DP-3", "DP-3", gap), three);
assert.equal(L.stack(oneCopy, "eDP-1", "DP-3", gap), oneCopy);
assert.equal(L.stack(withOff, "eDP-1", "HDMI-A-1", gap), withOff);
const threeCopies = ["DP-11", "DP-12", "DP-13"].reduce((l, n) => L.stack(l, n, "eDP-1", gap), many);
sound(threeCopies, "three copies");
assert.equal(L.stack(threeCopies, "DP-14", "eDP-1", gap), threeCopies, "a fourth copy is refused");

// separate
s = L.separate(twoCopies, "DP-3");
sound(s, "separate");
assert.deepEqual(copyNames(s), ["DP-4=eDP-1"]);
assert.deepEqual(names(s), ["eDP-1", "DP-3"]);
assert.equal(L.separate(two, "DP-3"), two, "not a copy");

// makeSource: roles swap, the rest stays
const pair = L.stack(three, "DP-3", "eDP-1", gap);
s = L.makeSource(pair, "DP-3");
sound(s, "makeSource");
assert.deepEqual(copyNames(s), ["eDP-1=DP-3"]);
assert.deepEqual([at(s, "DP-3").x, at(s, "DP-3").y, at(s, "DP-3").scale], [0, 0, 1.5]);
assert.deepEqual([at(s, "DP-4").x, at(s, "DP-4").y], [2560, 0], "the neighbour made room");
s = L.makeSource(twoCopies, "DP-4");
sound(s, "makeSource of three");
assert.deepEqual(copyNames(s), ["eDP-1=DP-4", "DP-3=DP-4"]);

// disable: a source hands over to its first copy (FR-026)
s = L.disable(twoCopies, "eDP-1");
sound(s, "disable a source");
assert.equal(at(s, "eDP-1").enabled, false);
assert.deepEqual(names(s), ["DP-3"]);
assert.deepEqual(copyNames(s), ["DP-4=DP-3"]);
// disable: a copy leaves its stack; a plain display is just off
s = L.disable(twoCopies, "DP-4");
sound(s, "disable a copy");
assert.deepEqual([at(s, "DP-4").enabled, at(s, "DP-4").copyOf], [false, ""]);
s = L.disable(three, "DP-3");
sound(s, "disable");
assert.deepEqual(names(s), ["eDP-1", "DP-4"]);

// broken and repair (research R7)
assert.equal(L.broken(twoCopies), false);
assert.equal(L.repair(twoCopies), twoCopies);
// the source was unplugged: its two copies are parked under nothing
read = L.unpark(L.fromRandr([parkedJson(dellJson, 0, gap), parkedJson(thirdJson, 0, 2 * gap)]), gap);
assert.equal(L.broken(read), true);
s = L.repair(read);
sound(s, "repair after the source went");
assert.deepEqual(names(s), ["DP-3"]);
assert.deepEqual(copyNames(s), ["DP-4=DP-3"]);
assert.equal(L.broken(s), false);
// the source was turned off (a closed lid): the copy takes its place
read = L.unpark(L.fromRandr([Object.assign({}, panelJson, { enabled: false }),
  parkedJson(dellJson, 0, gap), parkedJson(thirdJson, 1920, 0)]), gap);
s = L.repair(read);
sound(s, "repair after the source turned off");
assert.deepEqual(names(s), ["DP-3", "DP-4"]);
// an orphan where another display now is gets moved beside it
read = L.unpark(L.fromRandr([panelJson, parkedJson(dellJson, 100, gap + 100)]), gap);
s = L.repair(read);
sound(s, "repair an orphan on top of a display");
assert.deepEqual(names(s), ["eDP-1", "DP-3"]);

// dropTarget: the inner half of another placed display
assert.equal(L.dropTarget(three, "DP-4", 960, 600), "eDP-1");
assert.equal(L.dropTarget(three, "DP-4", 100, 600), "", "outer quarter");
assert.equal(L.dropTarget(three, "DP-4", 5000, 700), "", "itself");
assert.equal(L.dropTarget(pair, "DP-3", 960, 600), "", "its own stack");
assert.equal(L.dropTarget(pair, "DP-4", 960, 600), "eDP-1");

// choices
const lone = { panel: "eDP-1", lidClosed: false, selected: "eDP-1" };
const desk = { panel: "LVDS-1", lidClosed: false, selected: "DP-4" };
assert.deepEqual(L.choices(one, "eDP-1"), []);
assert.deepEqual(L.choices(two, "eDP-1"), ["extend", "duplicate", "panel", "external"]);
assert.deepEqual(L.choices(two, "LVDS-1"), ["extend", "duplicate"]);

// arrangement
assert.equal(L.arrangement(one, lone), "");
assert.equal(L.arrangement(three, lone), "extend");
assert.equal(L.arrangement(twoCopies, lone), "duplicate");
assert.equal(L.arrangement(pair, lone), "", "a pair and a third");
assert.equal(L.arrangement(L.disable(L.disable(three, "DP-3"), "DP-4"), lone), "panel");
assert.equal(L.arrangement(L.disable(three, "eDP-1"), lone), "external");
assert.equal(L.arrangement(L.disable(three, "DP-3"), lone), "");

// arrange: every choice, then Extend, leaves all on and none a copy (SC-007)
for (const choice of ["duplicate", "panel", "external"]) {
  const made = L.arrange(three, choice, lone, gap);
  sound(made, choice);
  assert.equal(L.arrangement(made, lone), choice);
  const back = L.arrange(made, "extend", lone, gap);
  sound(back, choice + " then extend");
  assert.equal(L.arrangement(back, lone), "extend");
  assert.equal(back.every(d => d.enabled && !d.copyOf), true);
}
// arrange: what already fits is left alone (FR-011)
assert.equal(L.arrange(three, "extend", lone, gap), three);
assert.equal(L.arrange(twoCopies, "duplicate", lone, gap), twoCopies);
s = L.arrange(pair, "duplicate", lone, gap);
assert.deepEqual(at(s, "DP-3"), at(pair, "DP-3"), "a copy that already fits keeps every value");
// arrange duplicate: the panel is the source; without one, the selected display
assert.deepEqual(copyNames(L.arrange(three, "duplicate", lone, gap)), ["DP-3=eDP-1", "DP-4=eDP-1"]);
assert.deepEqual(copyNames(L.arrange(three, "duplicate", desk, gap)), ["eDP-1=DP-4", "DP-3=DP-4"]);
// arrange duplicate from a hand-made stack whose source is another display
s = L.arrange(L.stack(three, "eDP-1", "DP-3", gap), "duplicate", lone, gap);
sound(s, "duplicate from a stack");
assert.deepEqual(copyNames(s), ["DP-3=eDP-1", "DP-4=eDP-1"]);
// arrange: Only external from a duplicated layout has no copy
s = L.arrange(twoCopies, "external", lone, gap);
sound(s, "external from duplicate");
assert.deepEqual(copyNames(s), []);
assert.deepEqual(names(s), ["DP-3", "DP-4"]);
// arrange: with the lid closed the panel stays off and is not the source
const lidDown = { panel: "eDP-1", lidClosed: true, selected: "DP-4" };
const docked = L.disable(three, "eDP-1");
assert.equal(L.arrangement(docked, lidDown), "extend");
s = L.arrange(docked, "duplicate", lidDown, gap);
sound(s, "duplicate with the lid closed");
assert.equal(at(s, "eDP-1").enabled, false);
assert.deepEqual(copyNames(s), ["DP-3=DP-4"]);
assert.equal(L.arrangement(s, lidDown), "duplicate");
assert.equal(L.arrange(s, "extend", lidDown, gap).filter(d => d.enabled).length, 2);
assert.equal(L.arrange(docked, "panel", lidDown, gap), docked, "Only panel under a closed lid");
// arrange: five displays cannot all duplicate
assert.equal(L.arrange(many, "duplicate", lone, gap), many);
// arrange: a choice the switch does not offer
assert.equal(L.arrange(two, "panel", desk, gap), two);

// random stack edits always give a sound layout (FR-019)
layout = many;
for (let i = 0; i < 400; i++) {
  const pick = () => layout[Math.floor(random() * layout.length)].name;
  const op = Math.floor(random() * 6);
  if (op === 0) layout = L.stack(layout, pick(), pick(), gap);
  else if (op === 1) layout = L.separate(layout, pick());
  else if (op === 2) layout = L.makeSource(layout, pick());
  else if (op === 3 && layout.filter(L.placed).length > 1) layout = L.disable(layout, pick());
  else if (op === 4) layout = L.arrange(layout, "extend", lone, gap);
  else {
    const name = pick();
    if (L.placed(at(layout, name)))
      layout = L.settle(L.patch(layout, name, { x: Math.round(random() * 9000), y: Math.round(random() * 3000) }), name);
  }
  sound(layout, "random stack edit " + i);
  assert.deepEqual(L.unpark(L.park(layout, gap), gap), layout, "park round trip " + i);
}

console.log("displayLayout: all tests passed");
