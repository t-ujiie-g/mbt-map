// Drawing with mbt-map/draw (clicks as terra-draw's; circles on the ellipsoid
// through mbt-map/geodesic). Drawing and measuring exclude each other, and keys
// go to the drawing unless they belong to an IME composition or a text field.
import { mergeFeatures, splitFeatures } from "mbt-map/analysis";
import { createDraw } from "mbt-map/draw";
import * as geodesic from "mbt-map/geodesic";

export const DRAW_MODES = [["select", "Select"], ["split", "Split"], ["point", "Point"], ["linestring", "Line"], ["polygon", "Polygon"], ["rectangle", "Rectangle"], ["circle", "Circle"], ["freehand", "Freehand"]];

/** The properties the panel edits on the selected shape, as [key, label]. */
export const FIELDS = [["name", "Name"], ["note", "Note"]];

/** The drawing over `map`; choosing a mode clears `measurement`'s. */
export function createShowcaseDraw(map, measurement) {
  const draw = createDraw(map, { geodesic, snapping: true, geometry: { split: splitFeatures, merge: mergeFeatures } });
  const setMode = draw.setMode.bind(draw);
  draw.setMode = (mode) => {
    if (mode) measurement.clear();
    setMode(mode);
  };
  window.__draw = draw;
  return draw;
}

/** Enter finishes, Escape cancels (or deselects), Delete removes the selected shape, ⌘Z / Ctrl+Z undoes and with Shift redoes. */
export function onDrawKey(draw, e) {
  if (e.isComposing || e.keyCode === 229 || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target?.tagName ?? "")) return;
  if (e.key === "Enter" && draw.state.mode) draw.finish();
  else if (e.key === "Escape" && draw.state.mode === "select") draw.select(null);
  else if (e.key === "Escape" && draw.state.mode) draw.cancel();
  else if ((e.key === "Delete" || e.key === "Backspace") && draw.state.selected) draw.deleteSelected();
  else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    if (e.shiftKey) draw.redo();
    else draw.undo();
  }
}

/** The operations as [label, action, enabled]. */
export function drawActions(draw, s) {
  return [
    ["Undo", () => draw.undo(), s.canUndo],
    ["Redo", () => draw.redo(), s.canRedo],
    ["Finish", () => draw.finish(), s.vertices.length > 0],
    ["Cancel", () => draw.setMode(null), Boolean(s.mode)],
    ["Merge", () => void draw.merge(), s.selection.length > 1],
    ["Delete selected", () => draw.deleteSelected(), s.selection.length > 0],
    ["Clear all", () => draw.clear(), s.features.length > 0],
    ["Save as GeoJSON", () => saveGeoJSON(s.features), s.features.length > 0],
  ];
}

/** What the readout says: how many of each shape, and what the clicks do now. */
export function drawnText(s) {
  const counts = DRAW_MODES.map(([m, label]) => [label, s.features.filter((f) => f.properties.mode === m).length]).filter(([, n]) => n > 0);
  const hint = {
    select: s.selection.length > 1 ? "Shift+click to add shapes, Merge to join them" : s.selected ? "Drag vertices or midpoints, drag inside to move, right-click a vertex to delete it. Shift+click to add shapes" : "Click a shape to select it",
    split: `Draw a cutting line and click its last vertex again to cut (splits ${s.selection.length ? "the selected shapes" : "the shapes it crosses"})`,
    point: "Click to place a point",
    linestring: "Click to add vertices, click the last one again to finish",
    polygon: "Click to add vertices, click the first one to close",
    rectangle: "Click two corners",
    circle: "Click the center, then the radius",
    freehand: "Click to start, move, click to close",
  }[s.mode] ?? "Choose a shape";
  return { counts: counts.map(([l, n]) => `${l} ${n}`).join(", ") || "No shapes yet", hint };
}

function saveGeoJSON(features) {
  const blob = new Blob([JSON.stringify({ type: "FeatureCollection", features }, null, 2)], { type: "application/geo+json" });
  const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "drawing.geojson" });
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/** The selected shape's value of `key` as text. */
export function fieldValue(s, key) {
  const f = s.features.find((x) => x.id === s.selected);
  return f ? String(f.properties[key] ?? "") : "";
}

/**
 * The tool in the panel for the plain-DOM examples: modes in `#draw-modes`, operations in `#draw-actions`,
 * the readout in `#drawn`, the selected shape's fields in `#draw-fields`.
 */
export function mountDraw(map, measurement) {
  const draw = createShowcaseDraw(map, measurement);
  const modes = document.getElementById("draw-modes");
  const actions = document.getElementById("draw-actions");
  const readout = document.getElementById("drawn");
  const fields = document.getElementById("draw-fields");
  const inputs = FIELDS.map(([key, label]) => {
    const input = Object.assign(document.createElement("input"), { name: key });
    // Set on change (blur or Enter), so that each edit is one step to undo.
    input.addEventListener("change", () => draw.state.selected && draw.setProperties(draw.state.selected, { [key]: input.value || null }));
    const row = document.createElement("label");
    row.append(label, input);
    fields.append(row);
    return [key, input];
  });
  const button = (label, f, enabled = true) => {
    const b = Object.assign(document.createElement("button"), { textContent: label, disabled: !enabled });
    b.addEventListener("click", f);
    return b;
  };
  const show = (s) => {
    modes.replaceChildren(
      ...DRAW_MODES.map(([m, label]) => {
        const b = button(label, () => draw.setMode(s.mode === m ? null : m));
        b.setAttribute("aria-pressed", String(s.mode === m));
        return b;
      }),
    );
    actions.replaceChildren(...drawActions(draw, s).map(([label, f, enabled]) => button(label, f, enabled)));
    const t = drawnText(s);
    readout.textContent = `${t.counts}. ${t.hint}`;
    fields.hidden = s.selection.length !== 1;
    for (const [key, input] of inputs) if (document.activeElement !== input) input.value = fieldValue(s, key);
  };
  draw.subscribe(show);
  show(draw.state);
  document.addEventListener("keydown", (e) => onDrawKey(draw, e));
  return draw;
}
