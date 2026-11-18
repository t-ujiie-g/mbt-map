import assert from "node:assert/strict";
import test from "node:test";
import { crsCode, readArrow, writeArrow } from "./arrow.mjs";

test("crsCode: an EPSG code from a string or PROJJSON's id, none for longitude and latitude", () => {
  assert.equal(crsCode(undefined), undefined);
  assert.equal(crsCode(null), undefined);
  assert.equal(crsCode("OGC:CRS84"), undefined);
  assert.equal(crsCode("EPSG:4326"), undefined);
  assert.equal(crsCode(" epsg:6677 "), 6677);
  assert.equal(crsCode({ type: "ProjectedCRS", id: { authority: "EPSG", code: 6677 } }), 6677);
  assert.equal(crsCode({ id: { authority: "EPSG", code: "3857" } }), 3857);
  assert.equal(crsCode({ id: { authority: "OGC", code: "CRS84" } }), undefined);
});

test("crsCode: a CRS that names no EPSG code throws", () => {
  for (const crs of ['PROJCRS["x"]', "+proj=utm +zone=54", "EPSG:abc", "ESRI:102100", {}, { id: { authority: "IAU", code: 30100 } }, 6677]) {
    assert.throws(() => crsCode(crs), /names no EPSG code; give options.crs/);
  }
});

// A wasm whose `read` gives table bytes [1, 2] and whose `info_out` gives the three strings; `write` gives its flags.
function fake(strings) {
  const encoder = new TextEncoder();
  const info = strings.flatMap((s) => {
    const b = encoder.encode(s);
    return [...new Uint8Array(Uint32Array.of(b.length).buffer), ...b];
  });
  return { read: () => "table", info_out: () => "info", write: (flags) => flags, info };
}
const io = (wasm, seen) => ({
  writeInput: (w, parts) => seen.push(parts),
  output: (w, n) => (n === "table" ? Uint8Array.of(1, 2).buffer : n === "info" ? Uint8Array.from(wasm.info).buffer : n),
});

test("readArrow: the table and the CRS of the geometry column, the extension's before the geo metadata's", () => {
  const geo = JSON.stringify({ primary_column: "g", columns: { g: { crs: { id: { authority: "EPSG", code: 6677 } } }, other: { crs: "EPSG:3857" } } });
  const seen = [];
  let wasm = fake(["g", "", geo]);
  let r = readArrow(wasm, Uint8Array.of(9), {}, io(wasm, seen));
  assert.deepEqual([...new Uint8Array(r.table)], [1, 2]);
  assert.equal(r.crs, 6677);
  assert.deepEqual(seen, [[Uint8Array.of(9)]]);
  wasm = fake(["g", '{"crs":"EPSG:2451"}', geo]);
  assert.equal(readArrow(wasm, Uint8Array.of(9), {}, io(wasm, [])).crs, 2451);
  // Longitude and latitude, or no metadata at all: the caller's `crs`, if any.
  wasm = fake(["g", '{"crs":"OGC:CRS84"}', "not json"]);
  assert.equal(readArrow(wasm, Uint8Array.of(9), {}, io(wasm, [])).crs, undefined);
  wasm = fake(["", "", ""]);
  assert.equal(readArrow(wasm, Uint8Array.of(9), { crs: 6677 }, io(wasm, [])).crs, 6677);
  wasm = fake(["g", '{"crs":"mystery"}', ""]);
  assert.throws(() => readArrow(wasm, Uint8Array.of(9), {}, io(wasm, [])), /names no EPSG code/);
});

test("writeArrow: the options as the wasm's flags", () => {
  const wasm = fake([]);
  const seen = [];
  assert.equal(writeArrow(wasm, Uint8Array.of(5), {}, io(wasm, seen)), 0);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: true }, io(wasm, seen)), 1);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { file: true }, io(wasm, seen)), 2);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: true, file: true }, io(wasm, seen)), 3);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: 1, file: "yes" }, io(wasm, seen)), 0);
  assert.equal(seen.length, 5);
});

test("readParquet: GZIP pages are inflated to the size the wasm says and follow the file, sized", async () => {
  const { readParquet } = await import("./arrow.mjs");
  const gzip = async (bytes) => new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());
  const page = await gzip(Uint8Array.of(1, 2, 3, 4, 5));
  const data = new Uint8Array(4 + page.length);
  data.set(page, 4);
  const run = async (size) => {
    const seen = [];
    // Three i32s listed (12 bytes): the page's position, its length and the size it inflates to.
    const wasm = { pages: () => 3, read: (n) => `read ${n}`, info_out: () => "info" };
    const output = (w, n) => (n === 12 ? Int32Array.of(4, page.length, size).buffer : n === "info" ? new ArrayBuffer(0) : new TextEncoder().encode(n).buffer);
    const r = await readParquet(wasm, data, {}, { writeInput: (w, parts) => seen.push(parts), output });
    return [new TextDecoder().decode(r.table), seen];
  };
  const [read, seen] = await run(5);
  assert.equal(read, `read ${data.length}`);
  assert.equal(seen.length, 2);
  assert.deepEqual(seen[1].map((p) => Array.from(p)), [Array.from(data), [5, 0, 0, 0], [1, 2, 3, 4, 5]]);
  await assert.rejects(run(4), /larger than its header says/);
  await assert.rejects(run(6), /smaller than its header says/);
});

test("readParquet: a file without GZIP pages is read as it was placed", async () => {
  const { readParquet } = await import("./arrow.mjs");
  const seen = [];
  const wasm = { pages: () => 0, read: () => "table", info_out: () => "info" };
  const output = (w, n) => (n === "table" ? Uint8Array.of(7).buffer : new ArrayBuffer(0));
  const r = await readParquet(wasm, Uint8Array.of(1, 2), { crs: 6677 }, { writeInput: (w, parts) => seen.push(parts), output });
  assert.deepEqual([...new Uint8Array(r.table)], [7]);
  assert.equal(r.crs, 6677);
  assert.equal(seen.length, 1);
});
