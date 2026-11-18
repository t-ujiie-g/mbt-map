// arrow.wasm vs apache-arrow 21.2.0 (wkx 0.5.0 for WKB, lz4js 0.2.0 for its LZ4 buffers) on seeded random
// tables: what it writes must read back in apache-arrow as the table's values and geometries, what
// apache-arrow writes must read as its values, and damaged input must be refused without a trap.
// Usage: node table/arrow-golden.mjs [--tables=N]; writes bench/results/arrow-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import * as arrow from "apache-arrow";
import wkx from "wkx";
import lz4 from "lz4js";
import { hostNumber, hostText } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const TABLES = Number(arg("tables", 40));
// apache-arrow compresses buffers with the codec it is given.
arrow.compressionRegistry.set(arrow.CompressionType.LZ4_FRAME, { encode: (data) => lz4.compress(data), decode: (data) => lz4.decompress(data) });
const wasmOf = async (name, imports) =>
  (await WebAssembly.instantiate(await readFile(path.join(ROOT, `_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine/${name}/${name}.wasm`)), imports)).instance.exports;
let a;
a = await wasmOf("analysis_worker", { Math, host: { number: hostNumber(() => a.memory) } });
const w = await wasmOf("arrow_worker", { Math, host: hostText() });
const decoder = new TextDecoder();
const encoder = new TextEncoder();
function put(e, bytes) {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
}
function out(e, n) {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
}
// GeoJSON features as table bytes, as `fromGeoJSON` loads them.
function tableOf(features) {
  put(a, encoder.encode(JSON.stringify({ type: "FeatureCollection", features })));
  const id = a.load();
  if (id < 0) throw new Error("load failed");
  const bytes = out(a, a.table_out(id));
  a.dispose(id);
  return bytes;
}
const FLAGS = { native: 1, file: 2 };
function write(table, flags) {
  put(w, table);
  return out(w, w.write(flags));
}
// Arrow bytes read: the rows as GeoJSON features and what the geometry column told of itself.
function read(bytes) {
  put(w, bytes);
  const features = tableToGeoJSON(out(w, w.read())).features;
  const info = out(w, w.info_out());
  const view = new DataView(info.buffer);
  const texts = [];
  for (let at = 0; at < info.length; ) {
    const n = view.getUint32(at, true);
    texts.push(decoder.decode(info.subarray(at + 4, at + 4 + n)));
    at += 4 + n;
  }
  return { features, geometry: texts[0], extension: texts[1], geo: texts[2] };
}

// Seeded xorshift32, so that every run compares the same tables.
let seed = 0x51f15e;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 4294967296;
}
const int = (n) => Math.floor(random() * n);
const pick = (xs) => xs[int(xs.length)];
const WORDS = ["", "a", "park", "é", "東京", "😀", "10", 'q"uote', "back\\slash"];
const xy = () => [Math.round((random() * 360 - 180) * 1e6) / 1e6, Math.round((random() * 170 - 85) * 1e6) / 1e6];
const line = () => Array.from({ length: 2 + int(4) }, xy);
function ring() {
  const [x, y] = xy();
  return [[x, y], [x + 1, y], [x + 1, y + 1], [x, y + 1], [x, y]];
}
const polygon = () => Array.from({ length: 1 + int(2) }, ring);
const SHAPES = {
  Point: xy,
  MultiPoint: () => Array.from({ length: 1 + int(3) }, xy),
  LineString: line,
  MultiLineString: () => Array.from({ length: 1 + int(3) }, line),
  Polygon: polygon,
  MultiPolygon: () => Array.from({ length: 1 + int(3) }, polygon),
};
const geometryOf = (type) => (type ? { type, coordinates: SHAPES[type]() } : null);
// Columns by what their cells hold; a missing key and null both read back as null.
const CELLS = {
  whole: () => pick([0, 1, -7, 2147483647, -2147483648, int(1000)]),
  real: () => pick([0.5, -1e21, 1e-7, 0.1 + 0.2, 4294967296, int(10)]),
  text: () => pick(WORDS),
  flag: () => random() < 0.5,
  mixed: () => pick([1, 2.5, "x", true, false, ""]),
  empty: () => null,
};
function makeFeatures(types, rows) {
  const names = Object.keys(CELLS).filter(() => random() < 0.8);
  return Array.from({ length: rows }, () => {
    const properties = {};
    for (const name of names) {
      const r = random();
      if (r < 0.1) properties[name] = null;
      else if (r > 0.15) properties[name] = CELLS[name]();
    }
    return { type: "Feature", properties, geometry: geometryOf(random() < 0.12 ? null : pick(types)) };
  });
}

