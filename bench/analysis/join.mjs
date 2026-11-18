// A spatial join with a rollup as mbt-map/table's `spatialJoin` runs it (relate.wasm's pairs, then table.wasm's
// `pairs`), driven without the worker: what took the place of the analysis wasm's `collect`.
import { hostText } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";

const BUILD = "_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export async function loadJoin(fetchBytes, analysis) {
  const relate = (await WebAssembly.instantiate(await fetchBytes(`${BUILD}/relate_worker/relate_worker.wasm`), {})).instance.exports;
  const table = (await WebAssembly.instantiate(await fetchBytes(`${BUILD}/table_worker/table_worker.wasm`), { Math, host: hostText() })).instance.exports;
  const put = (e, parts) => {
    let at = e.prepare_input(parts.reduce((n, p) => n + p.length, 0));
    for (const p of parts) {
      new Uint8Array(e.memory.buffer, at, p.length).set(p);
      at += p.length;
    }
  };
  const out = (e, n) => {
    if (n < 0) throw new Error(decoder.decode(out(e, -n)));
    return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
  };
  const text = (s) => {
    const b = encoder.encode(s);
    return [new Uint8Array(Uint32Array.of(b.length).buffer), b];
  };
  // ["get", property] as packed JSON: a column the table may lack.
  const get = (property) => [5, new Uint8Array(Uint32Array.of(2).buffer), 4, ...text("get"), 4, ...text(property)];
  // Outputs count, valid and sum of `property`, as docs/dev/FORMATS.md "Table operations" packs them.
  const outputs = (property) => [
    new Uint8Array(Uint32Array.of(3).buffer),
    ...[["count", 0, [0]], ["valid", 1, get(property)], ["sum", 3, get(property)]].flatMap(([name, code, value]) => [
      ...text(name), Uint8Array.of(code), new Uint8Array(Float64Array.of(0.5).buffer), ...value.flatMap((v) => (typeof v === "number" ? [Uint8Array.of(v)] : [v])),
    ]),
  ];
  const tableOf = (id) => out(analysis, analysis.table_out(id));
  return {
    // The table bytes of dataset `polygons` with the count of the rows of `points` meeting each, how many hold
    // `property` and its sum.
    rollup(polygons, points, property) {
      const [a, b] = [tableOf(polygons), tableOf(points)];
      put(relate, [a, b]);
      const pairs = out(relate, relate.relate_pairs(a.length, 0, 0) * 4);
      relate.forget_tables();
      put(table, [a, b, Uint8Array.of(2), ...text("_1"), ...text("_2"), new Uint8Array(Uint32Array.of(pairs.length / 4).buffer), pairs, ...outputs(property)]);
      return out(table, table.pairs(a.length, b.length));
    },
    // Three numbers per row of `rollup`'s table, as bench/analysis/reference.mjs's `collected`.
    collected: (bytes) => Float64Array.from(tableToGeoJSON(bytes).features.flatMap((f) => [f.properties.count, f.properties.valid, f.properties.sum ?? 0])),
  };
}
