// parquet.wasm (with zstd.wasm) vs files pyarrow wrote (bench/table/parquet/, their rows from
// bench/data/parquet-fixtures.py) and vs hyparquet 1.33.1 on files hyparquet-writer 0.18.0 writes; damaged input must not trap.
// Usage: node table/parquet-golden.mjs [--tables=N]; writes bench/results/parquet-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { parquetReadObjects } from "hyparquet";
import { parquetWriteBuffer } from "hyparquet-writer";
import { hostText, writeInput } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { readParquet } from "../../data_worker/js/arrow.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const TABLES = Number(arg("tables", 30));
const DIR = path.join(ROOT, "bench/table/parquet");
const BUILD = path.join(ROOT, "_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine");
const z = (await WebAssembly.instantiate(await readFile(path.join(BUILD, "zstd_worker/zstd_worker.wasm")), {})).instance.exports;
const w = (await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine/parquet_worker/parquet_worker.wasm")), { Math, host: hostText() })).instance.exports;
const decoder = new TextDecoder();
function output(e, n) {
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(e.memory.buffer, e.output_addr(), -n)));
  return e.memory.buffer.slice(e.output_addr(), e.output_addr() + n);
}
// A Parquet file read as the data worker reads it: the rows as GeoJSON features and the CRS its geometry names.
async function read(bytes) {
  const { table, crs } = await readParquet(w, bytes, {}, { writeInput, output }, async () => z);
  return { features: tableToGeoJSON(new Uint8Array(table)).features, crs: crs ?? null };
}

const results = {};
const failures = [];
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, differ: 0 });
  r.cases++;
  if (want === got) return;
  r.differ++;
  if (failures.length < 12) failures.push({ group, label, want: String(want).slice(0, 300), got: String(got).slice(0, 300) });
}
const json = (v) => JSON.stringify(v, (_, x) => (typeof x === "bigint" ? Number(x) : x));
// Decimals past 2^53 are summed byte by byte: the last digits of the double may differ.
const close = (a, b) => a === b || (typeof a === "number" && typeof b === "number" && Math.abs(a - b) <= Math.abs(a) * 1e-14);

const expected = JSON.parse(await readFile(path.join(DIR, "expected.json"), "utf8"));
for (const [name, file] of Object.entries(expected.files)) {
  const bytes = new Uint8Array(await readFile(path.join(DIR, `${name}.parquet`)));
  if (file.refused) {
    const message = await read(bytes).then(() => "", (e) => e.message);
    check("refused", name, "true", String(message.includes(file.refused)));
    continue;
  }
  let got;
  try {
    got = await read(bytes);
  } catch (e) {
    check("pyarrow", name, "read", e.message);
    continue;
  }
  const rows = expected.data[file.rows];
  check("pyarrow", `${name} rows`, file.rows, got.features.length);
  check("pyarrow", `${name} crs`, file.crs, got.crs);
  check("pyarrow", `${name} geometry`, json(rows.map((r) => (file.geometry ? r.geometry : null))), json(got.features.map((f) => f.geometry)));
  check("pyarrow", `${name} columns`, json(file.rows === 0 ? [] : file.columns), json(Object.keys(got.features[0]?.properties ?? {})));
  for (const column of file.columns) {
    const want = rows.map((r) => r.properties[column]);
    const have = got.features.map((f) => f.properties[column]);
    if (column === "huge") check("pyarrow", `${name} ${column}`, "true", String(want.length === have.length && want.every((v, i) => close(v, have[i]))));
    else check("pyarrow", `${name} ${column}`, json(want), json(have));
  }
}

