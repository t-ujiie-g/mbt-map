// Stations read from a CSV, an area from WKT and lines from TopoJSON by mbt-map/table,
// drawn as GeoJSON sources and counted by the same tables (in the analysis worker). The
// shapefiles (bench/data/pack-fixtures.mjs writes them) are read by the pack test.
import { Map } from "mbt-map";
import { parse, read, write } from "mbt-map/table";

const stations = await read("./stations.csv");
const area = await parse("SRID=4326;POLYGON ((139.760 35.670, 139.775 35.670, 139.775 35.688, 139.760 35.688, 139.760 35.670))", { format: "wkt" });
const lines = await read("./lines.topojson");
// Read before the first operation moves the rows into the analysis worker, and again after.
const before = JSON.stringify(await stations.toGeoJSON());
const csv = await write(stations, { format: "csv" });
const inside = await stations.pointsWithin(area);
const grown = await stations.buffer(10);

const map = new Map({
  container: "map",
  center: [139.767, 35.684],
  zoom: 14,
  style: {
    version: 8,
    sources: {
      gsi: { type: "vector", tiles: ["/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14, attribution: "国土地理院ベクトルタイル提供実験" },
      area: { type: "geojson", data: (await area.toGeoJSON()) },
      stations: { type: "geojson", data: (await stations.toGeoJSON()) },
      lines: { type: "geojson", data: (await lines.toGeoJSON()) },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", paint: { "line-color": "#ffffff", "line-width": 2 } },
      { id: "area", type: "fill", source: "area", paint: { "fill-color": "#3b82f6", "fill-opacity": 0.2 } },
      { id: "lines", type: "line", source: "lines", paint: { "line-color": "#16a34a", "line-width": 3 } },
      { id: "stations", type: "circle", source: "stations", paint: { "circle-radius": 6, "circle-color": "#e4572e" } },
    ],
  },
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(async () => {
  window.__data = {
    length: stations.length,
    columns: stations.columns,
    features: (await stations.toGeoJSON()).features,
    area: (await area.toGeoJSON()).features[0].geometry.type,
    datasets: [stations.length, area.length],
    moved: JSON.stringify(await stations.toGeoJSON()) === before && (await write(stations, { format: "csv" })) === csv,
    derived: [grown.length, grown.columns, grown.format],
    inside: Array.from(inside),
    lines: { layer: lines.layer, layers: lines.layers, features: (await lines.toGeoJSON()).features },
  };
  window.__loaded = performance.now();
});
window.__map = map;