const results = {};
const failures = [];
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, differ: 0 });
  r.cases++;
  if (want === got) return;
  r.differ++;
  if (failures.length < 12) failures.push({ group, label, want: String(want).slice(0, 400), got: String(got).slice(0, 400) });
}
const json = (v) => JSON.stringify(v, (_, x) => (typeof x === "bigint" ? Number(x) : x));

// What a column is written as and holds, by docs/data.md's rule.
function written(values) {
  const held = values.filter((v) => v != null);
  const kinds = new Set(held.map((v) => typeof v));
  if (held.length === 0) return { type: "Null", values: values.map(() => null) };
  if (kinds.size > 1 || kinds.has("string")) return { type: "Utf8", values: values.map((v) => (v == null ? null : String(v))) };
  if (kinds.has("boolean")) return { type: "Bool", values: values.map((v) => v ?? null) };
  const whole = held.every((v) => Number.isInteger(v) && v >= -2147483648 && v <= 2147483647);
  return { type: whole ? "Int32" : "Float64", values: values.map((v) => v ?? null) };
}
// A nested Arrow value (vectors of vectors of points) as arrays.
const plain = (v) => (v == null ? null : typeof v === "number" ? v : Array.from(v, plain));
// A geometry's coordinates as the GeoArrow type `kind` nests them.
function nested(geometry, kind) {
  if (!geometry) return null;
  const c = geometry.coordinates;
  if (kind === geometry.type.toLowerCase()) return c;
  return [c];
}
const NATIVE = [
  [["Point"], "point"], [["Point", "MultiPoint"], "multipoint"], [["MultiPoint"], "multipoint"], [["LineString"], "linestring"],
  [["LineString", "MultiLineString"], "multilinestring"], [["Polygon"], "polygon"], [["Polygon", "MultiPolygon"], "multipolygon"], [["MultiPolygon"], "multipolygon"],
];
const MIXED = [["Point", "LineString"], ["Polygon", "LineString", "MultiPoint"], Object.keys(SHAPES)];

for (let k = 0; k < TABLES; k++) {
  const types = k % 4 === 3 ? pick(MIXED) : NATIVE[k % NATIVE.length][0];
  const features = makeFeatures(types, pick([0, 1, 2, 9, 60, 300]));
  const table = tableOf(features);
  const label = `table ${k} (${features.length} rows of ${types})`;
  const names = [...new Set(features.flatMap((f) => Object.keys(f.properties)))];
  const present = features.filter((f) => f.geometry).map((f) => f.geometry.type);
  const some = present.length > 0;
  // GeoArrow's type for the rows: their one kind, or the multi of a kind and its multi; null for another mix.
  const kinds = [...new Set(present)].sort((x, y) => x.length - y.length);
  const uniform = kinds.length === 1 ? kinds[0].toLowerCase() : kinds.length === 2 && kinds[1] === `Multi${kinds[0]}` ? kinds[1].toLowerCase() : null;

  for (const flags of [0, FLAGS.file, FLAGS.native, FLAGS.native | FLAGS.file]) {
    const native = (flags & FLAGS.native) !== 0;
    const how = `${native ? "native" : "wkb"} ${flags & FLAGS.file ? "file" : "stream"}`;
    let bytes;
    try {
      bytes = write(table, flags);
    } catch (e) {
      check("write", `${label} ${how} refused`, String(native && some && uniform === null), String(/mixed geometry types/.test(e.message)));
      continue;
    }
    const t = arrow.tableFromIPC(bytes);
    check("write", `${label} ${how} rows`, features.length === 0 ? 0 : features.length, t.numRows);
    if (features.length === 0) continue;
    for (const name of names) {
      const want = written(features.map((f) => f.properties[name]));
      const column = t.getChild(name);
      check("write", `${label} ${how} ${name} type`, want.type, String(column?.type));
      check("write", `${label} ${how} ${name}`, json(want.values), json(column?.toArray ? Array.from({ length: t.numRows }, (_, i) => column.get(i)) : null));
    }
    const field = t.schema.fields.find((f) => f.metadata.has("ARROW:extension:name"));
    if (!some) {
      check("write", `${label} ${how} no geometry column`, "undefined", String(field?.name));
      continue;
    }
    const column = t.getChild(field.name);
    check("write", `${label} ${how} extension`, `geoarrow.${native ? uniform : "wkb"}`, field.metadata.get("ARROW:extension:name"));
    check("write", `${label} ${how} crs`, "OGC:CRS84", JSON.parse(field.metadata.get("ARROW:extension:metadata")).crs);
    check("write", `${label} ${how} geo`, field.name, JSON.parse(t.schema.metadata.get("geo")).primary_column);
    const got = Array.from({ length: t.numRows }, (_, i) => {
      const v = column.get(i);
      if (v == null) return null;
      return native ? plain(v) : wkx.Geometry.parse(Buffer.from(v)).toGeoJSON();
    });
    const want = features.map((f) => (native ? nested(f.geometry, uniform) : f.geometry));
    check("write", `${label} ${how} geometry`, json(want), json(got));

    // Our own reader gives the rows back (a mixed column as text, as it was written).
    const back = read(bytes);
    // A kind written among its multis reads back as the multi.
    const promoted = (g) => (g && native && g.type.toLowerCase() !== uniform ? { type: `Multi${g.type}`, coordinates: [g.coordinates] } : g);
    const rows = features.map((f) => ({ geometry: promoted(f.geometry), properties: Object.fromEntries(names.map((n) => [n, written(features.map((g) => g.properties[n])).values[features.indexOf(f)]])) }));
    check("round trip", `${label} ${how}`, json(rows), json(back.features.map((f) => ({ geometry: f.geometry, properties: Object.fromEntries(names.map((n) => [n, f.properties[n] ?? null])) }))));
    check("round trip", `${label} ${how} column`, field.name, back.geometry);
  }
}

