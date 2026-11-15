// The map on the home pages: GSI's pale map with stations around Tokyo, drawn by the package in lib/.
import { Map } from "mbt-map";

const STATIONS = [
  ["東京", 139.7671, 35.6812],
  ["有楽町", 139.7631, 35.6751],
  ["神田", 139.7708, 35.6918],
  ["新橋", 139.7583, 35.6662],
  ["秋葉原", 139.7731, 35.6984],
  ["日本橋", 139.7745, 35.684],
  ["大手町", 139.7662, 35.6864],
  ["銀座", 139.7671, 35.6717],
];

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
      stations: {
        type: "geojson",
        promoteId: "name",
        data: {
          type: "FeatureCollection",
          features: STATIONS.map(([name, lng, lat]) => ({ type: "Feature", properties: { name }, geometry: { type: "Point", coordinates: [lng, lat] } })),
        },
      },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      {
        id: "stations",
        type: "circle",
        source: "stations",
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 3, 16, 9],
          "circle-color": ["case", ["boolean", ["feature-state", "hover"], false], "#d6604d", "#2f5bd0"],
          "circle-stroke-color": "#ffffff",
          "circle-stroke-width": 2,
        },
      },
      {
        id: "station-names",
        type: "symbol",
        source: "stations",
        layout: { "text-field": ["get", "name"], "text-size": 13, "text-offset": [0, 1.1], "text-anchor": "top" },
        paint: { "text-color": "#18202d", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
      },
    ],
  },
  center: [139.7671, 35.6812],
  zoom: 13.6,
  pitch: 30,
});

let hovered = null;
const setHover = (id) => {
  if (hovered !== null) map.setFeatureState({ source: "stations", id: hovered }, { hover: false });
  hovered = id;
  if (id !== null) map.setFeatureState({ source: "stations", id }, { hover: true });
};
map.on("mousemove", "stations", (e) => {
  map.getCanvas().style.cursor = "pointer";
  setHover(e.features[0].id ?? null);
});
map.on("mouseleave", "stations", () => {
  map.getCanvas().style.cursor = "";
  setHover(null);
});
map.on("click", "stations", (e) => map.flyTo({ center: e.lngLat, zoom: 16, pitch: 50, duration: 1600 }));
