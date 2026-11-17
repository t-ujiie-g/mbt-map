import { Map } from "mbt-map";
import { parse, read } from "mbt-map/table";

const PLACES = `name,lat,lon,opened
Tokyo Station,35.6812,139.7671,1914
Tokyo Tower,35.6586,139.7454,1958
Sensō-ji,35.7148,139.7967,645
Ueno Park,35.7156,139.7745,1873
Shinjuku Gyoen,35.6852,139.7101,1949
Meiji Jingu,35.6764,139.6993,1920
Tokyo Skytree,35.7101,139.8107,2012`;

const only = (...types) => ["in", ["geometry-type"], ["literal", types]];
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
      data: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "fill", type: "fill", source: "data", filter: only("Polygon", "MultiPolygon"), paint: { "fill-color": "#2f5bd0", "fill-opacity": 0.2 } },
      { id: "line", type: "line", source: "data", filter: only("LineString", "MultiLineString", "Polygon", "MultiPolygon"), paint: { "line-color": "#2f5bd0", "line-width": 2 } },
      { id: "point", type: "circle", source: "data", filter: only("Point", "MultiPoint"), paint: { "circle-radius": 6, "circle-color": "#2f5bd0", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } },
      { id: "label", type: "symbol", source: "data", filter: only("Point"), layout: { "text-field": ["get", "name"], "text-size": 12, "text-offset": [0, 1.2], "text-anchor": "top" }, paint: { "text-halo-color": "#fff", "text-halo-width": 1.5 } },
    ],
  },
  center: [139.7671, 35.6812],
  zoom: 11,
});
await map.once("load");

const status = document.getElementById("status");

function bounds({ features }) {
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  const visit = (c) => {
    if (typeof c[0] !== "number") return c.forEach(visit);
    box[0] = Math.min(box[0], c[0]);
    box[1] = Math.min(box[1], c[1]);
    box[2] = Math.max(box[2], c[0]);
    box[3] = Math.max(box[3], c[1]);
  };
  for (const f of features) if (f.geometry) visit(f.geometry.coordinates);
  return box[0] <= box[2] ? box : null;
}

async function show(reading, name) {
  status.textContent = `Reading ${name}…`;
  try {
    const table = await reading;
    const data = await table.toGeoJSON();
    map.getSource("data").setData(data);
    const box = bounds(data);
    if (box) map.fitBounds(box, { padding: 60, maxZoom: 15 });
    status.textContent = `${name}: ${table.length} row${table.length === 1 ? "" : "s"} (${table.format})\ncolumns: ${table.columns.join(", ")}`;
  } catch (e) {
    status.textContent = `${name}: ${e.message}`;
  }
}

show(parse(PLACES, { format: "csv" }), "places.csv");

const input = document.getElementById("file");
input.onchange = () => input.files.length && show(read(input.files), input.files[0].name);

document.addEventListener("dragover", (e) => e.preventDefault());
document.addEventListener("drop", (e) => {
  e.preventDefault();
  const { files } = e.dataTransfer;
  if (files.length) show(read(files), files[0].name);
});
