// `mbt-map/analysis`: elevation grids (slope, aspect, hillshade, viewshed, line of sight), coordinate
// transforms and class breaks, in the analysis worker `mbt-map/table`'s tables use. The tables'
// analysis is `mbt-map/table`'s; its names are also exported here.
import { analysisCall, analysisClient, free, live, named, startAnalysis, type AnalysisOptions } from "./clients";
import { crsArg as crsArgOf, type Crs } from "./crs";
import { demZoom } from "./dem-zoom";
import { CURVATURE_COEFF, distance, sight } from "./sight";
import { fromGeoJSON, Table, type BBox, type LoadOptions } from "./table";
import { resolveTemplate } from "./urls";

export { classBreaks, classStep, MAX_CKMEANS_CELLS, MAX_CLASS_VALUES, MAX_CLASSES, MAX_JENKS_WORK, statistics, type ClassMethod, type Statistics } from "./classify";
export { defineCrs, grid, Network, type BBox, type BufferMode, type BufferOptions, type Collected, type DbscanKind, type DensityOptions, type InterpolateOptions, type LoadOptions, type NearestOnLine, type Relation } from "./table";
export { distance };
export type { AnalysisOptions, Crs };
/** `mbt-map/table`'s `Table`, by its earlier name. */
export const Dataset = Table;
export type Dataset = Table;

const crsArg = (crs: Crs) => crsArgOf(crs, "analysis", named);
const isPoint = (p: unknown): p is [number, number] => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite);

/** `mbt-map/table`'s `fromGeoJSON`, by its earlier name; a table is read again from its GeoJSON. */
export async function load(data: unknown, options: LoadOptions = {}): Promise<Table> {
  return fromGeoJSON(data instanceof Table ? await data.toGeoJSON() : data, options);
}

/** `DemGrid.viewshed`'s options, as gdal_viewshed's `-oz`, `-tz`, `-md`, `-cc`, `-om`, `-vv`, `-iv`, `-ov`. */
export interface ViewshedOptions {
  observerHeight?: number;
  targetHeight?: number;
  maxDistance?: number;
  curvatureCoeff?: number;
  mode?: keyof typeof VIEWSHED_MODES;
  visibleValue?: number;
  invisibleValue?: number;
  outOfRangeValue?: number;
}

/** A viewshed: its cells row by row from the north over `bounds`. */
export interface ViewshedResult {
  width: number;
  height: number;
  bounds: BBox;
  values: Float64Array;
}

/** `DemGrid.lineOfSight`'s options. */
export interface LineOfSightOptions {
  observerHeight?: number;
  targetHeight?: number;
  curvatureCoeff?: number;
  samples?: number;
}

const VIEWSHED_MODES = { normal: 0, dem: 1, ground: 2 } as const;
const MAX_SIGHT_SAMPLES = 100_000;

/** How a DEM's RGB holds elevations: MapLibre's encodings, GSI's, or custom factors. */
export type DemEncoding = "mapbox" | "terrarium" | "gsi" | { redFactor: number; greenFactor: number; blueFactor: number; baseShift?: number };

/** `zoom`: the tile zoom to read (the grid's cells are its pixels); `bounds`: the area to cover (the grid snaps outward to whole tiles). */
export interface DemOptions extends AnalysisOptions {
  zoom: number;
  bounds: BBox;
  encoding?: DemEncoding;
}

// Mirrors `load_dem`'s encodings in analysis_worker/dem.mbt.
function encodingArgs(e: DemEncoding = "mapbox"): number[] {
  if (e === "mapbox") return [0, 0, 0, 0, 0];
  if (e === "terrarium") return [1, 0, 0, 0, 0];
  if (e === "gsi") return [2, 0, 0, 0, 0];
  return [3, e.redFactor, e.greenFactor, e.blueFactor, e.baseShift ?? 0];
}

/** An elevation grid in the analysis worker, row by row from the north. */
export class DemGrid {
  #id: number;
  #generation = analysisClient.generation;
  #disposed = false;
  readonly width: number;
  readonly height: number;
  /** `[west, south, east, north]` of the whole tiles it covers. */
  readonly bounds: BBox;

  /** @internal */
  constructor(id: number, width: number, height: number, bounds: BBox) {
    this.#id = id;
    this.width = width;
    this.height = height;
    this.bounds = bounds;
  }

  async #call<T>(op: string, args: object = {}): Promise<T> {
    return analysisCall<T>(op, { grid: live(this.#id, this.#generation, this.#disposed, "grid"), ...args });
  }

  /**
   * The cells seen from `observer` (`[lng, lat]`) as gdal_viewshed computes them (`observerHeight`,
   * `targetHeight` above the ground, `maxDistance` meters, 0 for no limit, `curvatureCoeff`): `normal`
   * gives `visibleValue` / `invisibleValue` / `outOfRangeValue` per cell, `dem` and `ground` the height a
   * target there must reach to be seen (above sea level or above the ground). The grid is cut to
   * `maxDistance`; a DEM grid is measured in ground meters at its middle latitude.
   */
  async viewshed(observer: [number, number], options: ViewshedOptions = {}): Promise<ViewshedResult> {
    const { observerHeight = 2, targetHeight = 0, maxDistance = 0, curvatureCoeff = CURVATURE_COEFF, mode = "normal", visibleValue = 255, invisibleValue = 0, outOfRangeValue = 0 } = options;
    if (!(mode in VIEWSHED_MODES)) throw new Error(`mbt-map: analysis: unknown viewshed mode ${mode}`);
    return this.#call("viewshed", {
      observer,
      options: { observerHeight, targetHeight, maxDistance, curvatureCoeff, mode: VIEWSHED_MODES[mode], visible: visibleValue, invisible: invisibleValue, outOfRange: outOfRangeValue },
    });
  }

