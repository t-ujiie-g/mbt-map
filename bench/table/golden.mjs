// table.wasm vs Arquero 8.0.3 on seeded random tables (select, filter, derive, orderby, slice, rows by number as
// reify, a column as array, rollup, join): the rows, their order, the columns' order and every value must match.
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
  const tables = Array.isArray(bytes) ? bytes : [bytes];
  put(t, [...tables, new Uint8Array(args)]);
  const result = out(t, t[fn](...tables.map((b) => b.length), ...numbers));
  const { features } = tableToGeoJSON(result);
  put(t, [result]);
  const kinds = new Int32Array(out(t, t.kinds() * 4).buffer);
  return { rows: features.map((f) => f.properties), points: features.map((f) => f.geometry?.coordinates[0] ?? null), columns: kinds.length / 5, bytes: result };
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
// Aggregates hold null where Arquero gives undefined or NaN, and groupby takes a missing key as null.
const orNull = (v) => (v === undefined || Number.isNaN(v) ? null : v);
const nulled = (rows, columns) => rows.map((row) => Object.fromEntries(columns.map((c) => [c, orNull(row[c])])));
// A rollup's arguments as mbt-map/table packs them (`AGGREGATES` there has the aggregates' codes).
const CODES = ["count", "valid", "distinct", "sum", "mean", "min", "max", "median", "any", "variance", "stdev", "quantile", "mode", "product"];
function rollupArgs(keys, outputs) {
  const p = new Packer().u32(keys.length);
  for (const [name, value] of keys) p.utf8(name).json(value);
  p.u32(outputs.length);
  for (const [name, [op, value = null, fraction = 0.5]] of outputs) p.utf8(name).u8(CODES.indexOf(op)).f64(fraction).json(value);
  return p.finish();
}
function joinArgs(pairs, left = false, suffix = ["_1", "_2"]) {
  const p = new Packer().u8(left ? 1 : 0).utf8(suffix[0]).utf8(suffix[1]).u32(pairs.length);
  for (const [l, r] of pairs) p.utf8(l).utf8(r);
  return p.finish();
}
const AGGREGATES = ["valid", "distinct", "sum", "mean", "min", "max", "median", "any", "variance", "stdev", "mode", "product"];
// The rows a table joins: keys as the first table's, `b` to clash with its column, `v` and `j` of their own.
function makeOthers() {
  const names = ["s", "n", "m", "b"].filter(() => random() < 0.85);
  return Array.from({ length: pick([0, 1, 3, 30, 300]) }, (_, j) => {
    const row = { j, v: int(100) };
    for (const name of names) {
      const v = COLUMNS[name]();
      if (v !== undefined) row[name] = v;
    }
    return row;
  });
}

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

  // The doubled `n` as a column, for Arquero to sum what ours computes per row.
  const whole = frame(nulled(rows, columns), columns).derive({ doubled: aq.escape((d) => (number(d.n) ? d.n * 2 : null)) });
  const c1 = int(3);
  const GROUPS = [
    [[], []],
    [[["s", "s"]], ["s"]],
    [[["b", "b"]], ["b"]],
    [[["m", "m"]], ["m"]],
    [[["n", "n"]], ["n"]],
    [[["s", "s"], ["b", "b"]], ["s", "b"]],
    [[["m", "m"], ["n", "n"], ["s", "s"]], ["m", "n", "s"]],
    [[["big", [">", ["get", "n"], c1]]], [{ big: aq.escape((d) => (number(d.n) ? d.n > c1 : null)) }]],
  ];
  const fractions = [0, 0.25, random(), 1, 1.5];
  const values = columns.filter((c) => c !== "i");
  for (const [keys, arquero] of rows.length === 0 ? [] : GROUPS) {
    if (!keys.every(([name, value]) => name === "big" || columns.includes(value)) || (keys[0]?.[0] === "big" && !columns.includes("n"))) continue;
    const outputs = [["rows", ["count"]]];
    const ops = { rows: aq.op.count() };
    for (const c of values) {
      for (const name of AGGREGATES) {
        outputs.push([`${name} ${c}`, [name, c]]);
        ops[`${name} ${c}`] = aq.op[name](c);
      }
      fractions.forEach((p, k) => {
        outputs.push([`q${k} ${c}`, ["quantile", c, p]]);
        ops[`q${k} ${c}`] = aq.op.quantile(c, p);
      });
    }
    if (columns.includes("n")) {
      outputs.push(["computed", ["sum", ["*", ["get", "n"], 2]]]);
      ops.computed = aq.op.sum("doubled");
    }
    const grouped = keys.length ? whole.groupby(...arquero) : whole;
    const want = grouped.rollup(ops);
    const got = run(bytes, "rollup", rollupArgs(keys, outputs));
    const names = want.columnNames();
    check("rollup", `${label} by ${keys.map((key) => key[0])}`, show(nulled(want.objects(), names), names), show(got.rows, names));
    check("rollup", `${label} by ${keys.map((key) => key[0])} columns`, String(names.length), String(got.columns));
  }

  const others = makeOthers();
  const otherColumns = others.length === 0 ? [] : ["j", "v", ...["s", "n", "m", "b"].filter((c) => others.some((row) => c in row))];
  const otherBytes = tableOf(others);
  const right = frame(others, otherColumns);
  const JOINS = [
    ["s", ["s"], ["s"]],
    [["n", "m"], ["n"], ["m"]],
    [["m", "n"], ["m"], ["n"]],
    [[["s", "b"], ["s", "b"]], ["s", "b"], ["s", "b"]],
    [[["s", "m"], ["s", "n"]], ["s", "m"], ["s", "n"]],
    [[["m"]], ["m"], ["m"]],
    [null, null, null],
  ];
  for (const [on, l, r] of JOINS) {
    const shared = columns.filter((c) => otherColumns.includes(c));
    if (on === null ? shared.length === 0 : !l.every((c) => columns.includes(c)) || !r.every((c) => otherColumns.includes(c))) continue;
    const pairs = (l ?? shared).map((c, k) => [c, (r ?? shared)[k]]);
    for (const left of [false, true]) {
      const suffix = random() < 0.2 ? ["", "#"] : undefined;
      const want = theirs.join(right, on ?? undefined, undefined, { left, suffix });
      const got = run([bytes, otherBytes], "join", joinArgs(pairs, left, suffix));
      compare("join", `${label} with ${others.length} on ${JSON.stringify(on)}${left ? " left" : ""}`, want, got);
      if (got.rows.length > 0) check("join", `${label} on ${JSON.stringify(on)} columns`, String(want.columnNames().length), String(got.columns));
    }
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
    run(fn === "join" || fn === "pairs" ? [one, numbers.pop() ?? one] : one, fn, args, ...numbers);
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
  ["an aggregate of an unknown column", refused("rollup", rollupArgs([], [["x", ["sum", "y"]]])), "x: no column y"],
  ["a group key that is no column", refused("rollup", rollupArgs([["y", "y"]], [])), "y: no column y"],
  ["an aggregate's bad expression", refused("rollup", rollupArgs([], [["x", ["sum", ["nope"]]]])), /^x: .*nope/],
  ["a cut rollup", refused("rollup", new Packer().u32(1).utf8("x").finish()), "malformed values"],
  ["a pair out of the tables", refused("pairs", new Packer().u8(0).utf8("_1").utf8("_2").u32(2).bytes(Int32Array.of(0, 1)).finish()), "a pair out of the tables"],
  ["half a pair", refused("pairs", new Packer().u8(1).utf8("_1").utf8("_2").u32(1).bytes(Int32Array.of(0)).finish()), "a pair out of the tables"],
  ["more pairs than bytes", refused("pairs", new Packer().u8(0).utf8("_1").utf8("_2").u32(9).finish()), "malformed pairs"],
  ["a pair rollup's unknown column", refused("pairs", rollupArgs([], [["x", ["sum", "y"]]]).slice(4) && new Packer().u8(2).utf8("_1").utf8("_2").u32(0).bytes(new Uint8Array(rollupArgs([], [["x", ["sum", "y"]]]).slice(4))).finish()), "x: no column y"],
  ["a join on a column one table lacks", refused("join", joinArgs([["i", "i"]]), tableOf([{ n: 1 }])), "no column i"],
  ["a join on no key", refused("join", joinArgs([])), "no key to join on"],
  ["a join giving a name twice", refused("join", joinArgs([["i", "i"]], false, ["", ""])), "a column twice in the joined table"],
  ["a join with a negative count of keys", refused("join", new Packer().u8(0).utf8("_1").utf8("_2").u32(0xffffffff).finish()), "malformed join"],
  ["a cut join", refused("join", new Packer().u8(0).utf8("_1").finish()), "malformed join"],
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
