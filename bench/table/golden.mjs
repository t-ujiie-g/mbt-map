// table.wasm vs Arquero 8.0.3 on seeded random tables (select, filter, derive, orderby, slice, rows by number as
// reify, a column as array): the rows, their order, the columns' order and every value must be the same.
// Usage: node table/golden.mjs [--tables=N]; writes bench/results/table-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import * as aq from "arquero";
import { hostNumber, hostText } from "../../wasmio/js/host.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { readValue } from "../../worker/js/values.mjs";
import { Packer } from "../../npm/src/pack.ts";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const TABLES = Number(arg("tables", 60));
const wasmOf = async (name, imports) =>
  (await WebAssembly.instantiate(await readFile(path.join(ROOT, `_build/wasm-gc/release/build/t-ujiie-g/mbtmap_engine/${name}/${name}.wasm`)), imports)).instance.exports;
let a;
a = await wasmOf("analysis_worker", { Math, host: { number: hostNumber(() => a.memory) } });
const t = await wasmOf("table_worker", { Math, host: hostText() });
const decoder = new TextDecoder();
const encoder = new TextEncoder();
function put(e, parts) {
  let at = e.prepare_input(parts.reduce((n, p) => n + p.length, 0));
  for (const p of parts) {
    new Uint8Array(e.memory.buffer, at, p.length).set(p);
    at += p.length;
  }
}
function out(e, n) {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
}

// Seeded xorshift32, so that every run compares the same tables.
let seed = 0x2f6e2b1;
function random() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return (seed >>> 0) / 4294967296;
}
const int = (n) => Math.floor(random() * n);
const pick = (xs) => xs[int(xs.length)];
const WORDS = ["", "a", "aa", "b", "B", "park", "Park", "school", "é", "東京", "😀", "10", "9", "z z"];
// A cell: mostly a value of the column's kind, sometimes null, sometimes no key at all (undefined).
const cell = (make) => (random() < 0.12 ? null : random() < 0.1 ? undefined : make());
const COLUMNS = {
  n: () => cell(() => pick([0, 1, 2, 2, 3.5, -7, 1e21, 0.1 + 0.2, int(20)])),
  s: () => cell(() => pick(WORDS)),
  b: () => cell(() => random() < 0.5),
  m: () => cell(() => (random() < 0.5 ? int(4) : random() < 0.5)),
};

function makeRows() {
  const names = Object.keys(COLUMNS).filter(() => random() < 0.85);
  return Array.from({ length: pick([0, 1, 2, 7, 40, 200]) }, (_, i) => {
    const row = { i };
    for (const name of names) {
      const v = COLUMNS[name]();
      if (v !== undefined) row[name] = v;
    }
    return row;
  });
}
// Rows as table bytes, each with a point, read as `load` reads GeoJSON.
function tableOf(rows) {
  const features = rows.map((properties, i) => ({ type: "Feature", properties, geometry: { type: "Point", coordinates: [i, -i] } }));
  put(a, [encoder.encode(JSON.stringify({ type: "FeatureCollection", features }))]);
  const id = a.load();
  if (id < 0) throw new Error("load failed");
  const bytes = out(a, a.table_out(id));
  a.dispose(id);
  return bytes;
}
// A table_worker export over table bytes and packed arguments: the rows' properties, their points and the columns.
function run(bytes, fn, args = new ArrayBuffer(0), ...numbers) {
  put(t, [bytes, new Uint8Array(args)]);
  const result = out(t, t[fn](bytes.length, ...numbers));
  const { features } = tableToGeoJSON(result);
  put(t, [result]);
  const kinds = new Int32Array(out(t, t.kinds() * 4).buffer);
  return { rows: features.map((f) => f.properties), points: features.map((f) => f.geometry.coordinates[0]), columns: kinds.length / 5, bytes: result };
}

