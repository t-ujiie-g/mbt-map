import { Map, timeOfDayLights } from "mbt-map";
import { modelLayer } from "mbt-map/3d";

const CENTER = [139.7655, 35.6812];

const towers = {
  type: "FeatureCollection",
  features: [
    [139.7643, 35.6814, 0, 1],
    [139.7655, 35.6806, 30, 1.5],
    [139.7667, 35.6819, 60, 2],
  ].map(([lng, lat, heading, size]) => ({
    type: "Feature",
    properties: { heading, size },
    geometry: { type: "Point", coordinates: [lng, lat] },
  })),
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
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: CENTER,
  zoom: 16.8,
  pitch: 55,
  bearing: 30,
});

const size = ["get", "size"];
const layer = modelLayer({
  id: "towers",
  model: new URL("./tower.glb", import.meta.url).href,
  data: towers,
  scale: [size, size, size],
  rotation: [0, 0, ["get", "heading"]],
});

const hour = document.getElementById("hour");
const time = document.getElementById("time");

/** The sun over Tokyo at `h` o'clock (JST) on the summer solstice, casting shadows. */
function setSun(h) {
  const when = new Date(Date.UTC(2026, 5, 21, 0, (h - 9) * 60));
  const lights = timeOfDayLights(when, ...CENTER).map((l) =>
    l.type === "directional" ? { ...l, properties: { ...l.properties, "cast-shadows": true, "shadow-intensity": 0.6 } } : l,
  );
  map.setLights(lights);
  time.textContent = when.toLocaleTimeString("ja-JP", { timeZone: "Asia/Tokyo", hour: "2-digit", minute: "2-digit" });
}

await map.once("load");
map.addLayer(layer);
setSun(Number(hour.value));
hour.addEventListener("input", () => setSun(Number(hour.value)));
