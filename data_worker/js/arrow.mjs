// Arrow IPC through arrow.wasm (docs/dev/FORMATS.md "Arrow"): what the data worker's `read` and
// `write` do for the format `arrow`, loaded with the first of them.

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
  const table = output(wasm, wasm.read());
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

/** `table` (Table bytes) as Arrow IPC: `options.native` for GeoArrow's types, `options.file` for the file format. */
export function writeArrow(wasm, table, options, { writeInput, output }) {
  writeInput(wasm, [table]);
  return output(wasm, wasm.write((options.native === true ? 1 : 0) | (options.file === true ? 2 : 0)));
}