// Tables apache-arrow writes: every type read, the ones left out, dictionaries, several batches.
const iso = (ms, utc) => new Date(ms).toISOString().replace(".000Z", "Z").replace(/Z$/, utc ? "Z" : "");
function typed(rows) {
  const n = rows;
  const ints = Array.from({ length: n }, () => (random() < 0.15 ? null : int(200) - 100));
  const big = Array.from({ length: n }, () => (random() < 0.15 ? null : BigInt(int(2 ** 31)) * 4096n - 5n));
  const reals = Array.from({ length: n }, () => (random() < 0.15 ? null : pick([0.5, -2.25, 1e10, 3])));
  const words = Array.from({ length: n }, () => (random() < 0.15 ? null : pick(WORDS)));
  const flags = Array.from({ length: n }, () => (random() < 0.15 ? null : random() < 0.5));
  const days = Array.from({ length: n }, () => (random() < 0.15 ? null : (int(40000) - 10000) * 86400000));
  const times = Array.from({ length: n }, () => (random() < 0.15 ? null : (int(2 ** 31) - 2 ** 30) * 1000 + pick([0, 0, 123])));
  const vector = (values, type) => arrow.vectorFromArray(values, type);
  const columns = {
    i8: [vector(ints, new arrow.Int8()), ints],
    i16: [vector(ints, new arrow.Int16()), ints],
    i32: [vector(ints, new arrow.Int32()), ints],
    i64: [vector(big, new arrow.Int64()), big.map((v) => (v == null ? null : Number(v)))],
    u8: [vector(ints.map((v) => (v == null ? null : v + 100)), new arrow.Uint8()), ints.map((v) => (v == null ? null : v + 100))],
    u16: [vector(ints.map((v) => (v == null ? null : v + 100)), new arrow.Uint16()), ints.map((v) => (v == null ? null : v + 100))],
    u32: [vector(ints.map((v) => (v == null ? null : v + 4294967000)), new arrow.Uint32()), ints.map((v) => (v == null ? null : v + 4294967000))],
    u64: [vector(big.map((v) => (v == null ? null : v + 5n)), new arrow.Uint64()), big.map((v) => (v == null ? null : Number(v + 5n)))],
    f16: [vector(reals.map((v) => (v == null ? null : pick([0.5, -2.25, 3]))), new arrow.Float16()), null],
    f32: [vector(reals, new arrow.Float32()), reals.map((v) => (v == null ? null : Math.fround(v)))],
    f64: [vector(reals, new arrow.Float64()), reals],
    flag: [vector(flags, new arrow.Bool()), flags],
    text: [vector(words, new arrow.Utf8()), words],
    large: [vector(words, new arrow.LargeUtf8()), words],
    coded: [vector(words, new arrow.Dictionary(new arrow.Utf8(), new arrow.Int8())), words],
    day: [vector(days, new arrow.DateDay()), days.map((v) => (v == null ? null : iso(v, false).slice(0, 10)))],
    date: [vector(days, new arrow.DateMillisecond()), days.map((v) => (v == null ? null : iso(v, false).slice(0, 10)))],
    seconds: [vector(times.map((v) => (v == null ? null : Math.floor(v / 1000) * 1000)), new arrow.TimestampSecond()), times.map((v) => (v == null ? null : iso(Math.floor(v / 1000) * 1000, false)))],
    millis: [vector(times, new arrow.TimestampMillisecond("UTC")), times.map((v) => (v == null ? null : iso(v, true)))],
    micros: [vector(times, new arrow.TimestampMicrosecond()), times.map((v) => (v == null ? null : iso(v, false)))],
    nanos: [vector(times, new arrow.TimestampNanosecond("Asia/Tokyo")), times.map((v) => (v == null ? null : iso(v, true)))],
    nothing: [vector(Array(n).fill(null), new arrow.Null()), Array(n).fill(null)],
    list: [vector(ints.map((v) => (v == null ? null : [v, v])), new arrow.List(new arrow.Field("item", new arrow.Int32()))), undefined],
    pair: [vector(ints.map((v) => (v == null ? null : { p: v, q: "s" })), new arrow.Struct([new arrow.Field("p", new arrow.Int32()), new arrow.Field("q", new arrow.Utf8())])), undefined],
    blob: [vector(ints.map((v) => (v == null ? null : Uint8Array.of(1, 2))), new arrow.Binary()), undefined],
  };
  return columns;
}
// A table of `vectors` by name, with `metadata` on the fields named and on the schema.
function tableWith(vectors, fieldMetadata = {}, schemaMetadata = new Map()) {
  const t = new arrow.Table(vectors);
  const fields = t.schema.fields.map((f) => (fieldMetadata[f.name] ? f.clone({ metadata: new Map(Object.entries(fieldMetadata[f.name])) }) : f));
  const schema = new arrow.Schema(fields, schemaMetadata);
  return new arrow.Table(schema, t.batches.map((b) => new arrow.RecordBatch(schema, b.data)));
}
const point2 = new arrow.FixedSizeList(2, new arrow.Field("xy", new arrow.Float64(), false));
const point3 = new arrow.FixedSizeList(3, new arrow.Field("xyz", new arrow.Float64(), false));
const pointStruct = new arrow.Struct([new arrow.Field("x", new arrow.Float64(), false), new arrow.Field("y", new arrow.Float64(), false)]);
const listOf = (child, name) => new arrow.List(new arrow.Field(name, child, false));
// GeoArrow types by name over a point type, and how coordinates nest in them.
const geoType = (name, point) =>
  ({ point, linestring: listOf(point, "vertices"), multipoint: listOf(point, "points"), polygon: listOf(listOf(point, "vertices"), "rings"),
    multilinestring: listOf(listOf(point, "vertices"), "linestrings"), multipolygon: listOf(listOf(listOf(point, "vertices"), "rings"), "polygons") })[name];
