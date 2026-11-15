import { Map, sunPosition, timeOfDayLights } from "mbt-map";

const center = [139.6917, 35.6896];
// The ground's layers with the paint property and color each has by day.
const GROUND = { background: ["background-color", "#f2efe9"], park: ["fill-color", "#d8e8c8"], water: ["fill-color", "#a5c8e8"], roads: ["line-color", "#ffffff"] };
const DUSK = [20, 26, 42];

/** `color` (#rrggbb) mixed with the dusk's by `share` (0 to 1). */
const dim = (color, share) => `rgb(${DUSK.map((c, i) => Math.round(parseInt(color.slice(2 * i + 1, 2 * i + 3), 16) * (1 - share) + c * share)).join(", ")})`;

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
      { id: "background", type: "background", paint: { "background-color": GROUND.background[1] } },
      { id: "park", type: "fill", source: "openmaptiles", "source-layer": "park", paint: { "fill-color": GROUND.park[1] } },
      { id: "water", type: "fill", source: "openmaptiles", "source-layer": "water", paint: { "fill-color": GROUND.water[1] } },
      {
        id: "roads",
        type: "line",
        source: "openmaptiles",
        "source-layer": "transportation",
        paint: { "line-color": GROUND.roads[1], "line-width": ["interpolate", ["exponential", 1.5], ["zoom"], 13, 1, 18, 12] },
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
  const date = new Date(`2026-06-21T${hh}:${mm}:00+09:00`);
  // 0 with the sun on the horizon, 1 from 10° up: as it sets the shadows fade, the ambient light makes up
  // for the sun's and the ground goes dark, so dusk is dim rather than black buildings on a bright map.
  const up = Math.min(1, Math.max(0, sunPosition(date, ...center).altitude / 10));
  const [ambient, sun] = timeOfDayLights(date, ...center);
  map.setLights([
    { ...ambient, properties: { ...ambient.properties, intensity: ambient.properties.intensity + 0.3 * (1 - up) } },
    { ...sun, properties: { ...sun.properties, "cast-shadows": up > 0, "shadow-intensity": 0.6 * up } },
  ]);
  for (const [id, [property, color]] of Object.entries(GROUND)) map.setPaintProperty(id, property, dim(color, 0.75 * (1 - up)));
}

slider.oninput = update;
map.once("load", update);
