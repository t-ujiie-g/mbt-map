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

test("readArrow: listed parts are inflated (GZIP here, ZSTD by zstd.wasm) and follow the data, sized", async () => {
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
    const writeInput = (w, parts) => seen.push([w === z ? "zstd" : "data", parts.map((p) => Array.from(p))]);
    const r = await readArrow(wasm, data, {}, { writeInput, output }, async () => z);
    return [new TextDecoder().decode(r.table), seen];
  };
  const zstdAt = 4 + page.length;
  const [read, seen] = await run([4, page.length, 5, 2, zstdAt, 2, 3, 6, zstdAt, 2, -1, 6]);
  assert.equal(read, `read ${data.length}`);
  assert.deepEqual(seen[1], ["zstd", [[8, 9]]]);
  assert.deepEqual(seen.at(-1), ["data", [Array.from(data), [5, 0, 0, 0], [1, 2, 3, 4, 5], [3, 0, 0, 0], [7, 7, 7], [3, 0, 0, 0], [7, 7, 7]]]);
  // A part of unknown size may take what is left of the 1 GB.
  assert.deepEqual(limits, [3, 2 ** 30 - 8]);
  await assert.rejects(run([4, page.length, 4, 2]), /larger than its header says/);
  await assert.rejects(run([4, page.length, 6, 2]), /smaller than its header says/);
  await assert.rejects(run([4, page.length, 2 ** 30 + 1, 2]), /inflate past 1 GB/);
  await assert.rejects(run([zstdAt, 2, 2, 6]), /malformed ZSTD data/);
  await assert.rejects(run([zstdAt, 2, 4, 6]), /another size than its header says/);
});

// A "Parquet file" of 100 000 bytes, each its position modulo 251, ending in an 8-byte footer, its length and PAR1;
// a wasm that plans `ranges` and gives back the parts it is handed; a server that counts what it sends.
async function ranged(ranges, { server = "ranges", options = {} } = {}) {
  const { readParquet } = await import("./arrow.mjs");
  const file = Uint8Array.from({ length: 100000 }, (_, i) => i % 251);
  file.set([0x50, 0x41, 0x52, 0x31]);
  file.set([8, 0, 0, 0, 0x50, 0x41, 0x52, 0x31], file.length - 8);
  const calls = [];
  const sent = [];
  let input = [];
  const geo = JSON.stringify({ columns: { g: { covering: { bbox: { xmin: ["b", "x0"], ymin: ["b", "y0"], xmax: ["b", "x1"], ymax: ["b", "y1"] } } } } });
  const text = (strings) => Uint8Array.from(strings.flatMap((t) => [...new Uint8Array(Uint32Array.of(t.length).buffer), ...new TextEncoder().encode(t)])).buffer;
  const wasm = { open: () => (calls.push(["open", input[0].length]), 0), info_out: () => "info", plan: () => (calls.push(["plan", input.map((p) => Array.from(p))]), ranges.length * 2), pages: () => 0, read: () => "table" };
  const output = (w, n) => (n === "info" ? text(["g", "", geo]) : n === ranges.length * 16 ? Float64Array.from(ranges.flat()).buffer : n === "table" ? Uint8Array.from(input[0]).buffer : new ArrayBuffer(0));
  const fetching = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const range = /^bytes=(\d*)-(\d*)$/.exec(new Headers(init.headers).get("range") ?? "");
    if (!range || server === "whole") return (sent.push([0, file.length]), new Response(file, { status: 200 }));
    const start = range[1] === "" ? file.length - Number(range[2]) : Number(range[1]);
    const end = range[1] === "" ? file.length - 1 : Number(range[2]);
    sent.push([start, end - start + 1]);
    return new Response(file.subarray(start, end + 1), { status: 206, headers: server === "hidden" ? {} : { "content-range": `bytes ${start}-${end}/${file.length}` } });
  };
  // As data_worker/js/read.mjs's `rangeReader`.
  const rangeReader = (url) => async (offset, length) => new Uint8Array(await (await fetch(url, { headers: { Range: `bytes=${offset}-${offset + length - 1}` } })).arrayBuffer());
  try {
    const r = await readParquet(wasm, { remote: { url: "http://x/f.parquet" } }, options, { writeInput: (w, parts) => (input = parts), output }, null, rangeReader);
    return { main: new Uint8Array(r.table), calls, sent, file };
  } finally {
    globalThis.fetch = fetching;
  }
}

test("readParquet: the end first, then the planned ranges (near ones as one), handed over with where they were", async () => {
  const { main, calls, sent, file } = await ranged([[1000, 100], [1200, 50], [30000, 10], [90000, 20]]);
  // The last 64 KB, then one request for the two ranges 100 bytes apart and one for the third; the last range
  // is in the end already here.
  assert.deepEqual(sent, [[100000 - 65536, 65536], [1000, 250], [30000, 10]]);
  assert.deepEqual(calls[0], ["open", 8]);
  const view = new DataView(main.buffer);
  assert.equal(view.getUint32(0, true), 3);
  assert.deepEqual([0, 1, 2].map((i) => [view.getFloat64(4 + i * 12, true), view.getUint32(12 + i * 12, true)]), [[1000, 250], [30000, 10], [90000, 20]]);
  assert.deepEqual(Array.from(main.subarray(40, 44)), Array.from(file.subarray(1000, 1004)));
  assert.deepEqual(Array.from(main.subarray(40 + 250, 40 + 260)), Array.from(file.subarray(30000, 30010)));
  assert.deepEqual(Array.from(main.subarray(40 + 260)), Array.from(file.subarray(90000, 90020)));
});

test("readParquet: bbox, columns and the covering columns' paths go to the plan", async () => {
  const { calls } = await ranged([], { options: { bbox: [1, 2, 3, 4], columns: ["a", "東"] } });
  const args = calls[1][1].flat();
  assert.equal(args[0], 1);
  assert.deepEqual(Array.from(new Float64Array(Uint8Array.from(args.slice(1, 33)).buffer)), [1, 2, 3, 4]);
  assert.equal(args[33], 1);
  const text = new TextDecoder().decode(Uint8Array.from(args.slice(34)));
  for (const name of ["a", "東", "b.x0", "b.y0", "b.x1", "b.y1"]) assert.ok(text.includes(name), name);
  const none = (await ranged([])).calls[1][1].flat();
  assert.deepEqual([none[0], none[33]], [0, 0]);
});

test("readParquet: a server without ranges, or that hides the size, gives the whole file once", async () => {
  for (const server of ["whole", "hidden"]) {
    const { main, sent, file } = await ranged([[1000, 100], [90000, 20]], { server });
    assert.deepEqual(sent.at(-1), [0, 100000]);
    assert.ok(sent.length <= 2);
    assert.deepEqual(Array.from(main.subarray(28, 32)), Array.from(file.subarray(1000, 1004)));
  }
});

test("readParquet: what is no Parquet file, and more than may be read, are refused", async () => {
  const { readParquet } = await import("./arrow.mjs");
  const io = { writeInput: () => {}, output: () => new ArrayBuffer(0) };
  await assert.rejects(readParquet({}, { data: new Uint8Array(20) }, {}, io), /not a Parquet file/);
  await assert.rejects(readParquet({}, { data: Uint8Array.of(0x50, 0x41, 0x52, 0x31, 0, 0, 0, 0, 99, 0, 0, 0, 0x50, 0x41, 0x52, 0x31) }, {}, io), /a footer past the start/);
  await assert.rejects(ranged([[0, 2 ** 28 + 1]]), /bytes to read: narrow bbox or columns/);
});
