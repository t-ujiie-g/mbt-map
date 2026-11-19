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
  return { pages: () => 0, read: () => "table", info_out: () => "info", write: (flags) => flags, info };
}
const io = (wasm, seen) => ({
  writeInput: (w, parts) => seen.push(parts),
  output: (w, n) => (n === "table" ? Uint8Array.of(1, 2).buffer : n === "info" ? Uint8Array.from(wasm.info).buffer : n === 0 ? new ArrayBuffer(0) : n),
});

test("readArrow: the table and the CRS of the geometry column, the extension's before the geo metadata's", async () => {
  const geo = JSON.stringify({ primary_column: "g", columns: { g: { crs: { id: { authority: "EPSG", code: 6677 } } }, other: { crs: "EPSG:3857" } } });
  const seen = [];
  let wasm = fake(["g", "", geo]);
  let r = await readArrow(wasm, Uint8Array.of(9), {}, io(wasm, seen));
  assert.deepEqual([...new Uint8Array(r.table)], [1, 2]);
  assert.equal(r.crs, 6677);
  assert.deepEqual(seen, [[Uint8Array.of(9)]]);
  wasm = fake(["g", '{"crs":"EPSG:2451"}', geo]);
  assert.equal((await readArrow(wasm, Uint8Array.of(9), {}, io(wasm, []))).crs, 2451);
  // Longitude and latitude, or no metadata at all: the caller's `crs`, if any.
  wasm = fake(["g", '{"crs":"OGC:CRS84"}', "not json"]);
  assert.equal((await readArrow(wasm, Uint8Array.of(9), {}, io(wasm, []))).crs, undefined);
  wasm = fake(["", "", ""]);
  assert.equal((await readArrow(wasm, Uint8Array.of(9), { crs: 6677 }, io(wasm, []))).crs, 6677);
  wasm = fake(["g", '{"crs":"mystery"}', ""]);
  await assert.rejects(readArrow(wasm, Uint8Array.of(9), {}, io(wasm, [])), /names no EPSG code/);
});

test("writeArrow: the options as the wasm's flags", () => {
  const wasm = fake([]);
  const seen = [];
  const flagsIo = { writeInput: (w, parts) => seen.push(parts), output: (w, n) => n };
  assert.equal(writeArrow(wasm, Uint8Array.of(5), {}, flagsIo), 0);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: true }, flagsIo), 1);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { file: true }, flagsIo), 2);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: true, file: true }, flagsIo), 3);
  assert.equal(writeArrow(wasm, Uint8Array.of(5), { native: 1, file: "yes" }, flagsIo), 0);
  assert.equal(seen.length, 5);
});

test("readParquet: listed parts are inflated (GZIP here, ZSTD by zstd.wasm) and follow the file, sized", async () => {
  const { readParquet } = await import("./arrow.mjs");
  const gzip = async (bytes) => new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());
  const page = await gzip(Uint8Array.of(1, 2, 3, 4, 5));
  const data = new Uint8Array(4 + page.length + 2);
  data.set(page, 4);
  data.set([8, 9], 4 + page.length);
  // zstd.wasm: "inflates" its input to [7, 7, 7] if `limit` allows.
  const limits = [];
  const z = { memory: { buffer: Uint8Array.of(7, 7, 7).buffer }, output_addr: () => 0, inflate: (limit) => (limits.push(limit), limit >= 3 ? 3 : -1) };
  const run = async (list) => {
    const seen = [];
    // The list as i32s: a part's position, its length, the size it inflates to and its codec.
    const wasm = { pages: () => list.length, read: (n) => `read ${n}`, info_out: () => "info" };
    const output = (w, n) => (n === list.length * 4 ? Int32Array.from(list).buffer : n === "info" ? new ArrayBuffer(0) : new TextEncoder().encode(n).buffer);
    const writeInput = (w, parts) => seen.push([w === z ? "zstd" : "file", parts.map((p) => Array.from(p))]);
    const r = await readParquet(wasm, data, {}, { writeInput, output }, async () => z);
    return [new TextDecoder().decode(r.table), seen];
  };
  const zstdAt = 4 + page.length;
  const [read, seen] = await run([4, page.length, 5, 2, zstdAt, 2, 3, 6, zstdAt, 2, -1, 6]);
  assert.equal(read, `read ${data.length}`);
  assert.deepEqual(seen[1], ["zstd", [[8, 9]]]);
  assert.deepEqual(seen.at(-1), ["file", [Array.from(data), [5, 0, 0, 0], [1, 2, 3, 4, 5], [3, 0, 0, 0], [7, 7, 7], [3, 0, 0, 0], [7, 7, 7]]]);
  // A part of unknown size may take what is left of the 1 GB.
  assert.deepEqual(limits, [3, 2 ** 30 - 8]);
  await assert.rejects(run([4, page.length, 4, 2]), /larger than its header says/);
  await assert.rejects(run([4, page.length, 6, 2]), /smaller than its header says/);
  await assert.rejects(run([4, page.length, 2 ** 30 + 1, 2]), /inflate past 1 GB/);
  await assert.rejects(run([zstdAt, 2, 2, 6]), /malformed ZSTD data/);
  await assert.rejects(run([zstdAt, 2, 4, 6]), /another size than its header says/);
});

test("readParquet: a file without GZIP pages is read as it was placed", async () => {
  const { readParquet } = await import("./arrow.mjs");
  const seen = [];
  const wasm = { pages: () => 0, read: () => "table", info_out: () => "info" };
  const output = (w, n) => (n === "table" ? Uint8Array.of(7).buffer : new ArrayBuffer(0));
  const r = await readParquet(wasm, Uint8Array.of(1, 2), { crs: 6677 }, { writeInput: (w, parts) => seen.push(parts), output }, () => assert.fail("zstd.wasm is not loaded"));
  assert.deepEqual([...new Uint8Array(r.table)], [7]);
  assert.equal(r.crs, 6677);
  assert.equal(seen.length, 1);
});
