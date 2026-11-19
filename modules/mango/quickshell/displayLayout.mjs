// Geometry of the displays card (Displays.qml, DisplayCanvas.qml;
// specs/018-display-layout-card): what wlr-randr reports as a layout, the
// rules a layout must keep, snapping and settling, and the wlr-randr
// arguments that apply one. Since specs/020-duplicate-display also which
// display copies which: a copy is parked far below its source, the stack
// rules, and the arrangements of the card's switch. Plain ECMAScript with no QML types, so
// displayLayout.test.mjs runs this same file at build time.

// The scales the card offers (FR-012).
export const scales = [1, 1.25, 1.5, 2];

function turned(transform) {
  return /(90|270)$/.test(transform);
}

// `wlr-randr --json` to a layout (data-model.md). A display that is off
// reports no state: it gets its preferred mode, scale 1 and no rotation.
export function fromRandr(json) {
  return json.map(o => {
    const modes = (o.modes ?? []).map(m => ({
      width: m.width, height: m.height, refresh: m.refresh, preferred: !!m.preferred,
    }));
    const on = !!o.enabled;
    let mode = on ? (o.modes ?? []).findIndex(m => m.current) : -1;
    if (mode < 0) mode = modes.findIndex(m => m.preferred);
    if (mode < 0) mode = 0;
    return {
      name: o.name,
      make: o.make ?? "",
      model: o.model ?? "",
      serial: o.serial ?? "",
      modes: modes,
      enabled: on,
      mode: mode,
      x: on ? o.position?.x ?? 0 : 0,
      y: on ? o.position?.y ?? 0 : 0,
      scale: on ? o.scale ?? 1 : 1,
      transform: on ? o.transform ?? "normal" : "normal",
      adaptiveSync: on && !!o.adaptive_sync,
      // The display this one copies, "" for none; set by unpark, which
      // also marks a parked display that found no source as an orphan.
      copyOf: "",
      orphan: false,
    };
  });
}

// In the arrangement: on, and not a copy of another display.
export function placed(d) {
  return d.enabled && !d.copyOf;
}

// A copy's source, or the display itself.
export function sourceOf(layout, name) {
  const d = layout.find(o => o.name === name);
  return d && d.enabled && d.copyOf ? d.copyOf : name;
}

export function copiesOf(layout, name) {
  return layout.filter(d => d.enabled && d.copyOf === name);
}

// "Panel + Projector" for the stack that `name` is the source of.
export function stackLabel(layout, name) {
  const d = layout.find(o => o.name === name);
  return (d ? [d] : []).concat(copiesOf(layout, name)).map(label).join(" + ");
}

// What wlr-randr holds for a copy is its source's x and the source's y
// plus one gap per slot (research R3 of specs/020): the pointer cannot
// cross the gap, and the position is the only record of the copy. This
// reads it back: a copy gets its source's position. A parked display with
// no display above it is an orphan, left where its source was.
export function unpark(layout, gap) {
  const parked = d => d.enabled && d.y >= gap;
  return layout.map(d => {
    if (!parked(d)) return d;
    const y = d.y % gap;
    const source = layout.find(o =>
      o.enabled && !parked(o) && o.name !== d.name && o.x === d.x && o.y === y);
    return source
      ? Object.assign({}, d, { copyOf: source.name, x: source.x, y: source.y })
      : Object.assign({}, d, { orphan: true, y: y });
  });
}

// The reverse of unpark: copies in the order read get slot 1, 2, 3.
export function park(layout, gap) {
  let slot = 0;
  return layout.map(d => {
    if (!d.enabled || !d.copyOf) return d;
    const source = layout.find(o => o.name === d.copyOf);
    if (!source) return d;
    slot += 1;
    return Object.assign({}, d, { x: source.x, y: source.y + slot * gap });
  });
}

