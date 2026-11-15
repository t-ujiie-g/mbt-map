import { Map } from "mbt-map";
import { lineOfSight, measure3d } from "mbt-map/3d";

const EYE = 1.6;

const map = new Map({
  container: "map",
  style: "https://tiles.openfreemap.org/styles/liberty",
  center: [139.6948, 35.6905],
  zoom: 16.5,
  pitch: 50,
  bearing: -30,
});

const status = document.getElementById("status");
const meters = (m) => `${m.toFixed(1)} m`;
let from = null;

const line = (a, b, seen) => ({ type: "Feature", properties: { seen }, geometry: { type: "LineString", coordinates: [a.slice(0, 2), b.slice(0, 2)] } });
const point = (p) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: p.slice(0, 2) } });
const draw = (...features) => map.getSource("sight").setData({ type: "FeatureCollection", features });

await map.once("load");
map.addSource("sight", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
map.addLayer({ id: "sight", type: "line", source: "sight", paint: { "line-width": 4, "line-color": ["case", ["get", "seen"], "#2a9d4b", "#d6342c"] } });
map.addLayer({ id: "ends", type: "circle", source: "sight", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 5, "circle-color": "#18202d" } });

map.on("click", (e) => {
  const at = map.pickPosition(e.point);
  if (!at) return;
  if (!from) {
    from = [at[0], at[1], at[2] + EYE];
    draw(point(from));
    status.textContent = "Now click where you look.";
    return;
  }
  const sight = lineOfSight(map, from, at);
  const block = sight.obstruction;
  if (sight.visible) {
    draw(line(from, at, true), point(from), point(at));
    status.textContent = `Clear: ${meters(measure3d([from, at]).length)}`;
  } else {
    draw(line(from, block, true), line(block, at, false), point(from), point(at));
    status.textContent = `Blocked ${meters(measure3d([from, block]).length)} away, ${meters(block[2])} up`;
  }
  status.textContent += ". Click again to start over.";
  from = null;
});
