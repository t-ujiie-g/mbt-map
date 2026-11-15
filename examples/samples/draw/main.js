import { Map } from "mbt-map";
import { createDraw } from "mbt-map/draw";
import * as geodesic from "mbt-map/geodesic";

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      pale: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tileSize: 256,
        minzoom: 2,
        maxzoom: 18,
        attribution: "国土地理院",
      },
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: [139.7671, 35.6812],
  zoom: 15,
});
await map.once("load");

const draw = createDraw(map, { geodesic, snapping: true });
const modes = document.querySelectorAll("[data-mode]");
const $ = (id) => document.getElementById(id);

function render(s) {
  for (const b of modes) b.setAttribute("aria-pressed", String(b.dataset.mode === s.mode));
  $("undo").disabled = !s.canUndo;
  $("redo").disabled = !s.canRedo;
  $("delete").disabled = s.selection.length === 0;
  $("geojson").textContent = JSON.stringify({ type: "FeatureCollection", features: s.features }, null, 2);
}
render(draw.state);
draw.subscribe(render);

for (const b of modes) b.onclick = () => draw.setMode(draw.state.mode === b.dataset.mode ? null : b.dataset.mode);
$("undo").onclick = () => draw.undo();
$("redo").onclick = () => draw.redo();
$("delete").onclick = () => draw.deleteSelected();
$("clear").onclick = () => draw.clear();

document.addEventListener("keydown", (e) => {
  if (e.isComposing || e.keyCode === 229) return;
  if (e.key === "Enter") draw.finish();
  else if (e.key === "Escape") draw.cancel();
  else if (e.key === "Delete" || e.key === "Backspace") draw.deleteSelected();
  else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") e.shiftKey ? draw.redo() : draw.undo();
});