  /**
   * Whether `to` can be seen from `from` (both `[lng, lat]`) over the grid's elevations sampled bilinearly
   * along the line (`samples`, by default one per cell), with gdal_viewshed's curvature correction and
   * distances on Turf's sphere; `blockedAt` is the first sample that hides it.
   */
  async lineOfSight(from: [number, number], to: [number, number], { observerHeight = 2, targetHeight = 0, curvatureCoeff = CURVATURE_COEFF, samples }: LineOfSightOptions = {}): Promise<{ visible: boolean; blockedAt: [number, number] | null }> {
    if (!isPoint(from) || !isPoint(to)) throw new Error("mbt-map: analysis: invalid points");
    const cell = distance([this.bounds[0], this.bounds[1]], [this.bounds[2], this.bounds[1]]) / this.width;
    const n = samples ?? Math.min(MAX_SIGHT_SAMPLES, Math.max(2, Math.ceil(distance(from, to) / cell) + 1));
    if (!Number.isInteger(n) || n < 2 || n > MAX_SIGHT_SAMPLES) throw new Error("mbt-map: analysis: invalid number of samples");
    const points = Array.from({ length: n }, (_, i): [number, number] => [from[0] + ((to[0] - from[0]) * i) / (n - 1), from[1] + ((to[1] - from[1]) * i) / (n - 1)]);
    const heights = await this.sample(points);
    const s = sight(heights, points.map((p) => distance(from, p)), observerHeight, targetHeight, curvatureCoeff);
    return { visible: s.visible, blockedAt: s.blockedAt === null ? null : points[s.blockedAt] };
  }

  /** Elevations in meters; NaN where the DEM has no data. */
  elevations(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 0 });
  }

  /** Slopes in degrees (gdaldem's Horn method). */
  slope(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 1 });
  }

  /** Aspects in degrees clockwise from north, facing downhill; NaN where flat. */
  aspect(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 2 });
  }

  /**
   * The elevation in meters at each `[lng, lat]`, interpolated bilinearly between cell centers as
   * GDAL's `-r bilinear` does; NaN off the grid or next to a cell without data.
   */
  sample(positions: ArrayLike<[number, number]>): Promise<Float64Array> {
    const coords = new Float64Array(positions.length * 2);
    for (let i = 0; i < positions.length; i++) coords.set(positions[i], i * 2);
    return this.#call("gridSample", { coords: coords.buffer });
  }

  /** Shades from 1 to 255 under light from `azimuth` degrees at `altitude` degrees (gdaldem's hillshade). */
  hillshade({ azimuth = 315, altitude = 45, zFactor = 1 }: { azimuth?: number; altitude?: number; zFactor?: number } = {}): Promise<Uint8Array> {
    return this.#call("gridHillshade", { azimuth, altitude, zFactor });
  }

  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    free("dispose", { dataset: this.#id }, this.#generation);
  }
}

/** A raster as mbt-map/data's `readRaster` gives it, only what `loadGrid` reads: `bands` (rows from the north),
 * `bbox` and `resolution` in `crs` (an EPSG code, null for EPSG:4326), `noData`, `pixelIsPoint`. */
export interface GridRaster {
  width: number;
  height: number;
  bands: ArrayLike<number>[];
  bbox: BBox | null;
  resolution: [number, number] | null;
  crs: number | null;
  noData: number | null;
  pixelIsPoint?: boolean;
}

/** Band `band` (default 0) of `raster` as an elevation grid, `noData` cells empty, cells the resolution divided by
 * `scale` (gdaldem's `-s`), PixelIsPoint as GDAL reads it; `sample` takes longitude and latitude (docs/analysis.md). */