const results = {};
const failures = [];
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, differ: 0 });
  r.cases++;
  if (want === got) return;
  r.differ++;
  if (failures.length < 20) failures.push({ group, label, want: want.slice(0, 300), got: got.slice(0, 300) });
}
// Rows as text that tells a missing key from null and keeps the keys' order (GeoJSON holds no -0 or NaN).
const show = (rows, columns) => JSON.stringify(rows.map((row) => columns.map((c) => (row[c] === undefined ? "absent" : row[c]))));
// An Arquero table of `rows` with `columns` whatever the first row holds.
const frame = (rows, columns) => aq.table(Object.fromEntries(columns.map((c) => [c, rows.map((row) => row[c])])));
function compare(group, label, theirs, ours) {
  const columns = theirs.columnNames();
  check(group, label, show(theirs.objects(), columns), show(ours.rows, columns));
  // The rows' points follow them: each row's `i` is its point's x.
  if (columns.includes("i")) check(group, `${label} geometry`, JSON.stringify(theirs.array("i")), JSON.stringify(ours.points));
}
const number = (v) => typeof v === "number";

for (let k = 0; k < TABLES; k++) {
  const rows = makeRows();
  const columns = rows.length === 0 ? [] : ["i", ...Object.keys(COLUMNS).filter((c) => rows.some((row) => c in row))];
  const bytes = tableOf(rows);
  const theirs = frame(rows, columns);
  const label = `table ${k} (${rows.length} rows)`;

  const chosen = columns.filter(() => random() < 0.6).sort(() => random() - 0.5);
  const names = new Packer().u32(chosen.length);
  for (const c of chosen) names.utf8(c);
  const selected = run(bytes, "select", names.finish());
  // Arquero's table without columns has no rows; ours keeps them, for their geometry.
  if (chosen.length === 0) check("select", `${label} no columns`, String(rows.length), String(selected.rows.length));
  else compare("select", `${label} ${chosen}`, theirs.select(chosen), selected);

  const threshold = int(5);
  const word = pick(WORDS);
  const some = [pick(WORDS), pick(WORDS), pick(WORDS)];
  const FILTERS = [
    [[">", ["get", "n"], threshold], (d) => number(d.n) && d.n > threshold],
    [["==", ["get", "s"], word], (d) => d.s === word],
    [["all", ["has", "n"], ["<=", ["to-number", ["get", "n"], 0], threshold]], (d) => d.n !== undefined && Number(d.n ?? 0) <= threshold],
    [["in", ["get", "s"], ["literal", some]], (d) => some.includes(d.s)],
    [["==", ["get", "b"], true], (d) => d.b === true],
    [["any", ["==", ["typeof", ["get", "m"]], "boolean"], ["==", ["get", "m"], null]], (d) => typeof d.m === "boolean" || d.m == null],
    [true, () => true],
    [["get", "n"], () => false],
  ];
  for (const [expression, test] of FILTERS) {
    compare("filter", `${label} ${JSON.stringify(expression)}`, theirs.filter(aq.escape(test)), run(bytes, "filter", new Packer().json(expression).finish()));
  }

  const given = rows.map(() => cell(() => pick([1, "x", true])));
  const DERIVED = [
    ["double", 0, ["*", ["get", "n"], 2], (d) => (number(d.n) ? d.n * 2 : null)],
    ["s", 0, ["upcase", ["to-string", ["get", "s"]]], (d) => (d.s == null ? "" : d.s.toUpperCase())],
    ["given", 1, given, null],
    ["label", 0, ["concat", ["get", "i"], "-", ["coalesce", ["get", "s"], "?"]], (d) => `${d.i}-${d.s ?? "?"}`],
  ];
  const derive = new Packer().u32(DERIVED.length);
  let derived = theirs;
  for (const [name, kind, how, js] of DERIVED) {
    derive.utf8(name).u8(kind);
    if (kind === 0) derive.json(how);
    else {
      derive.u32(how.length);
      for (const v of how) derive.value(v);
    }
    derived = kind === 0 ? derived.derive({ [name]: aq.escape((d) => js(rows[d.i])) }) : derived.assign({ [name]: how });
  }
  const ourDerived = run(bytes, "derive", derive.finish());
  compare("derive", label, derived, ourDerived);
  check("derive", `${label} columns`, String(derived.columnNames().length), String(ourDerived.columns));

  const c0 = int(4);
  const ORDERS = [
    [["n"], [(d) => d.n]],
    [[{ by: "n", descending: true }], [aq.desc("n")]],
    [["s"], ["s"]],
    [[{ by: "s", descending: true }, "n"], [aq.desc("s"), "n"]],
    [["b", { by: "m", descending: true }], ["b", aq.desc("m")]],
    [["m", "s", "n"], ["m", "s", "n"]],
    [[["/", ["-", ["get", "n"], c0], ["-", ["get", "n"], c0]], "s"], [aq.escape((d) => (number(d.n) ? (d.n - c0) / (d.n - c0) : null)), "s"]],
    [[["length", ["to-string", ["get", "s"]]]], [aq.escape((d) => (d.s == null ? 0 : d.s.length))]],
  ];
  for (const [keys, arquero] of ORDERS) {
    if (!keys.flat().every((key) => typeof key !== "string" || columns.includes(key)) || keys.some((key) => key.by && !columns.includes(key.by))) continue;
    const order = new Packer().u32(keys.length);
    for (const key of keys) {
      const by = key.by ?? key;
      order.u8(key.descending ? 1 : 0).json(typeof by === "string" ? ["get", by] : by);
    }
    compare("orderby", `${label} ${JSON.stringify(keys)}`, theirs.orderby(...arquero), run(bytes, "orderby", order.finish()));
  }

  for (const [start, end] of [[0, rows.length], [1, 3], [int(rows.length + 2), int(rows.length + 5)], [5, 2]]) {
    compare("slice", `${label} ${start}..${end}`, theirs.slice(start, end), run(bytes, "slice", undefined, start, end));
  }
  if (rows.length > 0) {
    const taken = Uint32Array.from({ length: int(12) }, () => int(rows.length));
    compare("rows by number", `${label} ${Array.from(taken)}`, theirs.reify(taken), run(bytes, "take", taken.buffer));
  }

  for (const c of columns) {
    put(t, [bytes, encoder.encode(c)]);
    const cells = out(t, t.column(bytes.length));
    const view = new DataView(cells.buffer);
    const values = [];
    for (let at = 0; at < cells.length; ) {
      let v;
      [v, at] = readValue(view, cells, at);
      values.push(v);
    }
    check("array", `${label} ${c}`, show(theirs.objects(), [c]), show(values.map((v) => ({ [c]: v })), [c]));
  }
}