const deep = (c, f) => (typeof c[0] === "number" ? f(c) : c.map((x) => deep(x, f)));

for (let k = 0; k < TABLES; k++) {
  const rows = pick([1, 2, 7, 90]);
  const columns = typed(rows);
  const type = Object.keys(SHAPES)[k % 6];
  const geometries = Array.from({ length: rows }, () => geometryOf(random() < 0.15 ? null : type));
  const encoding = pick(["wkb", "wkb named", "wkb geo", "interleaved", "xyz", "separated", "none"]);
  const vectors = Object.fromEntries(Object.entries(columns).map(([name, [v]]) => [name, v]));
  const metadata = {};
  let schemaMetadata = new Map();
  let column = "geom";
  const coords = geometries.map((g) => g?.coordinates ?? null);
  if (encoding.startsWith("wkb")) {
    const cells = geometries.map((g) => (g ? new Uint8Array(wkx.Geometry.parseGeoJSON(g).toWkb()) : null));
    if (encoding === "wkb named") column = "GEOMETRY";
    vectors[column] = arrow.vectorFromArray(cells, random() < 0.5 ? new arrow.Binary() : new arrow.LargeBinary());
    if (encoding === "wkb") metadata[column] = { "ARROW:extension:name": "geoarrow.wkb", "ARROW:extension:metadata": '{"crs":"EPSG:4326"}' };
    if (encoding === "wkb geo") schemaMetadata = new Map([["geo", JSON.stringify({ version: "1.0.0", primary_column: column, columns: { [column]: { encoding: "WKB" } } })]]);
  } else if (encoding !== "none") {
    const point = { interleaved: point2, xyz: point3, separated: pointStruct }[encoding];
    const shape = { interleaved: (p) => p, xyz: (p) => [...p, 9], separated: ([x, y]) => ({ x, y }) }[encoding];
    vectors[column] = arrow.vectorFromArray(coords.map((c) => (c ? deep(c, shape) : null)), geoType(type.toLowerCase(), point));
    metadata[column] = { "ARROW:extension:name": `geoarrow.${type.toLowerCase()}` };
  }
  let t = tableWith(vectors, metadata, schemaMetadata);
  // Two record batches now and then: the rows follow one another.
  const twice = random() < 0.4;
  if (twice) t = new arrow.Table(t.schema, [...t.batches, ...t.batches]);
  const label = `arrow table ${k} (${rows} rows, ${type} as ${encoding}${twice ? ", two batches" : ""})`;
  for (const format of ["stream", "file", "stream lz4", "file lz4"]) {
    let got;
    try {
      got = read(arrow.tableToIPC(t, format.split(" ")[0], format.endsWith("lz4") ? arrow.CompressionType.LZ4_FRAME : null));
    } catch (e) {
      check("read", `${label} ${format}`, "read", e.message);
      continue;
    }
    const all = twice ? [...geometries, ...geometries] : geometries;
    check("read", `${label} ${format} rows`, all.length, got.features.length);
    check("read", `${label} ${format} geometry column`, encoding === "none" ? "" : column, got.geometry);
    check("read", `${label} ${format} geometry`, json(encoding === "none" ? all.map(() => null) : all), json(got.features.map((f) => f.geometry)));
    for (const [name, [, want]] of Object.entries(columns)) {
      const values = got.features.map((f) => f.properties[name]);
      if (want === undefined) check("read", `${label} ${format} ${name} left out`, "true", String(values.every((v) => v === undefined)));
      else if (want === null) check("read", `${label} ${format} ${name}`, json(Array.from({ length: all.length }, (_, i) => columns[name][0].get(i % rows))), json(values.map((v) => v ?? null)));
      else check("read", `${label} ${format} ${name}`, json(twice ? [...want, ...want] : want), json(values.map((v) => v ?? null)));
    }
  }
}

