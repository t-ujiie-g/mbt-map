// A GeoJSON source loaded from a table's bytes vs from GeoJSON text (geojson.wasm, without its worker): the tiles
// must be the same bytes, and the times of both paths go to bench/results/table-source.json.
// Usage: node table/source.mjs [--runs=N]
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { hostNumber, writeInput } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { loadInput } from "../../geojson_worker/js/diff.mjs";
import { nodeFetchBytes } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";
import { median } from "../lib/rows.mjs";
import { makeGeoJSONFixtures } from "../geojson/fixtures.mjs";
import { loadAnalysis } from "../analysis/load.mjs";

const RUNS = Number(arg("runs", 5));
await makeGeoJSONFixtures();
const a = (await loadAnalysis(nodeFetchBytes)).exports;
let g;
g = (await WebAssembly.instantiate(await nodeFetchBytes("_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine/geojson_worker/geojson_worker.wasm"), { Math, host: { number: hostNumber(() => g.memory) } })).instance.exports;

function load(parts, flags) {
  writeInput(g, parts, "source");
  const n = g.load(1, 18, 128, 0.375, flags, 0, 0, 0, 0);
  if (n < 0) throw new Error(new TextDecoder().decode(new Uint8Array(g.memory.buffer, g.output_addr(), -n)));
  return n;
}
function tile(z, x, y) {
  const n = Math.max(0, g.tile(1, z, x, y));
  return Buffer.from(new Uint8Array(g.memory.buffer, g.output_addr(), n)).toString("base64");
}
// Tiles over the data at a few zooms: the one holding its first point and its neighbors.
function tilesOf([lng, lat]) {
  const out = [[0, 0, 0]];
  for (const z of [4, 10, 14, 16]) {
    const x = Math.floor(((lng + 180) / 360) * 2 ** z);
    const y = Math.floor(((1 - Math.asinh(Math.tan((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z);
    out.push([z, x, y], [z, x + 1, y], [z, x, y + 1]);
  }
  return out;
}
const time = (f) => {
  f();
  return median(Array.from({ length: RUNS }, () => {
    const start = performance.now();
    f();
    return performance.now() - start;
  }));
};

const results = {};
let differ = 0;
for (const name of ["buildings", "roads", "points", "mixed"]) {
  const text = await nodeFetchBytes(`bench/dist/geojson/${name}.geojson`);
  const at = a.prepare_input(text.length);
  new Uint8Array(a.memory.buffer, at, text.length).set(text);
  const id = a.load();
  const table = new Uint8Array(a.memory.buffer.slice(a.output_addr(), a.output_addr() + a.table_out(id)));
  a.dispose(id);
  const fromText = () => load(loadInput(undefined, text), 0);
  const fromTable = () => load(loadInput(undefined, null, table.buffer, null), 2);
  const first = JSON.parse(new TextDecoder().decode(text)).features.find((f) => f.geometry)?.geometry.coordinates.flat(4).slice(0, 2);
  const tiles = tilesOf(first);
  const features = fromText();
  const want = tiles.map((t) => tile(...t));
  fromTable();
  const got = tiles.map((t) => tile(...t));
  const same = want.filter((w, i) => w === got[i]).length;
  differ += tiles.length - same;
  let fc;
  results[name] = {
    features,
    bytes: { geojson: text.length, table: table.length },
    tiles: { compared: tiles.length, identical: same, nonEmpty: want.filter((w) => w.length > 0).length },
    ms: {
      "worker: load from GeoJSON text": time(fromText),
      "worker: load from table bytes": time(fromTable),
      "page: table to GeoJSON object": time(() => (fc = tableToGeoJSON(table))),
      "page: JSON.stringify and encode": time(() => new TextEncoder().encode(JSON.stringify(fc))),
    },
  };
}
console.table(Object.fromEntries(Object.entries(results).map(([name, r]) => [name, { features: r.features, tiles: `${r.tiles.identical}/${r.tiles.compared}`, ...Object.fromEntries(Object.entries(r.ms).map(([k, v]) => [k, v.toFixed(1)])) }])));
await writeFile(path.join(ROOT, "bench/results/table-source.json"), `${JSON.stringify({ env: { runtime: `node ${process.version}` }, runs: RUNS, results }, null, 2)}\n`);
console.log(differ === 0 ? "all tiles identical" : `${differ} tiles differ`);
process.exit(differ === 0 ? 0 : 1);
