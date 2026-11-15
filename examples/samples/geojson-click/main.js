import { Map } from "mbt-map";

const stations = [
  ["Tokyo", "東京", "Chiyoda", 139.7671, 35.6812],
  ["Shinjuku", "新宿", "Shinjuku", 139.7005, 35.6905],
  ["Shibuya", "渋谷", "Shibuya", 139.7016, 35.658],
  ["Ikebukuro", "池袋", "Toshima", 139.7109, 35.7295],
  ["Shinagawa", "品川", "Minato", 139.7387, 35.6285],
  ["Ueno", "上野", "Taito", 139.7774, 35.7141],
  ["Akihabara", "秋葉原", "Chiyoda", 139.7731, 35.6984],
  ["Shimbashi", "新橋", "Minato", 139.7583, 35.6663],
];

const data = {
  type: "FeatureCollection",
  features: stations.map(([name, ja, city, lng, lat]) => ({
    type: "Feature",
    properties: { name, ja, city },
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
      stations: { type: "geojson", data, promoteId: "name" },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      {
        id: "stations",
        type: "circle",
        source: "stations",
        paint: {
          "circle-radius": ["case", ["boolean", ["feature-state", "hover"], false], 11, 7],
          "circle-color": ["case", ["boolean", ["feature-state", "hover"], false], "#e8590c", "#2f5bd0"],
          "circle-stroke-color": "#fff",
          "circle-stroke-width": 2,
        },
      },
    ],
  },
  bounds: [[139.70, 35.628], [139.778, 35.73]],
  fitBoundsOptions: { padding: 60 },
});

let hovered = null;
const setHover = (id) => {
  if (hovered !== null) map.setFeatureState({ source: "stations", id: hovered }, { hover: false });
  hovered = id;
  if (id !== null) map.setFeatureState({ source: "stations", id }, { hover: true });
};

map.on("mousemove", "stations", (e) => {
  map.getCanvas().style.cursor = "pointer";
  setHover(e.features[0].properties.name);
});
map.on("mouseleave", "stations", () => {
  map.getCanvas().style.cursor = "";
  setHover(null);
});

const info = document.getElementById("info");
map.on("click", "stations", (e) => {
  info.textContent = JSON.stringify(e.features[0].properties, null, 2);
});
