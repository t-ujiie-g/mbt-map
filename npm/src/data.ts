// `mbt-map/data`: GeoTIFF pixels and tiles, and reprojected sources' tiles, drawn in the data worker
// (started on the first call), which also reads and writes `mbt-map/table`'s tables.
import { dataClient, startData, type DataOptions } from "./clients";
import type { ReprojectedSource } from "./services/common";
import { httpUrl, type TransformedRequest } from "./urls";

export type { DataOptions };

/** May change a URL's request as the map's `transformRequest` does (no credentials are sent otherwise). */
export type TransformRequest = (url: string) => TransformedRequest | undefined;

type Input = string | URL | Blob | ArrayBuffer | ArrayBufferView;

/** `input` as the data worker takes a source: `{ url, init }`, `{ blob }` or `{ bytes }` (copied, and added to `transfer`). */
function sourceOf(input: Input, options: { transformRequest?: TransformRequest }, transfer: Transferable[]): object {
  if (typeof input === "string" || input instanceof URL) {
    const url = httpUrl(input, document.baseURI, "data: the URL");
    const r = options.transformRequest?.(url);
    const init = r ? { headers: r.headers, credentials: r.credentials } : undefined;
    return { url: r ? httpUrl(r.url, document.baseURI, "data: the URL") : url, init };
  }
  if (input instanceof Blob) return { blob: input };
  const bytes =
    input instanceof ArrayBuffer ? input.slice(0) :
    ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice().buffer :
    null;
  if (!bytes) throw new Error("mbt-map: data: read takes a URL, a Blob or bytes");
  transfer.push(bytes);
  return { bytes };
}

/** A band of a raster, typed as geotiff's `readRasters` types it. */
export type RasterBand = Uint8Array | Int8Array | Uint16Array | Int16Array | Uint32Array | Int32Array | Float32Array | Float64Array;

/** Which pixels `readRaster` reads, as geotiff's `readRasters` takes them (`window`, `bbox`, `width`, `height`, `resX`,
 * `resY`, `resampleMethod`, `samples`, `fillValue`), `image` by index, `transformRequest` as `read`'s; docs/data.md has the rules. */
export interface RasterOptions extends DataOptions {
  window?: [number, number, number, number];
  bbox?: [number, number, number, number];
  width?: number;
  height?: number;
  resX?: number;
  resY?: number;
  resampleMethod?: "nearest" | "bilinear";
  image?: number;
  samples?: number[];
  fillValue?: number;
  transformRequest?: TransformRequest;
}

/** Pixels `readRaster` read: `bands` per sample, the window's `bbox` and `resolution` (y negative north up; null
 * without geo tags) in `crs` (GeoKeys' EPSG code or null), `noData` (GDAL_NODATA or null); docs/data.md has the rest. */
export interface Raster {
  width: number;
  height: number;
  bands: RasterBand[];
  bbox: [number, number, number, number] | null;
  resolution: [number, number] | null;
  window: [number, number, number, number];
  image: number;
  images: number;
  crs: number | null;
  noData: number | null;
  pixelIsPoint: boolean;
}

const fail = (what: string): never => {
  throw new Error(`mbt-map: data: invalid ${what}`);
};

const isFour = (v: unknown): boolean => Array.isArray(v) && v.length === 4 && v.every(Number.isFinite);

/**
 * Reads pixels of the GeoTIFF or COG `input` (an http(s) URL, read by range requests; a Blob, read
 * in slices; or bytes) as geotiff 3.0.5's `readRasters` does (docs/data.md has the rules).
 */
export async function readRaster(input: Input, options: RasterOptions = {}): Promise<Raster> {
  const { window: wnd, bbox, width, height, resX, resY, resampleMethod, image, samples, fillValue } = options;
  if (wnd !== undefined && (!isFour(wnd) || !wnd.every(Number.isInteger))) fail("window");
  if (bbox !== undefined && !isFour(bbox)) fail("bbox");
  for (const [what, n] of [["width", width], ["height", height], ["image", image]] as const) {
    if (n !== undefined && !(Number.isInteger(n) && n >= (what === "image" ? 0 : 1) && n <= 65536)) fail(what);
  }
  for (const [what, n] of [["resX", resX], ["resY", resY], ["fillValue", fillValue]] as const) if (n !== undefined && !Number.isFinite(n)) fail(what);
  if (resampleMethod !== undefined && !["nearest", "bilinear", "linear"].includes(resampleMethod)) fail("resampleMethod");
  if (samples !== undefined && (!Array.isArray(samples) || !samples.every((s) => Number.isInteger(s) && s >= 0))) fail("samples");
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  startData(options);
  return dataClient.call<Raster>("readRaster", { ...source, options: { window: wnd, bbox, width, height, resX, resY, resampleMethod, image, samples, fillValue } }, transfer);
}

