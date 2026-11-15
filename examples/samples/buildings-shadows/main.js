import { Map, timeOfDayLights } from "mbt-map";

const center = [139.6917, 35.6896];

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      openmaptiles: {
        type: "vector",
        url: "https://tiles.openfreemap.org/planet",
        attribution: "OpenFreeMap © OpenMapTiles Data from OpenStreetMap",
      },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#f2efe9" } },
      { id: "park", type: "fill", source: "openmaptiles", "source-layer": "park", paint: { "fill-color": "#d8e8c8" } },
      { id: "water", type: "fill", source: "openmaptiles", "source-layer": "water", paint: { "fill-color": "#a5c8e8" } },
      {
        id: "roads",
        type: "line",
        source: "openmaptiles",
        "source-layer": "transportation",
        paint: { "line-color": "#ffffff", "line-width": ["interpolate", ["exponential", 1.5], ["zoom"], 13, 1, 18, 12] },
      },
      {
        id: "buildings",
        type: "fill-extrusion",
        source: "openmaptiles",
        "source-layer": "building",
        paint: {
          "fill-extrusion-color": "#dcd6cc",
          "fill-extrusion-height": ["get", "render_height"],
          "fill-extrusion-base": ["get", "render_min_height"],
        },
      },
    ],
  },
  center,
  zoom: 15.5,
  pitch: 60,
  bearing: -30,
});

const slider = document.getElementById("hour");
const time = document.getElementById("time");

function update() {
  const hour = Number(slider.value);
  const hh = String(Math.floor(hour)).padStart(2, "0");
  const mm = String((hour % 1) * 60).padStart(2, "0");
  time.textContent = `${hh}:${mm}`;
  const lights = timeOfDayLights(new Date(`2026-06-21T${hh}:${mm}:00+09:00`), ...center);
  map.setLights(lights.map((light) =>
    light.type === "directional"
      ? { ...light, properties: { ...light.properties, "cast-shadows": true, "shadow-intensity": 0.6 } }
      : light,
  ));
}

slider.oninput = update;
map.once("load", update);