// Every copy takes its source's position.
export function follow(layout) {
  return layout.map(d => {
    if (!d.enabled || !d.copyOf) return d;
    const source = layout.find(o => o.name === d.copyOf);
    return source && (source.x !== d.x || source.y !== d.y)
      ? Object.assign({}, d, { x: source.x, y: source.y }) : d;
  });
}

export function label(d) {
  return d.model || d.name;
}

// Size in layout pixels. wlroots truncates (research R5).
export function logicalSize(d) {
  const m = d.modes[d.mode] ?? { width: 0, height: 0 };
  const w = Math.floor(m.width / d.scale);
  const h = Math.floor(m.height / d.scale);
  return turned(d.transform) ? { w: h, h: w } : { w: w, h: h };
}

function rect(d) {
  const s = logicalSize(d);
  return { name: d.name, x: d.x, y: d.y, w: s.w, h: s.h };
}

// Distinct resolutions, largest first.
export function resolutions(d) {
  const seen = new Set();
  const out = [];
  for (const m of d.modes) {
    const key = m.width + "x" + m.height;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ w: m.width, h: m.height });
  }
  return out.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w);
}

// Mode indexes of one resolution, highest refresh first.
export function rates(d, w, h) {
  return d.modes.map((m, i) => i)
    .filter(i => d.modes[i].width === w && d.modes[i].height === h)
    .sort((a, b) => d.modes[b].refresh - d.modes[a].refresh);
}

// A mode as wlr-randr's --mode takes it.
export function modeArg(m) {
  return m.width + "x" + m.height + "@" + m.refresh + "Hz";
}

export function rotation(transform) {
  const m = /(90|180|270)$/.exec(transform);
  return m ? Number(m[1]) : 0;
}

// Changes the angle and keeps a flip (research R9).
export function withRotation(transform, degrees) {
  const flipped = transform.startsWith("flipped");
  if (degrees === 0) return flipped ? "flipped" : "normal";
  return flipped ? "flipped-" + degrees : String(degrees);
}

export function patch(layout, name, values) {
  return layout.map(d => d.name === name ? Object.assign({}, d, values) : d);
}

// Shifts the placed displays so their top-left corner is 0,0 (FR-019);
// copies go with their sources.
export function normalise(layout) {
  const on = layout.filter(placed);
  if (on.length === 0) return layout;
  const minX = Math.min(...on.map(d => d.x));
  const minY = Math.min(...on.map(d => d.y));
  if (minX === 0 && minY === 0) return follow(layout);
  return follow(layout.map(d => placed(d) ? Object.assign({}, d, { x: d.x - minX, y: d.y - minY }) : d));
}

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

// Length of the edge two rectangles share; 0 when they do not touch.
function shared(a, b) {
  if (a.x + a.w === b.x || b.x + b.w === a.x)
    return Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  if (a.y + a.h === b.y || b.y + b.h === a.y)
    return Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x));
  return 0;
}

// Names of the rectangles reachable from `start` through shared edges.
function component(rects, start) {
  const found = new Set([start]);
  const queue = [start];
  while (queue.length > 0) {
    const current = queue.pop();
    const a = rects.find(r => r.name === current);
    for (const b of rects) {
      if (found.has(b.name) || shared(a, b) <= 0) continue;
      found.add(b.name);
      queue.push(b.name);
    }
  }
  return found;
}

// The most displays that can be copies at once: three slots of the gap
// plus a display stay inside X11's 32767 (research R3 of specs/020).
export const maxCopies = 3;

// Why the copies of `layout` cannot be parked, "" when they can.
export function whyNot(layout, gap) {
  const copies = layout.filter(d => d.enabled && d.copyOf);
  if (copies.length === 0) return "";
  if (copies.length > maxCopies) return "At most three displays can duplicate";
  const rects = layout.filter(placed).map(rect);
  const top = Math.min(...rects.map(r => r.y));
  const bottom = Math.max(...rects.map(r => r.y + r.h));
  if (bottom - top >= gap || copies.some(d => logicalSize(d).h >= gap))
    return "This layout is too tall to duplicate";
  return "";
}

