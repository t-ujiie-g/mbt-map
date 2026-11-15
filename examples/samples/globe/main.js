import { Map } from "mbt-map";

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
      { id: "background", type: "background", paint: { "background-color": "#efe9dc" } },
      { id: "water", type: "fill", source: "openmaptiles", "source-layer": "water", paint: { "fill-color": "#7fb2d9" } },
      {
        id: "boundaries",
        type: "line",
        source: "openmaptiles",
        "source-layer": "boundary",
        filter: ["==", ["get", "admin_level"], 2],
        paint: { "line-color": "#8a8a9a", "line-width": 1 },
      },
    ],
    projection: { type: "globe" },
    sky: { "sky-color": "#000814", "atmosphere-blend": ["interpolate", ["linear"], ["zoom"], 0, 1, 5, 1, 7, 0] },
  },
  center: [139.7671, 35.6812],
  zoom: 2,
});

const stops = [
  { center: [116.3975, 39.9087], zoom: 4 },
  { center: [2.3522, 48.8566], zoom: 3 },
  { center: [-74.006, 40.7128], zoom: 3 },
  { center: [151.2093, -33.8688], zoom: 3 },
  { center: [139.7671, 35.6812], zoom: 2 },
];

document.getElementById("fly").onclick = async () => {
  for (const stop of stops) {
    map.flyTo({ ...stop, duration: 4000, essential: true });
    await map.once("moveend");
  }
};
