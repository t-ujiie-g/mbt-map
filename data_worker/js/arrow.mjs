// Arrow IPC through arrow.wasm and Parquet through parquet.wasm, with zstd.wasm (docs/dev/FORMATS.md "Arrow", "Parquet"):
// what the data worker's `read` and `write` do for the formats `arrow` and `parquet`, loaded with the first of them.

import { dataFetchInit, MAX_DATA_BYTES, readCapped } from "../../worker/js/body.mjs";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
// The bytes of a Parquet file's end fetched first (most footers fit), and how far apart two ranges of it may be
// to be fetched as one.
const TAIL = 65536;
const GAP = 16384;
// The most range requests of one read under way at once.
const MAX_REQUESTS = 8;
// `MAX_ARROW_INFLATED` (formats/arrow.mbt): the most one input's compressed parts may inflate to.
const MAX_INFLATED = 2 ** 30;

function parsed(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * The EPSG code of a GeoArrow or GeoParquet `crs` (a string such as `EPSG:6677`, or PROJJSON with
 * an `id`), undefined for none or longitude and latitude; throws for one that names no EPSG code.
 */
export function crsCode(crs) {
  if (crs == null) return undefined;
  const id = typeof crs === "string" ? /^\s*(\w+):(\w+)\s*$/.exec(crs)?.slice(1) : [crs.id?.authority, crs.id?.code];
  const [authority, code] = (id ?? []).map((v) => String(v).toUpperCase());
  if (authority === "OGC" && code === "CRS84") return undefined;
  if (authority === "EPSG" && /^\d+$/.test(code)) return Number(code) === 4326 ? undefined : Number(code);
  throw new Error("the geometry's CRS names no EPSG code; give options.crs");
}

/** The Arrow stream or file `data` as `read` gives a format's result: its table and the CRS its geometry column names. */
export async function readArrow(wasm, data, options, io, zstd) {
  await place(wasm, data, io, zstd);
  return described(wasm, io.output(wasm, wasm.read(data.length)), options, io.output);
}

// The strings of `bytes`, each after its u32 length.
function strings(bytes) {
  const view = new DataView(bytes.buffer);
  const texts = [];
  for (let at = 0; at + 4 <= bytes.length; ) {
    const n = view.getUint32(at, true);
    texts.push(decoder.decode(bytes.subarray(at + 4, at + 4 + n)));
    at += 4 + n;
  }
  return texts;
}

// `table` with the CRS the last read's geometry column names (`info_out`).
function described(wasm, table, options, output) {
  const [name, extension, geo] = strings(new Uint8Array(output(wasm, wasm.info_out())));
  // The caller's `crs` is for data that names none.
  const crs = crsCode(parsed(extension)?.crs ?? parsed(geo)?.columns?.[name]?.crs);
  return { table, crs: crs ?? options.crs };
}

// The GZIP member `bytes` inflated: exactly `size` bytes, or it throws.
async function gunzip(bytes, size) {
  const reader = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const out = new Uint8Array(size);
  let n = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value.length > size - n) {
      reader.cancel();
      throw new Error("a GZIP page larger than its header says");
    }
    out.set(value, n);
    n += value.length;
  }
  if (n !== size) throw new Error("a GZIP page smaller than its header says");
  return out;
}

/**
 * Places `data` as `wasm`'s input and, after it, what `wasm.pages()` lists of it inflated (a u32 length before each):
 * GZIP members by the browser's DecompressionStream, ZSTD frames by zstd.wasm (`zstd()` loads it). The parts may
 * inflate to MAX_INFLATED bytes in all; one whose size is listed must inflate to exactly it.
 */
async function place(wasm, data, { writeInput, output }, zstd) {
  writeInput(wasm, [data]);
  const count = wasm.pages();
  const list = new Int32Array(output(wasm, count < 0 ? count : count * 4));
  if (list.length === 0) return;
  const parts = [data];
  let left = MAX_INFLATED;
  for (let i = 0; i < list.length; i += 4) {
    const [at, length, size, codec] = list.subarray(i, i + 4);
    if (size > left) throw new Error("compressed parts that inflate past 1 GB");
    const packed = data.subarray(at, at + length);
    let bytes;
    if (codec === 2) bytes = await gunzip(packed, size);
    else {
      const z = await zstd();
      writeInput(z, [packed]);
      const n = z.inflate(size < 0 ? left : size);
      if (n < 0 || (size >= 0 && n !== size)) throw new Error(n === -2 ? "out of memory" : "malformed ZSTD data, or of another size than its header says");
      bytes = new Uint8Array(z.memory.buffer.slice(z.output_addr(), z.output_addr() + n));
    }
    left -= bytes.length;
    parts.push(new Uint8Array(Uint32Array.of(bytes.length).buffer), bytes);
  }
  writeInput(wasm, parts);
}

// The last `n` bytes of the file at `remote.url` and its size; `{ whole }` from a server that ignores ranges or
// does not show the size (`Content-Range`).
async function tail({ url, init }, n) {
  const get = async (headers) => {
    const options = dataFetchInit(init);
    options.headers = { ...options.headers, ...headers };
    const res = await fetch(url, options);
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return res;
  };
  const res = await get({ Range: `bytes=-${n}` });
  const size = res.status === 206 ? Number(/\/(\d+)$/.exec(res.headers.get("content-range") ?? "")?.[1]) : NaN;
  if (Number.isSafeInteger(size)) return { bytes: await readCapped(res, n), size };
  if (res.status === 206) res.body?.cancel();
  return { whole: await readCapped(res.status === 206 ? await get({}) : res, MAX_DATA_BYTES) };
}