// The rules of a layout the card may apply (data-model.md, "Layout", of
// specs/018 for the placed displays and of specs/020 for the copies).
export function valid(layout, gap) {
  const rects = layout.filter(placed).map(rect);
  if (rects.length === 0) return false;
  for (let i = 0; i < rects.length; i++)
    for (let j = i + 1; j < rects.length; j++)
      if (overlaps(rects[i], rects[j])) return false;
  if (component(rects, rects[0].name).size !== rects.length) return false;
  if (Math.min(...rects.map(r => r.x)) !== 0 || Math.min(...rects.map(r => r.y)) !== 0) return false;
  if (layout.some(d => d.enabled && d.orphan)) return false;
  for (const d of layout) {
    if (!d.enabled || !d.copyOf) continue;
    const source = layout.find(o => o.name === d.copyOf);
    if (!source || !placed(source)) return false;
  }
  return whyNot(layout, gap) === "";
}

// A copy's position and scale are its source's business.
function key(d) {
  if (!d.enabled) return [d.name];
  return d.copyOf
    ? [d.name, d.mode, d.transform, d.adaptiveSync, d.copyOf]
    : [d.name, d.mode, d.x, d.y, d.scale, d.transform, d.adaptiveSync, ""];
}

// Equal as far as applying goes; an off display's other values do not count.
export function same(a, b) {
  return JSON.stringify(a.map(key)) === JSON.stringify(b.map(key));
}

export function sameNames(a, b) {
  return a.map(d => d.name).join("\n") === b.map(d => d.name).join("\n");
}

// The displays of `real` whose state is not what `asked` holds for them.
export function notTaken(asked, real) {
  return real.filter(d => {
    const a = asked.find(o => o.name === d.name);
    return a && JSON.stringify(key(a)) !== JSON.stringify(key(d));
  });
}

// One line for the card about `notTaken`, "" when everything was taken.
export function notTakenLine(asked, real) {
  const list = notTaken(asked, real);
  if (list.length === 0) return "";
  if (list.length > 1) return "Some displays did not take the change";
  const d = list[0];
  const a = asked.find(o => o.name === d.name);
  if (!a.enabled || !d.enabled || a.mode === d.mode) return label(d) + " did not take the change";
  const hz = Math.round(a.modes[a.mode].refresh * 100) / 100;
  return label(d) + " cannot run at " + hz + " Hz here";
}

// The wlr-randr arguments for `layout` (contracts/displays.md, "Applying").
// Adaptive sync is named only where it differs from `applied`, since a
// display that cannot do it refuses the whole change (research R8). A copy
// goes to its parked position (specs/020, contracts/displays.md).
export function applyArgs(layout, applied, gap) {
  const args = [];
  for (const d of park(layout, gap)) {
    args.push("--output", d.name);
    if (!d.enabled) {
      args.push("--off");
      continue;
    }
    const m = d.modes[d.mode];
    args.push("--on", "--mode", modeArg(m),
      "--pos", d.x + "," + d.y, "--scale", String(d.scale), "--transform", d.transform);
    const was = applied.find(a => a.name === d.name);
    if (!was || was.adaptiveSync !== d.adaptiveSync)
      args.push("--adaptive-sync", d.adaptiveSync ? "enabled" : "disabled");
  }
  return args;
}

// How the canvas draws the placed displays in a width by height area:
// pixels per layout pixel, and the offset that centres them.
export function frame(layout, width, height, margin) {
  const rects = layout.filter(placed).map(rect);
  if (rects.length === 0 || width <= 2 * margin || height <= 2 * margin)
    return { k: 0.1, ox: 0, oy: 0 };
  const x0 = Math.min(...rects.map(r => r.x));
  const y0 = Math.min(...rects.map(r => r.y));
  const w = Math.max(...rects.map(r => r.x + r.w)) - x0;
  const h = Math.max(...rects.map(r => r.y + r.h)) - y0;
  if (w <= 0 || h <= 0) return { k: 0.1, ox: 0, oy: 0 };
  const k = Math.min((width - 2 * margin) / w, (height - 2 * margin) / h);
  return { k: k, ox: (width - w * k) / 2 - x0 * k, oy: (height - h * k) / 2 - y0 * k };
}

