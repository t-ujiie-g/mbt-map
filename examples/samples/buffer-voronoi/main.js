import { Map } from "mbt-map";
import { load } from "mbt-map/analysis";

const STATIONS = [
  ["Tokyo", 139.7671, 35.6812], ["Shinjuku", 139.7006, 35.6896], ["Shibuya", 139.7016, 35.658],
  ["Ikebukuro", 139.7109, 35.7295], ["Ueno", 139.7774, 35.7141], ["Shinagawa", 139.7387, 35.6285],
  ["Akihabara", 139.7731, 35.6984], ["Iidabashi", 139.7451, 35.702], ["Ebisu", 139.7101, 35.6467],
  ["Roppongi", 139.7314, 35.6628], ["Oshiage", 139.8128, 35.7107], ["Toyosu", 139.7958, 35.6549],
];
const BOX = [139.68, 35.62, 139.83, 35.74];

const stations = {
  type: "FeatureCollection",
  features: STATIONS.map(([name, lng, lat]) => ({ type: "Feature", properties: { name }, geometry: { type: "Point", coordinates: [lng, lat] } })),
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
        maxzoom: 18,
        attribution: "国土地理院",
      },
      result: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
      stations: { type: "geojson", data: stations },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "result-fill", type: "fill", source: "result", paint: { "fill-color": "#e4572e", "fill-opacity": 0.15 } },
      { id: "result-line", type: "line", source: "result", paint: { "line-color": "#e4572e", "line-width": 1.5 } },
      { id: "stations", type: "circle", source: "stations", paint: { "circle-radius": 5, "circle-color": "#18202d", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } },
    ],
  },
  center: [139.755, 35.68],
  zoom: 11.5,
});
await map.once("load");

const points = await load(stations);
const status = document.getElementById("status");
const buttons = document.querySelectorAll("[data-op]");

const ops = {
  buffer: () => points.buffer(Number(document.getElementById("meters").value)),
  voronoi: () => points.voronoi(BOX),
  hull: () => points.convexHull(),
};

for (const button of buttons) {
  button.onclick = async () => {
    for (const b of buttons) b.setAttribute("aria-pressed", String(b === button));
    const result = await ops[button.dataset.op]();
    const areas = await result.areas();
    map.getSource("result").setData(await result.toGeoJSON());
    const km2 = areas.reduce((sum, a) => sum + a, 0) / 1e6;
    status.textContent = `${result.length} feature${result.length === 1 ? "" : "s"}, ${km2.toFixed(1)} km² in all`;
    result.dispose();
  };
}