/** Strings as arrow.wasm and parquet.wasm take them: a u32 count, then a u32 length and UTF-8 each. */
function names(list) {
  const texts = list.map((s) => encoder.encode(s));
  const out = new Uint8Array(4 + texts.reduce((n, t) => n + 4 + t.length, 0));
  const view = new DataView(out.buffer);
  view.setUint32(0, texts.length, true);
  let at = 4;
  for (const t of texts) {
    view.setUint32(at, t.length, true);
    out.set(t, at + 4);
    at += 4 + t.length;
  }
  return out;
}

/**
 * The Parquet file `data`, or the one at `remote` (`{ url, init }`) read by range requests (`rangeReader`, as
 * data_worker/js/read.mjs has it): its footer, then only the row groups and columns that `options.bbox` (in the
 * file's coordinates) and `options.columns` leave, as parquet.wasm plans them. Gives what `readArrow` gives.
 */
export async function readParquet(wasm, { data, remote }, options, io, zstd, rangeReader) {
  const { writeInput, output } = io;
  let whole = data;
  let end = data;
  let size = data?.length;
  if (!whole) ({ whole, bytes: end = whole, size = whole.length } = await tail(remote, TAIL));
  const magic = (at) => end.length >= 12 && end[at] === 0x50 && end[at + 1] === 0x41 && end[at + 2] === 0x52 && end[at + 3] === 0x31;
  if (!magic(end.length - 4) || (whole && !magic(0))) throw new Error("malformed Parquet at 0: not a Parquet file");
  const footer = new DataView(end.buffer, end.byteOffset, end.byteLength).getUint32(end.length - 8, true);
  if (footer + 12 > size || footer > MAX_DATA_BYTES) throw new Error(`malformed Parquet at ${size - 8}: a footer past the start of the file, or too long`);
  // `length` bytes of the file from `offset`: of the whole file, of the end already here, or fetched. A server
  // may answer with the whole file instead (`fallback`); else no more than `length` bytes are taken of its answer.
  const get = async (offset, length, fallback = true) => {
    if (!whole && offset >= size - end.length) return end.subarray(offset - (size - end.length)).subarray(0, length);
    if (!whole) {
      const got = await rangeReader(remote.url, remote.init, fallback ? MAX_DATA_BYTES : length)(offset, length);
      if (!got.whole) return got;
      whole = got.whole;
    }
    return whole.subarray(offset, offset + length);
  };
  writeInput(wasm, [await get(size - 8 - footer, footer)]);
  output(wasm, wasm.open());
  const [name, , geo] = strings(new Uint8Array(output(wasm, wasm.info_out())));
  // GeoParquet's `covering`: the columns holding each row's box, by which row groups are passed over.
  const box = parsed(geo)?.columns?.[name]?.covering?.bbox;
  const paths = ["xmin", "ymin", "xmax", "ymax"].map((k) => box?.[k]);
  const covering = paths.every((p) => Array.isArray(p) && p.every((s) => typeof s === "string")) ? paths.map((p) => p.join(".")) : [];
  const { bbox, columns } = options;
  writeInput(wasm, [
    Uint8Array.of(bbox ? 1 : 0), new Uint8Array(Float64Array.from(bbox ?? [0, 0, 0, 0]).buffer),
    Uint8Array.of(columns ? 1 : 0), ...(columns ? [names(columns)] : []), names(covering),
  ]);
  const count = wasm.plan();
  const planned = new Float64Array(output(wasm, count < 0 ? count : count * 8));
  // The ranges in order, those less than GAP apart fetched as one.
  const wanted = [];
  for (const [offset, length] of Array.from({ length: planned.length / 2 }, (_, i) => [planned[i * 2], planned[i * 2 + 1]]).sort((a, b) => a[0] - b[0])) {
    const last = wanted.at(-1);
    if (last && offset <= last[0] + last[1] + GAP) last[1] = Math.max(last[1], offset + length - last[0]);
    else wanted.push([offset, length]);
  }
  if (wanted.reduce((n, [, length]) => n + length, 0) > MAX_DATA_BYTES) throw new Error(`more than ${MAX_DATA_BYTES} bytes to read: narrow bbox or columns`);
  // The first range alone, which may bring the whole file; the others a few at once, each held to its length.
  const parts = wanted.length ? [await get(...wanted[0])] : [];
  for (let i = 1; i < wanted.length; i += MAX_REQUESTS) parts.push(...(await Promise.all(wanted.slice(i, i + MAX_REQUESTS).map(([offset, length]) => get(offset, length, false)))));
  // parquet.wasm's input: how many parts, where each is in the file and how long, then their bytes.
  const table = new DataView(new ArrayBuffer(4 + wanted.length * 12));
  table.setUint32(0, wanted.length, true);
  wanted.forEach(([offset], i) => {
    table.setFloat64(4 + i * 12, offset, true);
    table.setUint32(12 + i * 12, parts[i].length, true);
  });
  const main = new Uint8Array(table.byteLength + parts.reduce((n, p) => n + p.length, 0));
  main.set(new Uint8Array(table.buffer));
  let at = table.byteLength;
  for (const p of parts) {
    main.set(p, at);
    at += p.length;
  }
  await place(wasm, main, io, zstd);
  return described(wasm, output(wasm, wasm.read(main.length)), options, output);
}

/** `table` (Table bytes) as Arrow IPC: `options.native` for GeoArrow's types, `options.file` for the file format. */
export function writeArrow(wasm, table, options, { writeInput, output }) {
  writeInput(wasm, [table]);
  return output(wasm, wasm.write((options.native === true ? 1 : 0) | (options.file === true ? 2 : 0)));
}
