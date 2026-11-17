import { Map } from "mbt-map";
import { write } from "mbt-map/table";

const features = {
  type: "FeatureCollection",
  features: [
    { type: "Feature", properties: { name: "Tokyo Station", kind: "station" }, geometry: { type: "Point", coordinates: [139.7671, 35.6812] } },
    { type: "Feature", properties: { name: "Yurakucho Station", kind: "station" }, geometry: { type: "Point", coordinates: [139.7631, 35.675] } },
    {
      type: "Feature",
      properties: { name: "Walk to the palace", kind: "route" },
      geometry: { type: "LineString", coordinates: [[139.7671, 35.6812], [139.7635, 35.6815], [139.7598, 35.6828]] },
    },
    {
      type: "Feature",
      properties: { name: "Imperial Palace East Gardens", kind: "park" },
      geometry: { type: "Polygon", coordinates: [[[139.7556, 35.6857], [139.7605, 35.6857], [139.7605, 35.6899], [139.7556, 35.6899], [139.7556, 35.6857]]] },
    },
  ],
};

const FORMATS = {
  geojson: { type: "application/geo+json", extension: "geojson" },
  csv: { type: "text/csv", extension: "csv" },
  kml: { type: "application/vnd.google-earth.kml+xml", extension: "kml" },
};

const only = (...types) => ["in", ["geometry-type"], ["literal", types]];
new Map({
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
      features: { type: "geojson", data: features },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "fill", type: "fill", source: "features", filter: only("Polygon"), paint: { "fill-color": "#2a9d55", "fill-opacity": 0.25 } },
      { id: "line", type: "line", source: "features", filter: only("LineString", "Polygon"), paint: { "line-color": "#2a9d55", "line-width": 3 } },
      { id: "point", type: "circle", source: "features", filter: only("Point"), paint: { "circle-radius": 6, "circle-color": "#2a9d55", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } },
    ],
  },
  center: [139.758, 35.6825],
  zoom: 14.5,
});

const preview = document.getElementById("preview");

function download(text, name, type) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

for (const button of document.querySelectorAll("[data-format]")) {
  button.onclick = async () => {
    const format = button.dataset.format;
    const { type, extension } = FORMATS[format];
    const text = await write(features, { format });
    preview.textContent = text;
    download(text, `features.${extension}`, type);
  };
}
