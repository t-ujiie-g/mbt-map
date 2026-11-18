// Arrow IPC through arrow.wasm and Parquet through parquet.wasm (docs/dev/FORMATS.md "Arrow", "Parquet"):
// what the data worker's `read` and `write` do for the formats `arrow` and `parquet`, loaded with the first of them.

const decoder = new TextDecoder();

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
export function readArrow(wasm, data, options, { writeInput, output }) {
  writeInput(wasm, [data]);
  return described(wasm, output(wasm, wasm.read()), options, output);
}

// `table` with the CRS the last read's geometry column names (`info_out`).
function described(wasm, table, options, output) {
  const info = new Uint8Array(output(wasm, wasm.info_out()));
  const view = new DataView(info.buffer);
  const texts = [];
  for (let at = 0; at + 4 <= info.length; ) {
    const n = view.getUint32(at, true);
    texts.push(decoder.decode(info.subarray(at + 4, at + 4 + n)));
    at += 4 + n;
  }
  const [name, extension, geo] = texts;
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
 * The Parquet file `data` as `readArrow` gives an Arrow one: its GZIP pages are inflated here (the browser's
 * DecompressionStream) and handed to the wasm after the file, each with its length before it.
 */
export async function readParquet(wasm, data, options, { writeInput, output }) {
  writeInput(wasm, [data]);
  const count = wasm.pages();
  const pages = new Int32Array(output(wasm, count < 0 ? count : count * 4));
  if (pages.length > 0) {
    const parts = [data];
    for (let i = 0; i < pages.length; i += 3) {
      const inflated = await gunzip(data.subarray(pages[i], pages[i] + pages[i + 1]), pages[i + 2]);
      parts.push(new Uint8Array(Uint32Array.of(inflated.length).buffer), inflated);
    }
    writeInput(wasm, parts);
  }
  return described(wasm, output(wasm, wasm.read(data.length)), options, output);
}

/** `table` (Table bytes) as Arrow IPC: `options.native` for GeoArrow's types, `options.file` for the file format. */
export function writeArrow(wasm, table, options, { writeInput, output }) {
  writeInput(wasm, [table]);
  return output(wasm, wasm.write((options.native === true ? 1 : 0) | (options.file === true ? 2 : 0)));
}