// Seeded xorshift32, so that every run compares the same tables.
let seed = 0x9a2c3f1;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 4294967296;
}
const int = (n) => Math.floor(random() * n);
const pick = (xs) => xs[int(xs.length)];
const WORDS = ["", "a", "park", "é", "東京", "😀", "10", "a longer word"];
for (let k = 0; k < TABLES; k++) {
  const n = pick([0, 1, 3, 50, 2000]);
  const cells = (make, nulls = true) => Array.from({ length: n }, () => (nulls && random() < 0.15 ? null : make()));
  const columnData = [
    { name: "name", data: cells(() => pick(WORDS)), type: "STRING" },
    { name: "n", data: cells(() => int(1000) - 500), type: "INT32" },
    { name: "big", data: cells(() => BigInt(int(2 ** 31)) * 1000n), type: "INT64" },
    { name: "x", data: cells(() => pick([0.5, -2.25, 1e10, int(9)])), type: "DOUBLE" },
    { name: "f", data: cells(() => Math.fround(random())), type: "FLOAT" },
    { name: "ok", data: cells(() => random() < 0.5), type: "BOOLEAN" },
    { name: "required", data: cells(() => int(5), false), type: "INT32", nullable: false },
  ].filter(() => random() < 0.9);
  if (columnData.length === 0) continue;
  const codec = pick(["SNAPPY", "UNCOMPRESSED"]);
  const buffer = parquetWriteBuffer({ columnData, codec, rowGroupSize: pick([100000, 700, 64]), statistics: random() < 0.5 });
  const label = `table ${k} (${n} rows, ${codec})`;
  const want = await parquetReadObjects({ file: buffer });
  let got;
  try {
    got = await read(new Uint8Array(buffer));
  } catch (e) {
    check("hyparquet", label, "read", e.message);
    continue;
  }
  check("hyparquet", label, json(want), json(got.features.map((f) => f.properties)));
}

// Damaged input: cut anywhere or with bytes changed, it is refused or read, never a trap.
async function survives(bytes) {
  try {
    await read(bytes);
    return true;
  } catch (e) {
    return !(e instanceof WebAssembly.RuntimeError) && !(e instanceof RangeError);
  }
}
for (const name of ["small-pages", "delta", "pages-v2-plain", "split", "zstd"]) {
  const bytes = new Uint8Array(await readFile(path.join(DIR, `${name}.parquet`)));
  let trapped = 0;
  for (let cut = 0; cut < bytes.length; cut += 1 + int(bytes.length / 300)) if (!(await survives(bytes.subarray(0, cut)))) trapped++;
  check("damaged", `${name} cut short`, 0, trapped);
  trapped = 0;
  for (let i = 0; i < 1500; i++) {
    const damaged = bytes.slice();
    // Half of the changes in the footer, where every structure is.
    const from = i % 2 ? 0 : Math.max(0, damaged.length - 4000);
    for (let m = 1 + int(3); m > 0; m--) damaged[from + int(damaged.length - from)] = pick([0, 1, 0x7f, 0x80, 0xff, int(256)]);
    if (!(await survives(damaged))) trapped++;
  }
  check("damaged", `${name} bytes changed`, 0, trapped);
}
const refusal = (bytes) => read(bytes).then(() => "", (e) => e.message);
check("refused", "no file", "true", String(/not a Parquet file/.test(await refusal(new Uint8Array(0)))));
check("refused", "text", "true", String(/^malformed Parquet at/.test(await refusal(new TextEncoder().encode("PAR1 is not all it takes PAR1")))));

console.table(Object.entries(results).map(([group, r]) => ({ group, cases: r.cases, differ: r.differ })));
if (failures.length) console.log(JSON.stringify(failures, null, 1));
await writeFile(path.join(ROOT, "bench/results/parquet-golden.json"), `${JSON.stringify({ pyarrow: "23.0.1", hyparquet: "1.33.1", "hyparquet-writer": "0.18.0", tables: TABLES, results }, null, 2)}\n`);
const differ = Object.values(results).reduce((sum, r) => sum + r.differ, 0);
console.log(differ === 0 ? "0 differ" : `${differ} differ`);
process.exit(differ === 0 ? 0 : 1);
