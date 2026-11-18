// Stations read from a CSV, an area from WKT and lines from TopoJSON by mbt-map/table,
// drawn as GeoJSON sources and counted by the same tables (in the analysis worker). The
// shapefiles (bench/data/pack-fixtures.mjs writes them) are read by the pack test.
import { Map } from "mbt-map";
import { fromGeoJSON, parse, read, write } from "mbt-map/table";

const stations = await read("./stations.csv");
const area = await parse("SRID=4326;POLYGON ((139.760 35.670, 139.775 35.670, 139.775 35.688, 139.760 35.688, 139.760 35.670))", { format: "wkt" });
const lines = await read("./lines.topojson");
// Read before the first operation moves the rows into the analysis worker, and again after.
const before = JSON.stringify(await stations.toGeoJSON());
const csv = await write(stations, { format: "csv" });
const inside = await stations.pointsWithin(area);
const grown = await stations.buffer(10);
// Attribute operations (table.wasm), on the table that was read and on their own results.
const fail = (p) => Promise.resolve(p).then(() => "", (e) => e.message);
const ordered = await stations.orderby({ by: "乗降客数", descending: true });
const top = await (await ordered.slice(0, 2)).select(["名前"]);
const derived = await stations.derive({ area: await grown.areas(), half: ["/", ["get", "乗降客数"], 2], tag: { values: ["a", null, undefined, 1, true] }, 備考: ["coalesce", ["get", "備考"], "-"] });
const sized = { size: ["case", [">", ["coalesce", ["get", "乗降客数"], 0], 100000], "busy", "quiet"] };
const groups = await stations.groupby(sized).rollup({ n: ["count"], total: ["sum", "乗降客数"], top: ["max", "乗降客数"], first: ["any", "名前"], middle: ["quantile", "乗降客数", 0.5] });
const routes = await fromGeoJSON({
  type: "FeatureCollection",
  features: [["東京", "JR"], ["東京", "Metro"], ["神田", "JR"], ["品川", "JR"]].map(([名前, 路線]) => ({ type: "Feature", geometry: null, properties: { 名前, 路線 } })),
});
const joined = await stations.join(routes, "名前");
const operations = {
  groups: (await groups.toGeoJSON()).features.map((f) => [f.geometry, f.properties]),
  mean: await (await stations.rollup({ mean: ["mean", "乗降客数"], kinds: ["distinct", ["geometry-type"]] })).toGeoJSON().then((c) => c.features[0].properties),
  joined: [joined.columns, await joined.array("路線"), (await joined.toGeoJSON()).features.map((f) => f.geometry?.type)],
  natural: (await stations.join(routes)).length,
  left: await (await stations.join(routes, ["名前", "名前"], { left: true })).array("名前"),
  renamed: (await routes.join(routes, [["路線"]], { suffix: ["", "2"] })).columns,
  noAggregate: await fail(stations.rollup({ x: ["nope", "名前"] })),
  noFraction: await fail(stations.rollup({ x: ["quantile", "名前"] })),
  noValue: await fail(stations.groupby("名前").rollup({ x: ["sum", "zz"] })),
  noKey: await fail(stations.groupby("zz").rollup({ n: ["count"] })),
  noJoinColumn: await fail(stations.join(routes, "路線")),
  noShared: await fail(groups.join(routes)),
  unevenKeys: await fail(stations.join(routes, ["名前", ["名前", "路線"]])),
  noTable: await fail(stations.join({})),
  busy: await (await stations.filter([">", ["get", "乗降客数"], 100000])).array("名前"),
  top: (await top.toGeoJSON()).features.map((f) => [f.geometry.type, f.properties]),
  columns: derived.columns,
  types: await derived.columnTypes(),
  area: Array.from(await derived.array("area"), (v) => Math.round(v)),
  half: await derived.array("half"),
  tag: (await derived.array("tag")).map((v) => (v === undefined ? "absent" : v)),
  notes: await derived.array("備考"),
  nearest: await (await stations.filter(await stations.nearest(139.7671, 35.6812, { k: 2 }))).array("名前"),
  last: await (await stations.slice(-2)).array("名前"),
  points: await (await stations.filter(["==", ["geometry-type"], "Point"])).array("名前"),
  noColumn: await fail(stations.select(["x"])),
  noRow: await fail(stations.filter(Uint32Array.of(9))),
  halfRow: await fail(stations.filter(Float64Array.of(0.5))),
  badExpression: await fail(stations.filter(["nope"])),
};

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
    operations,
    inside: Array.from(inside),
    lines: { layer: lines.layer, layers: lines.layers, features: (await lines.toGeoJSON()).features },
  };
  window.__loaded = performance.now();
});
window.__map = map;