// Damaged input: cut anywhere or with bytes changed, it is refused or read, never a trap.
const sample = write(tableOf(makeFeatures(["Polygon", "MultiPolygon"], 12)), 0);
const native = write(tableOf(makeFeatures(["LineString"], 12)), FLAGS.native | FLAGS.file);
const foreign = arrow.tableToIPC(tableWith(Object.fromEntries(Object.entries(typed(9)).map(([name, [v]]) => [name, v]))), "file");
const packed = arrow.tableToIPC(tableWith(Object.fromEntries(Object.entries(typed(40)).map(([name, [v]]) => [name, v]))), "stream", arrow.CompressionType.LZ4_FRAME);
function survives(bytes) {
  try {
    read(bytes);
    return true;
  } catch (e) {
    return !(e instanceof WebAssembly.RuntimeError) && !(e instanceof RangeError);
  }
}
for (const [name, bytes] of [["wkb stream", sample], ["native file", native], ["apache-arrow file", foreign], ["apache-arrow LZ4 stream", packed]]) {
  let trapped = 0;
  for (let cut = 0; cut < bytes.length; cut += 1 + int(7)) if (!survives(bytes.subarray(0, cut))) trapped++;
  check("damaged", `${name} cut short`, 0, trapped);
  trapped = 0;
  for (let i = 0; i < 4000; i++) {
    const damaged = bytes.slice();
    for (let n = 1 + int(3); n > 0; n--) damaged[int(damaged.length)] = pick([0, 1, 0x7f, 0x80, 0xff, int(256)]);
    if (!survives(damaged)) trapped++;
  }
  check("damaged", `${name} bytes changed`, 0, trapped);
}
const refusal = (bytes) => {
  try {
    read(bytes);
    return "";
  } catch (e) {
    return e.message;
  }
};
check("refused", "no schema", "true", String(/no schema/.test(refusal(new Uint8Array(0)))));
check("refused", "text", "true", String(/^malformed Arrow at/.test(refusal(encoder.encode("not an arrow file at all")))));

console.table(Object.entries(results).map(([group, r]) => ({ group, cases: r.cases, differ: r.differ })));
if (failures.length) console.log(JSON.stringify(failures, null, 1));
await writeFile(path.join(ROOT, "bench/results/arrow-golden.json"), `${JSON.stringify({ "apache-arrow": "21.2.0", wkx: "0.5.0", tables: TABLES, results }, null, 2)}\n`);
const differ = Object.values(results).reduce((n, r) => n + r.differ, 0);
console.log(differ === 0 ? "0 differ" : `${differ} differ`);
process.exit(differ === 0 ? 0 : 1);