// What the module refuses, by its message.
const one = tableOf([{ i: 0, n: 1 }]);
const refused = (fn, args, ...numbers) => {
  try {
    run(one, fn, args, ...numbers);
    return "";
  } catch (e) {
    return e.message;
  }
};
const REFUSED = [
  ["an unknown column", refused("select", new Packer().u32(1).utf8("x").finish()), "no column x"],
  ["a column twice", refused("select", new Packer().u32(2).utf8("n").utf8("n").finish()), "a column selected twice"],
  ["an unknown operator", refused("filter", new Packer().json(["nope", 1]).finish()), /nope/],
  ["a cut expression", refused("filter", new Uint8Array([5, 9, 0, 0, 0]).buffer), "malformed expression"],
  ["nesting past the cap", refused("filter", new Packer().json(Array.from({ length: 80 }).reduce((e) => ["!", e], true)).finish()), /malformed expression|expression/],
  ["a row out of the table", refused("take", Uint32Array.of(0, 1).buffer), "a row out of the table"],
  ["given values of another length", refused("derive", new Packer().u32(1).utf8("x").u8(1).u32(2).value(1).value(2).finish()), "2 values for x in a table of 1 rows"],
  ["a derived column's bad expression", refused("derive", new Packer().u32(1).utf8("x").u8(0).json(["nope"]).finish()), /^x: /],
  ["malformed table bytes", (() => { try { put(t, [one.subarray(0, 9)]); out(t, t.select(9)); return ""; } catch (e) { return e.message; } })(), "malformed table"],
];
for (const [label, got, want] of REFUSED) {
  check("refused", label, "true", String(want instanceof RegExp ? want.test(got) : got === want));
}

console.table(Object.entries(results).map(([group, r]) => ({ group, cases: r.cases, differ: r.differ })));
if (failures.length) console.log(JSON.stringify(failures, null, 1));
await writeFile(path.join(ROOT, "bench/results/table-golden.json"), `${JSON.stringify({ arquero: "8.0.3", tables: TABLES, results }, null, 2)}\n`);
const differ = Object.values(results).reduce((n, r) => n + r.differ, 0);
console.log(differ === 0 ? "0 differ" : `${differ} differ`);
process.exit(differ === 0 ? 0 : 1);