// Where a dragged display lands at x,y: its edges snap to the edges of the
// other enabled displays within `threshold` layout pixels (FR-008).
export function snap(layout, name, x, y, threshold) {
  const d = layout.find(o => o.name === name);
  const s = logicalSize(d);
  let bestX = x, bestY = y, dx = threshold, dy = threshold;
  for (const o of layout) {
    if (!placed(o) || o.name === name) continue;
    const r = rect(o);
    for (const c of [r.x - s.w, r.x + r.w, r.x, r.x + r.w - s.w]) {
      if (Math.abs(x - c) < dx) { dx = Math.abs(x - c); bestX = c; }
    }
    for (const c of [r.y - s.h, r.y + r.h, r.y, r.y + r.h - s.h]) {
      if (Math.abs(y - c) < dy) { dy = Math.abs(y - c); bestY = c; }
    }
  }
  return { x: Math.round(bestX), y: Math.round(bestY) };
}

// Moves `name` to the nearest place where it touches one of `targets`
// along an edge and overlaps none of them.
function place(layout, name, targets) {
  const d = layout.find(o => o.name === name);
  const s = logicalSize(d);
  const others = layout.filter(o => placed(o) && o.name !== name && targets.has(o.name)).map(rect);
  if (others.length === 0) return patch(layout, name, { x: 0, y: 0 });
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const candidates = [];
  for (const o of others) {
    // At least this much shared edge, so the pointer has room to cross.
    const my = Math.min(100, s.h, o.h);
    const mx = Math.min(100, s.w, o.w);
    const yLo = o.y - s.h + my, yHi = o.y + o.h - my;
    const xLo = o.x - s.w + mx, xHi = o.x + o.w - mx;
    const ys = [clamp(d.y, yLo, yHi)];
    const xs = [clamp(d.x, xLo, xHi)];
    for (const p of others) {
      for (const y of [p.y - s.h, p.y + p.h, p.y, p.y + p.h - s.h])
        if (y >= yLo && y <= yHi) ys.push(y);
      for (const x of [p.x - s.w, p.x + p.w, p.x, p.x + p.w - s.w])
        if (x >= xLo && x <= xHi) xs.push(x);
    }
    for (const y of ys) candidates.push({ x: o.x - s.w, y: y }, { x: o.x + o.w, y: y });
    for (const x of xs) candidates.push({ x: x, y: o.y - s.h }, { x: x, y: o.y + o.h });
  }
  // Always free: right of the display that reaches furthest right.
  const last = others.reduce((a, b) => b.x + b.w > a.x + a.w ? b : a);
  candidates.push({ x: last.x + last.w, y: last.y });
  let best = null, bestDistance = Infinity;
  for (const c of candidates) {
    const r = { x: c.x, y: c.y, w: s.w, h: s.h };
    if (others.some(o => overlaps(r, o))) continue;
    const distance = (c.x - d.x) ** 2 + (c.y - d.y) ** 2;
    if (distance < bestDistance) { best = c; bestDistance = distance; }
  }
  return patch(layout, name, { x: Math.round(best.x), y: Math.round(best.y) });
}

// After `name` moved or changed: a layout with no overlap where every
// enabled display touches another, normalised (FR-009, research R5).
// Displays that lost their neighbour are moved back to the rest.
export function settle(layout, name) {
  let out = layout;
  const placedNames = () => new Set(out.filter(placed).map(o => o.name));
  const d = out.find(o => o.name === name);
  if (d && placed(d)) out = place(out, name, placedNames());
  for (let i = 0; i < layout.length; i++) {
    const rects = out.filter(placed).map(rect);
    if (rects.length < 2) break;
    const anchor = d && placed(d) ? name : rects[0].name;
    const joined = component(rects, anchor);
    const stray = rects.find(r => !joined.has(r.name));
    if (!stray) break;
    out = place(out, stray.name, joined);
  }
  const on = out.filter(placed);
  if (on.length === 1) out = patch(out, on[0].name, { x: 0, y: 0 });
  return normalise(out);
}
// Stacks (specs/020-duplicate-display, data-model.md "Operations"). Each
// returns a layout that keeps the rules, or the one it was given when the
// change is not possible.