/** What `rasterInfo` gives: `crs` (EPSG code), `bounds` in longitude and latitude, `maxzoom` (256-px tiles), `samples`, `noData`, `range` (band 0's values in the coarsest image). */
export interface RasterInfo {
  crs: number;
  bounds: [number, number, number, number];
  maxzoom: number;
  samples: number;
  noData: number | null;
  range: [number, number] | null;
}

/** How `rasterTile` draws (docs/data.md): `tileSize`, `bands`, `range`, `colors` (`[value, color]` stops), `dem`, `resampling`. */
export interface RasterTileOptions extends DataOptions {
  tileSize?: 256 | 512;
  bands?: number[];
  range?: [number, number];
  colors?: [number, string][];
  dem?: boolean;
  resampling?: "nearest" | "bilinear";
  transformRequest?: TransformRequest;
}

/** What drawing the GeoTIFF of `input` needs: it must carry an EPSG code proj.wasm knows. */
export async function rasterInfo(input: Input, options: DataOptions & { transformRequest?: TransformRequest } = {}): Promise<RasterInfo> {
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  startData(options);
  return dataClient.call<RasterInfo>("rasterInfo", source, transfer);
}

/** XYZ tile `z`/`x`/`y` of the GeoTIFF of `input` as a PNG, or null where it has no pixel. */
export async function rasterTile(input: Input, z: number, x: number, y: number, options: RasterTileOptions = {}): Promise<ArrayBuffer | null> {
  const { tileSize = 256, bands, range, colors, dem, resampling } = options;
  if (![z, x, y].every(Number.isInteger) || z < 0 || z > 24 || x < 0 || y < 0 || x >= 2 ** z || y >= 2 ** z) fail("tile");
  if (bands !== undefined && (!Array.isArray(bands) || bands.length < 1 || bands.length > 4 || !bands.every((b) => Number.isInteger(b) && b >= 0))) fail("bands");
  if (range !== undefined && !(Array.isArray(range) && range.length === 2 && range.every(Number.isFinite))) fail("range");
  if (colors !== undefined && !(Array.isArray(colors) && colors.every((c) => Array.isArray(c) && Number.isFinite(c[0]) && typeof c[1] === "string"))) fail("colors");
  if (resampling !== undefined && resampling !== "nearest" && resampling !== "bilinear") fail("resampling");
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  startData(options);
  return dataClient.call<ArrayBuffer | null>("rasterTile", { ...source, options: { z, x, y, tileSize, bands, range, colors, dem: dem === true, resampling } }, transfer);
}

/**
 * XYZ tile `z`/`x`/`y` of a `reprojected` source (docs/data.md; mbt-map/services' `wmsSource` and `wmtsSource` make them) as a PNG,
 * or null where it shows nothing. `transformRequest` is asked once with the source's template: its headers and credentials go
 * with each request.
 */
export async function reprojectTile(spec: ReprojectedSource, z: number, x: number, y: number, options: DataOptions & { tileSize?: 256 | 512; transformRequest?: TransformRequest } = {}): Promise<ArrayBuffer | null> {
  if (![z, x, y].every(Number.isInteger) || z < 0 || z > 24 || x < 0 || y < 0 || x >= 2 ** z || y >= 2 ** z) fail("tile");
  const part = spec.grid ?? spec.image;
  if (!part || typeof part.template !== "string") return fail("reprojected source");
  const template = new URL(part.template, document.baseURI).href.replace(/%7B(\w+)%7D/gi, "{$1}");
  const r = options.transformRequest?.(template);
  startData(options);
  const which = spec.grid ? { grid: { ...spec.grid, template } } : { image: { ...spec.image!, template } };
  const init = r ? { headers: r.headers, credentials: r.credentials } : undefined;
  return dataClient.call<ArrayBuffer | null>("reprojectTile", { spec: { crs: spec.crs, ...which }, options: { z, x, y, tileSize: options.tileSize ?? 256 }, init });
}

/** Stops the data worker; pending calls reject. */
export function terminate(): void {
  dataClient.terminate();
}
