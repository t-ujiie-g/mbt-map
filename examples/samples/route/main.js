import { Map } from "mbt-map";
import { load } from "mbt-map/analysis";

// A jittered 10 x 10 grid of streets near Tokyo Station, some blocks missing.
const SIZE = 10;
const [WEST, SOUTH, STEP] = [139.752, 35.672, 0.0022];
let seed = 3;
const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
const nodes = Array.from({ length: SIZE * SIZE }, (_, i) => [
  WEST + (i % SIZE) * STEP + (random() - 0.5) * STEP * 0.5,
  SOUTH + Math.floor(i / SIZE) * STEP + (random() - 0.5) * STEP * 0.5,
]);
const streets = [];
for (let i = 0; i < nodes.length; i++) {
  if (i % SIZE < SIZE - 1 && random() > 0.15) streets.push([nodes[i], nodes[i + 1]]);
  if (i < nodes.length - SIZE && random() > 0.15) streets.push([nodes[i], nodes[i + SIZE]]);
}
const roads = {
  type: "FeatureCollection",
  features: streets.map((coordinates) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } })),
};

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
      roads: { type: "geojson", data: roads },
      route: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "roads", type: "line", source: "roads", paint: { "line-color": "#5b6676", "line-width": 3 } },
      { id: "route", type: "line", source: "route", filter: ["==", ["geometry-type"], "LineString"], paint: { "line-color": "#2f5bd0", "line-width": 6 } },
      { id: "ends", type: "circle", source: "route", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 7, "circle-color": "#e4572e", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } },
    ],
  },
  center: [139.762, 35.682],
  zoom: 14,
});
await map.once("load");

const network = await (await load(roads)).network({ snap: 2 });
const status = document.getElementById("status");
let ends = [];

const feature = (type, coordinates) => ({ type: "Feature", properties: {}, geometry: { type, coordinates } });

function nearestNode({ lng, lat }) {
  const cos = Math.cos((lat * Math.PI) / 180);
  let best = nodes[0];
  for (const n of nodes) {
    if (Math.hypot((n[0] - lng) * cos, n[1] - lat) < Math.hypot((best[0] - lng) * cos, best[1] - lat)) best = n;
  }
  return best;
}

map.on("click", async (e) => {
  ends = ends.length === 2 ? [nearestNode(e.lngLat)] : [...ends, nearestNode(e.lngLat)];
  const found = ends.length === 2 ? await network.route(ends[0], ends[1]) : null;
  const features = ends.map((p) => feature("Point", p));
  if (found) features.unshift(feature("LineString", found.path));
  map.getSource("route").setData({ type: "FeatureCollection", features });
  status.textContent =
    ends.length < 2 ? "Now click the destination." : found ? `${(found.weight * 1000).toFixed(0)} m` : "These two are not connected.";
});