// Right of every placed display, where settle then finds the nearest edge.
function rightOf(layout) {
  let right = 0;
  for (const d of layout.filter(placed)) right = Math.max(right, d.x + logicalSize(d).w);
  return right;
}

// `name` and its copies become copies of `target`'s source.
export function stack(layout, name, target, gap) {
  const source = sourceOf(layout, target);
  const d = layout.find(o => o.name === name);
  const s = layout.find(o => o.name === source);
  if (!d || !s || !d.enabled || !placed(s)) return layout;
  if (sourceOf(layout, name) === source) return layout;
  const moving = new Set([name].concat(copiesOf(layout, name).map(c => c.name)));
  const out = settle(layout.map(o => moving.has(o.name) ? Object.assign({}, o, { copyOf: source }) : o), source);
  return valid(out, gap) ? out : layout;
}

// A copy becomes a display of its own again, beside the others (FR-007).
export function separate(layout, name) {
  const d = layout.find(o => o.name === name);
  if (!d || !d.enabled || !d.copyOf) return layout;
  return settle(patch(layout, name, { copyOf: "", orphan: false, x: rightOf(layout), y: 0 }), name);
}

// A copy and its source swap roles; the stack stays where it is (FR-018).
export function makeSource(layout, name) {
  const d = layout.find(o => o.name === name);
  if (!d || !d.enabled || !d.copyOf) return layout;
  const old = layout.find(o => o.name === d.copyOf);
  if (!old) return layout;
  const out = layout.map(o => {
    if (o.name === name) return Object.assign({}, o, { copyOf: "", x: old.x, y: old.y });
    if (o.name === old.name || (o.enabled && o.copyOf === old.name)) return Object.assign({}, o, { copyOf: name });
    return o;
  });
  // The new source may have another size: the neighbours make room.
  let settled = out;
  for (const o of out) if (placed(o) && o.name !== name) settled = settle(settled, o.name);
  return settled;
}

// Turns a display off. A source hands the desktop to its first copy
// (FR-026); a copy just leaves its stack.
export function disable(layout, name) {
  const d = layout.find(o => o.name === name);
  if (!d || !d.enabled) return layout;
  const copies = copiesOf(layout, name);
  if (copies.length > 0) {
    const heir = copies[0].name;
    return settle(patch(makeSource(layout, heir), name, { enabled: false, copyOf: "" }), heir);
  }
  return settle(patch(layout, name, { enabled: false, copyOf: "", orphan: false }), name);
}

// A read layout that needs repair: a parked display without its source.
export function broken(layout) {
  return layout.some(d => {
    if (!d.enabled) return false;
    if (d.orphan) return true;
    if (!d.copyOf) return false;
    const source = layout.find(o => o.name === d.copyOf);
    return !source || !placed(source);
  });
}

// Repairs it (research R7): of the copies a lost source left behind, the
// first takes its place and the rest copy that one.
export function repair(layout) {
  if (!broken(layout)) return layout;
  let out = layout.map(d => {
    if (!d.enabled || !d.copyOf) return d;
    const source = layout.find(o => o.name === d.copyOf);
    return source && placed(source) ? d : Object.assign({}, d, { copyOf: "", orphan: true });
  });
  const heirs = [];
  out = out.map(d => {
    if (!d.enabled || !d.orphan) return d;
    const heir = heirs.find(h => h.x === d.x && h.y === d.y);
    if (heir) return Object.assign({}, d, { orphan: false, copyOf: heir.name });
    heirs.push({ name: d.name, x: d.x, y: d.y });
    return Object.assign({}, d, { orphan: false, copyOf: "" });
  });
  for (const heir of heirs) out = settle(out, heir.name);
  return out;
}

