import { Map } from "mbt-map";
import { measure } from "mbt-map/geodesic";
import { createMeasurement, formatArea, formatLength } from "mbt-map/ui";

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      pale: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tileSize: 256,
        maxzoom: 18,
        attribution: "国土地理院",
      },
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: [139.7671, 35.6812],
  zoom: 13,
});
await map.once("load");

const measurement = createMeasurement(map, { measure });
const modes = document.querySelectorAll("[data-mode]");
const result = document.getElementById("result");

measurement.subscribe((s) => {
  for (const b of modes) b.setAttribute("aria-pressed", String(b.dataset.mode === s.mode));
  if (!s.mode) return (result.textContent = "");
  const lines = [`${s.mode === "area" ? "Perimeter" : "Length"}: ${formatLength(s.length)}`];
  if (s.area !== null) lines.push(`Area: ${formatArea(s.area)}`);
  lines.push(...s.segments.map((m, i) => `  ${i + 1}. ${formatLength(m)}`));
  result.textContent = lines.join("\n");
});

for (const b of modes) b.onclick = () => measurement.start(b.dataset.mode);
document.getElementById("undo").onclick = () => measurement.undo();
document.getElementById("clear").onclick = () => measurement.clear();