export async function loadGrid(raster: GridRaster, options: AnalysisOptions & { band?: number; scale?: number } = {}): Promise<DemGrid> {
  const { band = 0, scale = 1 } = options;
  const { width, height, bands, bbox, resolution, crs, noData } = raster ?? ({} as GridRaster);
  const values = bands?.[band];
  if (!values || values.length !== width * height) throw new Error("mbt-map: analysis: invalid raster or band");
  if (!(Number.isFinite(scale) && scale > 0)) throw new Error("mbt-map: analysis: invalid scale");
  if (!Array.isArray(resolution) || !resolution.every((r) => Number.isFinite(r) && r !== 0) || !Array.isArray(bbox)) throw new Error("mbt-map: analysis: a raster without geo tags (resolution and bbox)");
  const f64 = Float64Array.from(values, (v) => (v === noData ? NaN : v));
  const [rx, ry] = resolution;
  const half = raster.pixelIsPoint ? 0.5 : 0;
  const origin = [(rx > 0 ? bbox[0] : bbox[2]) - half * rx, (ry < 0 ? bbox[3] : bbox[1]) - half * ry];
  startAnalysis(options);
  const r = await analysisCall<{ grid: number; width: number; height: number; bounds: BBox }>("loadGrid", {
    values: f64.buffer, width, height, res: [Math.abs(rx) / scale, Math.abs(ry) / scale], origin, step: [rx, ry], crs: crs ?? 4326,
  }, [f64.buffer]);
  return new DemGrid(r.grid, r.width, r.height, r.bounds);
}

/** Mosaics the DEM tiles of `tiles` (a `{z}/{x}/{y}` http(s) template) covering `bounds` into a grid. */
export async function loadDem(tiles: string, options: DemOptions): Promise<DemGrid> {
  startAnalysis(options);
  const template = resolveTemplate(tiles, document.baseURI, "analysis: DEM tiles");
  const r = await analysisCall<{ grid: number; width: number; height: number; bounds: BBox }>("loadDem", {
    url: template, z: options.zoom, bounds: options.bounds, encoding: encodingArgs(options.encoding),
  });
  return new DemGrid(r.grid, r.width, r.height, r.bounds);
}

/**
 * The elevations at `positions` from the DEM tiles of `tiles` (`encoding`, up to `maxZoom`, default
 * 14): the tiles around them at the deepest zoom that fits one grid, sampled as `DemGrid.sample`
 * (a tile the server does not have counts as 0 m, as in `loadDem`).
 */
export async function sampleDem(
  tiles: string,
  positions: ArrayLike<[number, number]>,
  options: AnalysisOptions & { encoding?: DemEncoding; maxZoom?: number; tileSize?: number } = {},
): Promise<Float64Array> {
  if (positions.length === 0) return new Float64Array(0);
  const bounds: BBox = [Infinity, Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i++) {
    const [lng, lat] = positions[i];
    bounds[0] = Math.min(bounds[0], lng);
    bounds[1] = Math.min(bounds[1], lat);
    bounds[2] = Math.max(bounds[2], lng);
    bounds[3] = Math.max(bounds[3], lat);
  }
  if (!bounds.every(Number.isFinite)) throw new Error("mbt-map: analysis: positions must be finite [lng, lat] pairs");
  const zoom = demZoom(bounds, options.maxZoom ?? 14, options.tileSize);
  const grid = await loadDem(tiles, { ...options, zoom, bounds });
  try {
    return await grid.sample(positions);
  } finally {
    grid.dispose();
  }
}

type Feature = { type?: string; properties?: Record<string, unknown> | null; geometry: { type: string; coordinates: unknown } };

/** `features` loaded, `op` run on the dataset, the result as GeoJSON features; every dataset disposed. */
async function onFeatures(features: Feature[], op: (d: Table) => Promise<Table>, options: AnalysisOptions): Promise<Feature[]> {
  const d = await fromGeoJSON({ type: "FeatureCollection", features: features.map((f) => ({ type: "Feature", properties: f.properties ?? {}, geometry: f.geometry })) }, options);
  try {
    const r = await op(d);
    try {
      return (await r.toGeoJSON()).features as Feature[];
    } finally {
      r.dispose();
    }
  } finally {
    d.dispose();
  }
}

/** `features` split by `line` (a LineString), as `Table.split`: what mbt-map/draw's `geometry.split` takes. */
export async function splitFeatures(features: Feature[], line: Feature["geometry"], options: AnalysisOptions = {}): Promise<Feature[]> {
  const cut = await fromGeoJSON({ type: "Feature", properties: {}, geometry: line }, options);
  try {
    return await onFeatures(features, (d) => d.split(cut), options);
  } finally {
    cut.dispose();
  }
}

/** `features` as one, as `Table.merge`: what mbt-map/draw's `geometry.merge` takes. */
export async function mergeFeatures(features: Feature[], options: AnalysisOptions = {}): Promise<Feature> {
  return (await onFeatures(features, (d) => d.merge(), options))[0];
}

/**
 * x, y pairs taken from `from` to `to` (NaN where a projection cannot reach),
 * in the analysis worker; the first call loads the geometry module.
 */
export async function transform(coords: ArrayLike<number>, from: Crs, to: Crs, options: AnalysisOptions = {}): Promise<Float64Array> {
  const codes = { from: await crsArg(from), to: await crsArg(to) };
  startAnalysis(options);
  const buffer = Float64Array.from(coords).buffer;
  if (buffer.byteLength % 16 !== 0) throw new Error("mbt-map: analysis: coordinates must come in x, y pairs");
  return analysisCall<Float64Array>("transform", { coords: buffer, ...codes }, [buffer]);
}


/** Stops the analysis worker; tables in it are lost and pending calls reject. */
export function terminate(): void {
  analysisClient.terminate();
}