// The placed display a tile dragged to x,y would be dropped on: the
// pointer is in the inner half of its rectangle (FR-015). "" for none.
export function dropTarget(layout, name, x, y) {
  const own = sourceOf(layout, name);
  for (const o of layout) {
    if (!placed(o) || o.name === own) continue;
    const r = rect(o);
    if (x >= r.x + r.w / 4 && x <= r.x + r.w * 3 / 4 && y >= r.y + r.h / 4 && y <= r.y + r.h * 3 / 4)
      return o.name;
  }
  return "";
}

// Arrangements: the choices of the card's switch (data-model.md,
// "Arrangement"). `ctx` is { panel, lidClosed, selected }.

// The displays a choice speaks of: not a panel that is off under a closed lid.
function counted(layout, ctx) {
  return layout.filter(d => !(ctx.lidClosed && d.name === ctx.panel && !d.enabled));
}

// What the switch offers for the connected displays.
export function choices(layout, panel) {
  if (layout.length < 2) return [];
  return layout.some(d => d.name === panel)
    ? ["extend", "duplicate", "panel", "external"] : ["extend", "duplicate"];
}

// The choice that describes `layout`, "" when none does.
export function arrangement(layout, ctx) {
  if (layout.length < 2) return "";
  const all = counted(layout, ctx);
  const copies = all.filter(d => d.enabled && d.copyOf);
  if (all.every(d => d.enabled)) {
    if (copies.length === 0) return "extend";
    if (copies.length === all.length - 1 && copies.every(d => d.copyOf === copies[0].copyOf))
      return "duplicate";
    return "";
  }
  const panel = layout.find(d => d.name === ctx.panel);
  if (!panel) return "";
  const others = layout.filter(d => d.name !== ctx.panel);
  if (panel.enabled && others.every(d => !d.enabled)) return "panel";
  if (!panel.enabled && others.every(d => placed(d))) return "external";
  return "";
}

// `name` on and placed, beside the others.
function extended(layout, name) {
  const d = layout.find(o => o.name === name);
  if (placed(d)) return layout;
  return settle(patch(layout, name, { enabled: true, copyOf: "", orphan: false, x: rightOf(layout), y: 0 }), name);
}

// The layout a choice describes. Displays that already fit keep every
// value (FR-011); a layout that already is the choice is returned as is.
export function arrange(layout, choice, ctx, gap) {
  if (!choices(layout, ctx.panel).includes(choice) || arrangement(layout, ctx) === choice) return layout;
  const names = counted(layout, ctx).map(d => d.name);
  let out = layout;
  if (choice === "extend") {
    for (const name of names) out = extended(out, name);
  } else if (choice === "duplicate") {
    const has = name => names.includes(name);
    const first = layout.find(d => d.enabled && has(d.name));
    const source = has(ctx.panel) && !ctx.lidClosed ? ctx.panel
      : has(ctx.selected) ? ctx.selected : first ? first.name : "";
    if (source === "") return layout;
    const s = out.find(d => d.name === source);
    out = s.enabled && s.copyOf ? makeSource(out, source) : extended(out, source);
    out = out.map(d => has(d.name) && d.name !== source
      ? Object.assign({}, d, { enabled: true, copyOf: source, orphan: false }) : d);
    out = settle(out, source);
  } else if (choice === "panel") {
    if (ctx.lidClosed) return layout;
    out = extended(out, ctx.panel);
    out = out.map(d => d.name === ctx.panel ? d : Object.assign({}, d, { enabled: false, copyOf: "", orphan: false }));
    out = settle(out, ctx.panel);
  } else {
    for (const name of names) if (name !== ctx.panel) out = extended(out, name);
    out = settle(patch(out, ctx.panel, { enabled: false, copyOf: "", orphan: false }), ctx.panel);
  }
  return valid(out, gap) ? out : layout;
}
