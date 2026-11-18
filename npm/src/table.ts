// `mbt-map/table`: features in tables, read and written in the data worker (CSV, WKT, WKB, shapefiles,
// TopoJSON, KML/KMZ, GPX, FlatGeobuf, GeoJSON) and analysed in the analysis worker (matching Turf.js, flatbush,
// Clipper2, JTS, concaveman, d3, GDAL and Arquero); each worker and module loads on its first use.
import { tableInfo, tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";
import { analysisCall, analysisClient, dataClient, free, live, named, startAnalysis, startData, type AnalysisOptions, type DataOptions } from "./clients";
import { crsArg as crsArgOf, type Crs } from "./crs";
import { bboxArg, csvArgs, csvWriteArgs, formatOf, shapefileParts, type CsvOptions, type CsvWriteOptions, type DataFormat, type ShapefileParts, type WriteFormat } from "./data-format";
import { Packer } from "./pack";
import { packPattern } from "./relate-pattern";
import { httpUrl, type TransformedRequest } from "./urls";

export { defineCrs } from "./clients";
export { formatOf };
export type { AnalysisOptions, Crs, CsvOptions, CsvWriteOptions, DataFormat, DataOptions, ShapefileParts, WriteFormat };

/** `[minX, minY, maxX, maxY]` in degrees. */
export type BBox = [number, number, number, number];

const crsArg = (crs: Crs) => crsArgOf(crs, "analysis", named);

/**
 * How `buffer` measures its distance: `"geodesic"` on the ground (true meters
 * anywhere), `"planar"` in a projected CRS's plane (`crs`, Web Mercator by default).
 */
export type BufferMode = "geodesic" | "planar";

/**
 * `mode` (default `"geodesic"`); `join` and `cap` (default `"round"`); `arcTolerance`: how far round
 * edges may stray from true arcs in meters (default distance / 500); `crs`: the projected CRS a
 * planar buffer is measured in (default EPSG:3857).
 */
export interface BufferOptions {
  mode?: BufferMode;
  join?: "round" | "miter" | "square" | "bevel";
  cap?: "round" | "butt" | "square";
  arcTolerance?: number;
  crs?: Crs;
}

/**
 * A style expression (`["==", ["get", "kind"], "park"]`, as a map's layers take), or a literal. In a
 * table it reads a row: `["get", name]` its properties, `["geometry-type"]` its geometry's GeoJSON type
 * (`"Unknown"` without one) and `["id"]` nothing; `["zoom"]` is 0.
 */
export type Expression = string | number | boolean | null | readonly unknown[];

/** A column for `Table.derive`: an expression computed per row, or a value per row as given. */
export type Derived = Expression | ArrayBufferView | { values: ArrayLike<unknown> };

/** A value of each row: a column's name or an expression. */
export type RowValue = string | readonly unknown[];

/** A key for `Table.groupby`: a column's name, or names for the keys with the value of each. */
export type GroupKey = string | Record<string, RowValue>;

/**
 * An aggregate for `rollup`, named as Arquero's: `["count"]`, or one of `valid`, `distinct`, `sum`, `mean`, `min`,
 * `max`, `median`, `any`, `variance`, `stdev`, `mode` and `product` with a value, or `["quantile", value, fraction]`.
 */
export type Aggregate = readonly ["count"] | readonly [string, RowValue] | readonly ["quantile", RowValue, number];

// `@tableops.Aggregate`'s cases in their order: an aggregate goes to table.wasm as its place here.
const AGGREGATES = ["count", "valid", "distinct", "sum", "mean", "min", "max", "median", "any", "variance", "stdev", "quantile", "mode", "product"];

// Packs `aggregates` as table.wasm reads a rollup's outputs (docs/dev/FORMATS.md "Table operations").
function outputsOf(p: Packer, aggregates: Record<string, Aggregate>): Packer {
  const outputs = Object.entries(aggregates ?? {});
  p.u32(outputs.length);
  for (const [name, how] of outputs) {
    const [op, value = null, fraction = 0.5] = (Array.isArray(how) ? how : []) as unknown[];
    const code = AGGREGATES.indexOf(op as string);
    const takes = op === "count" ? 1 : op === "quantile" ? 3 : 2;
    if (code < 0 || how.length !== takes || !Number.isFinite(fraction)) throw new Error(`mbt-map: analysis: ${name}: not an aggregate: ${JSON.stringify(how)}`);
    p.utf8(name).u8(code).f64(fraction as number).json(value);
  }
  return p;
}

/** How `spatialJoin` and `nearestJoin` put rows together: as `join`'s `left` and `suffix`, or `rollup` to aggregate the other table's rows per row. */
export interface PairOptions extends JoinOptions {
  rollup?: Record<string, Aggregate>;
}

/** A table's rows in groups: what `Table.groupby` gives. */
export interface Grouped {
  /** One row without geometry per group, in the order the groups first come: the keys, then `aggregates`. */
  rollup(aggregates: Record<string, Aggregate>): Promise<Table>;
}

/** The columns `Table.join` matches: one name (or `[names]`) for the same columns in both tables, or `[left, right]`, each a name or names. */
export type JoinKeys = string | readonly [string | readonly string[]] | readonly [string | readonly string[], string | readonly string[]];

/** `left` keeps the rows without a match; `suffix` is added to a name both tables have (`["_1", "_2"]`). */
export interface JoinOptions {
  left?: boolean;
  suffix?: readonly [string?, string?];
}

/** A key for `Table.orderby`: a column's name or an expression, ascending unless `descending`. */
export type OrderKey = string | readonly unknown[] | { by: string | readonly unknown[]; descending?: boolean };

/** What a column's cells hold: one kind, `"mixed"`, or `"null"` when none holds a value. */
export type ColumnType = "number" | "string" | "boolean" | "mixed" | "null";

/** `crs`: the CRS of the data's coordinates (default EPSG:4326); they are kept as longitude and latitude. */
export interface LoadOptions extends AnalysisOptions {
  crs?: Crs;
}

/** `crs`: the CRS of the data's coordinates (default EPSG:4326); they are kept as longitude and latitude. */
export interface LoadOptions extends AnalysisOptions {
  crs?: Crs;
}

/** A routable graph of lines (`Table.network`). */
export class Network {
  #id: number;
  #generation = analysisClient.generation;
  #disposed = false;

  /** @internal */
  constructor(id: number) {
    this.#id = id;
  }

  /**
   * The shortest path between two vertices of the network (`[lng, lat]`, within its tolerance) as
   * geojson-path-finder finds it: its coordinates and length in kilometers; null where none joins them.
   */
  async route(from: [number, number], to: [number, number]): Promise<{ path: [number, number][]; weight: number } | null> {
    const network = live(this.#id, this.#generation, this.#disposed, "network");
    if (!isPoint(from) || !isPoint(to)) throw new Error("mbt-map: analysis: invalid points");
    const v = await analysisCall<Float64Array>("route", { network, from, to });
    if (v.length === 0) return null;
    return { weight: v[0], path: Array.from({ length: (v.length - 1) / 2 }, (_, i): [number, number] => [v[1 + i * 2], v[2 + i * 2]]) };
  }

  /** Frees the network in the worker; later routes reject. */
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    free("disposeNetwork", { network: this.#id }, this.#generation);
  }
}

/** `Table.interpolate`'s options. */
export interface InterpolateOptions {
  gridType?: "square" | "point" | "hex" | "triangle";
  property?: string;
  weight?: number;
}

/** `Table.density`'s options. */
export interface DensityOptions {
  bbox?: BBox;
  width?: number;
  height?: number;
  cellSize?: number;
  bandwidth?: number;
  thresholds?: number;
  weight?: string;
}

/** What a DBSCAN point is. */
export type DbscanKind = "core" | "edge" | "noise";
// By the codes DBSCAN_* of surface_worker's clusters (clusters/dbscan.mbt).
const DBSCAN_KINDS: DbscanKind[] = ["core", "edge", "noise"];

// surface_worker's grid codes.
const GRIDS = { point: 0, square: 1, hex: 2, triangle: 3 } as const;

/**
 * A grid over `bbox` as Turf makes it (`cellSide` in kilometers): `point` (pointGrid), `square`
 * (squareGrid), `hex` (hexGrid; `triangles` splits each hexagon in six) or `triangle` (triangleGrid).
 */
export async function grid(bbox: BBox, cellSide: number, type: keyof typeof GRIDS = "square", options: AnalysisOptions & { triangles?: boolean } = {}): Promise<Table> {
  if (!isBox(bbox) || !(cellSide > 0 && cellSide < Infinity) || !(type in GRIDS)) throw new Error("mbt-map: analysis: invalid grid");
  startAnalysis(options);
  const fn = ["point_grid", "square_grid", "hex_grid", "triangle_grid"][GRIDS[type]];
  return tableOf(analysisCall("surface", { dataset: -1, fn, args: [...bbox, cellSide, options.triangles ? 1 : 0] }));
}

/** Where a feature's lines come nearest to a point (`Table.nearestPointOnLine`). */
export interface NearestOnLine {
  point: [number, number];
  dist: number;
  location: number;
  index: number;
  multiFeatureIndex: number;
}

const isPoint = (p: unknown): p is [number, number] => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite);
const isBox = (b: unknown): b is BBox => Array.isArray(b) && b.length === 4 && b.every(Number.isFinite);

// Codes of geometry_worker/geometry.mbt.
const JOIN = { round: 0, miter: 1, square: 2, bevel: 3 } as const;
const CAP = { round: 0, butt: 1, square: 2 } as const;
const OVERLAY = { clip: 0, erase: 1, intersect: 2, split: 3 } as const;

// The predicates of relate_worker/relate.mbt, by code.
const RELATIONS = ["intersects", "contains", "within", "covers", "coveredBy", "touches", "crosses", "overlaps", "equals"] as const;

/** A spatial relation as JTS names it (`Geometry.intersects`, `contains`, …, `equals` for `equalsTopo`). */
export type Relation = (typeof RELATIONS)[number];

// Mirrors MEASURE_* in analysis_worker/datasets.mbt.
const MEASURE = { area: 0, length: 1, centroid: 2, bbox: 3 } as const;

/** What `Table.toGeoJSON` gives: a feature per row, its geometry null without one. */
export interface TableFeatureCollection {
  type: "FeatureCollection";
  features: { type: "Feature"; id?: string | number; geometry: { type: string; coordinates: unknown } | null; properties: Record<string, unknown> }[];
}

/** A read's result as the data worker gives it (docs/dev/FORMATS.md "Data worker messages"), and where it came from. */
interface ReadResult {
  table: ArrayBuffer;
  ids: ArrayBuffer | null;
  layer: string | null;
  layers: string[];
}

/** A table the analysis worker made (docs/dev/FORMATS.md "Analysis worker messages"). */
interface WorkerTable {
  dataset: number;
  features: number;
  columns: string[];
}

async function tableOf(r: Promise<WorkerTable>): Promise<Table> {
  return new Table(await r);
}

/**
 * Features in columns: `length` rows and `columns`, the property keys; a table that was read has its `format`,
 * `layer` and the input's `layers`. The rows stay on the page until the first operation moves them into the
 * analysis worker, where results stay too (docs/data.md); `dispose` frees them.
 */
export class Table {
  readonly length: number;
  readonly columns: readonly string[];
  readonly format: DataFormat | null;
  readonly layer: string | null;
  readonly layers: readonly string[];
  // The rows while on the page, and where to start the analysis worker for them.
  #held: { bytes: ArrayBuffer; analysis: AnalysisOptions } | null = null;
  // The rows' ids as read (docs/dev/FORMATS.md "Data worker messages"): operations give tables without.
  #ids: ArrayBuffer | null = null;
  #moving: Promise<number> | null = null;
  #id = -1;
  #generation = analysisClient.generation;
  #disposed = false;

  /** @internal */
  constructor(from: WorkerTable | (ReadResult & { format: DataFormat; analysis: AnalysisOptions })) {
    if ("dataset" in from) {
      this.#id = from.dataset;
      this.length = from.features;
      this.columns = Object.freeze(from.columns.slice());
      this.format = this.layer = null;
      this.layers = Object.freeze([]);
      return;
    }
    const { length, columns } = tableInfo(from.table);
    this.length = length;
    this.columns = Object.freeze(columns);
    this.format = from.format;
    this.layer = from.layer;
    this.layers = Object.freeze(from.layers.slice());
    this.#held = { bytes: from.table, analysis: from.analysis };
    this.#ids = from.ids;
  }

  // The table's id in the analysis worker, its rows moved there (not copied) on the first call.
  async #worker(role = ""): Promise<number> {
    if (this.#disposed) throw new Error(`mbt-map: analysis: the ${role}dataset was disposed`);
    if (this.#held) {
      const { bytes, analysis } = this.#held;
      this.#held = null;
      startAnalysis(analysis);
      this.#generation = analysisClient.generation;
      this.#moving = analysisClient.call<WorkerTable>("load", { table: bytes }, [bytes]).then((r) => (this.#id = r.dataset));
    }
    if (this.#moving) await this.#moving;
    return live(this.#id, this.#generation, this.#disposed, `${role}dataset`);
  }

  async #call<T>(op: string, args: object = {}): Promise<T> {
    return analysisCall<T>(op, { dataset: await this.#worker(), ...args });
  }

  /** Each feature's area in square meters (0 for points and lines). */
  areas(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.area });
  }

  /** Each feature's length in meters, rings included (0 for points). */
  lengths(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.length });
  }

  /** Each feature's centroid as x, y pairs (the mean of its points, as Turf's `centroid`). */
  centroids(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.centroid });
  }

  /** Each feature's box as min x, min y, max x, max y. */
  bboxes(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.bbox });
  }

  /** The features whose boxes meet `bbox`. */
  search(bbox: BBox): Promise<Int32Array> {
    return this.#call("search", { bbox });
  }

  /** Up to `k` features nearest to (x, y) by box distance in degrees, nearest first. */
  nearest(x: number, y: number, { k = 1, maxDistance = Infinity }: { k?: number; maxDistance?: number } = {}): Promise<Int32Array> {
    return this.#call("nearest", { x, y, k, maxDistance });
  }

  /** This dataset's point features with a point inside some polygon of `polygons` (boundaries count). */
  async pointsWithin(polygons: Table): Promise<Int32Array> {
    return analysisCall("within", { points: await this.#worker("points "), polygons: await polygons.#worker("polygons ") });
  }

  /** Point counts of a `cols` x `rows` grid over `bbox`, row by row from its south edge. */
  grid(bbox: BBox, cols: number, rows: number): Promise<Int32Array> {
    return this.#call("grid", { bbox, cols, rows });
  }

  /**
   * The pairs of a feature here and a feature of `other` in `relation` (JTS's predicates on
   * longitude and latitude as a plane) or matching a DE-9IM `pattern`, as `[i0, j0, i1, j1, …]`
   * by `i` then `j`. Only features whose boxes meet are tested, so `disjoint` is not offered.
   */
  async relate(other: Table, relation: Relation | { pattern: string }): Promise<Int32Array> {
    const predicate = typeof relation === "string" ? RELATIONS.indexOf(relation) : -1;
    if (typeof relation === "string" && predicate < 0) throw new Error(`mbt-map: analysis: unknown relation ${relation}`);
    const pattern = typeof relation === "string" ? 0 : packPattern(relation.pattern);
    return analysisCall("relate", { a: await this.#worker("related "), b: await other.#worker("relating "), predicate, pattern });
  }

  async #shapes(shape: string, args: number[] = []): Promise<Table> {
    return tableOf(analysisCall("shapes", { dataset: await this.#worker("shaped "), shape, args }));
  }

  /**
   * Every feature simplified as Turf's `simplify` does (radial distance, then Douglas-Peucker;
   * `highQuality` skips the first), `tolerance` in degrees; properties kept.
   */
  async simplify({ tolerance = 1, highQuality = false }: { tolerance?: number; highQuality?: boolean } = {}): Promise<Table> {
    if (!(tolerance >= 0 && tolerance < Infinity)) throw new Error("mbt-map: analysis: invalid tolerance");
    return this.#shapes("simplify", [tolerance, highQuality ? 1 : 0]);
  }

  /** The convex hull of every vertex here as one polygon (Turf's `convex`), or no feature for fewer than three. */
  convexHull(): Promise<Table> {
    return this.#shapes("convex");
  }

  /**
   * A concave hull of every vertex here as one polygon (concaveman's: `concavity` from 1, tight, up;
   * edges shorter than `lengthThreshold` degrees stay), or no feature for fewer than three.
   */
  async concaveHull({ concavity = 2, lengthThreshold = 0 }: { concavity?: number; lengthThreshold?: number } = {}): Promise<Table> {
    if (!(concavity > 0) || !(lengthThreshold >= 0)) throw new Error("mbt-map: analysis: invalid concave hull options");
    return this.#shapes("concave", [concavity, lengthThreshold]);
  }

  /** The Delaunay triangles of the points here as polygons, in d3-delaunay's order. */
  delaunay(): Promise<Table> {
    return this.#shapes("delaunay");
  }

  /**
   * The Voronoi cell of each point here, cut to `bbox`, with that point's properties (d3-delaunay's
   * `cellPolygon`); a point without a cell (a duplicate) keeps its row without geometry.
   */
  async voronoi(bbox: BBox): Promise<Table> {
    if (!isBox(bbox) || bbox[0] > bbox[2] || bbox[1] > bbox[3]) throw new Error("mbt-map: analysis: invalid bbox");
    return this.#shapes("voronoi", bbox);
  }

  /** Each line cut between the points on it nearest to `start` and `stop`, as Turf's `lineSlice`; properties kept. */
  async lineSlice(start: [number, number], stop: [number, number]): Promise<Table> {
    if (!isPoint(start) || !isPoint(stop)) throw new Error("mbt-map: analysis: invalid points");
    return this.#shapes("line_slice", [...start, ...stop]);
  }

  /**
   * Per feature, the point of its lines nearest to (x, y) as Turf's `nearestPointOnLine`: where it is,
   * its distance (`dist`, km), how far along the line (`location`, km), the segment (`index`) and line
   * (`multiFeatureIndex`); null for features without lines.
   */
  async nearestPointOnLine(x: number, y: number): Promise<(NearestOnLine | null)[]> {
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error("mbt-map: analysis: invalid point");
    const v = await this.#call<Float64Array>("nearestOnLine", { x, y });
    return Array.from({ length: v.length / 6 }, (_, i) => {
      const [px, py, dist, location, index, multiFeatureIndex] = v.subarray(i * 6, i * 6 + 6);
      return Number.isNaN(px) ? null : { point: [px, py] as [number, number], dist, location, index, multiFeatureIndex };
    });
  }

  async #surface(fn: string, args: number[], text = "", numbers: number[] = []): Promise<Table> {
    return tableOf(analysisCall("surface", { dataset: await this.#worker("used "), fn, args, text, numbers }));
  }

  /**
   * A grid over the box of the points here, each cell with the `property` value interpolated from
   * the points' by inverse distance weighting (Turf's `interpolate`): `gridType` `square` (default),
   * `point`, `hex` or `triangle`, `cellSize` in kilometers, `weight` the power of the distance.
   */
  async interpolate(cellSize: number, { gridType = "square", property = "elevation", weight = 1 }: InterpolateOptions = {}): Promise<Table> {
    if (!(cellSize > 0 && cellSize < Infinity) || !(gridType in GRIDS) || !Number.isFinite(weight)) throw new Error("mbt-map: analysis: invalid interpolation options");
    return this.#surface("interpolate", [cellSize, GRIDS[gridType], weight], property);
  }

  /** Lines where the grid of points here (a `pointGrid`) crosses each of `breaks` in `zProperty` (Turf's `isolines`). */
  async isolines(breaks: number[], { zProperty = "elevation" }: { zProperty?: string } = {}): Promise<Table> {
    if (!Array.isArray(breaks) || !breaks.every(Number.isFinite)) throw new Error("mbt-map: analysis: invalid breaks");
    return this.#surface("isolines", [], zProperty, breaks);
  }

  /** Polygons of the grid of points here between each two of `breaks` in `zProperty` (Turf's `isobands`). */
  async isobands(breaks: number[], { zProperty = "elevation" }: { zProperty?: string } = {}): Promise<Table> {
    if (!Array.isArray(breaks) || !breaks.every(Number.isFinite)) throw new Error("mbt-map: analysis: invalid breaks");
    return this.#surface("isobands", [], zProperty, breaks);
  }

  /**
   * Contours of the points' kernel density as d3-contour's `contourDensity` draws them (its defaults too), on a
   * `width` x `height` pixel grid over `bbox` (by default the points' box; `cellSize`, `bandwidth` √420 in pixels,
   * `thresholds` how many), each a MultiPolygon with its density `value`; `weight` names a property.
   */
  async density({ bbox, width = 960, height = 500, cellSize = 4, bandwidth = 20.4939015319192, thresholds = 20, weight }: DensityOptions = {}): Promise<Table> {
    const box = bbox ?? [NaN, NaN, NaN, NaN];
    if (![width, height, cellSize, bandwidth].every(Number.isFinite) || !(width > 0 && height > 0 && cellSize >= 1 && bandwidth >= 0 && Number.isInteger(thresholds) && thresholds >= 0) || box.length !== 4) {
      throw new Error("mbt-map: analysis: invalid density options");
    }
    return this.#surface("density", [...box, width, height, cellSize, bandwidth, thresholds, weight === undefined ? 0 : 1], weight ?? "");
  }

  /**
   * The table with DBSCAN over its points as Turf's `clustersDbscan` gives it (`maxDistance` in kilometers): the
   * columns `cluster` (a point's cluster; missing for noise) and `dbscan` (`core`, `edge` or `noise`). Rows that
   * are not points get neither.
   */
  async dbscan(maxDistance: number, { minPoints = 3 }: { minPoints?: number } = {}): Promise<Table> {
    if (!(maxDistance >= 0) || !Number.isInteger(minPoints) || minPoints < 1) throw new Error("mbt-map: analysis: invalid DBSCAN options");
    const v = await this.#call<Float64Array>("surface", { fn: "dbscan", args: [maxDistance, minPoints] });
    const rows = Array.from({ length: v.length / 2 }, (_, i) => i);
    return this.derive({
      cluster: { values: rows.map((i) => (v[i * 2] < 0 ? undefined : v[i * 2])) },
      dbscan: { values: rows.map((i) => DBSCAN_KINDS[v[i * 2 + 1]]) },
    });
  }

  /**
   * The table with k-means over its points as Turf's `clustersKmeans` gives it (`k` by default
   * `round(sqrt(n / 2))`): the columns `cluster` and its centroid's `centroid_x` and `centroid_y`. Rows that
   * are not points get none.
   */
  async kmeans(k?: number): Promise<Table> {
    if (k !== undefined && !(Number.isInteger(k) && k > 0)) throw new Error("mbt-map: analysis: invalid k");
    const v = await this.#call<Float64Array>("surface", { fn: "kmeans", args: [k ?? 0] });
    const n = v[0];
    const clusters = Array.from(v.subarray(1, 1 + n), (c) => (c < 0 ? undefined : c));
    const centroid = (at: number) => ({ values: clusters.map((c) => (c === undefined ? undefined : v[1 + n + c * 2 + at])) });
    return this.derive({ cluster: { values: clusters }, centroid_x: centroid(0), centroid_y: centroid(1) });
  }

  /**
   * geojson-path-finder's graph of the lines here (`tolerance` in degrees: vertices this close are one), kept
   * in the worker for `Network.route` until disposed. With `snap` (meters), a line's end within `snap` of
   * another line's segment is joined to it at its nearest point, and ends that close to each other become one.
   */
  async network({ tolerance = 1e-5, snap = 0 }: { tolerance?: number; snap?: number } = {}): Promise<Network> {
    if (!(tolerance > 0)) throw new Error("mbt-map: analysis: invalid tolerance");
    if (!(snap >= 0 && snap < Infinity)) throw new Error("mbt-map: analysis: invalid snap");
    return new Network(await this.#call<number>("network", { tolerance, snap }));
  }

  /** The DE-9IM matrix of feature `i` here and feature `j` of `other`, as JTS writes it (`"FF2F11212"`). */
  async relateMatrix(other: Table, i: number, j: number): Promise<string> {
    if (!Number.isInteger(i) || !Number.isInteger(j) || i < 0 || j < 0) throw new Error("mbt-map: analysis: invalid feature indices");
    return analysisCall("relate", { a: await this.#worker("related "), b: await other.#worker("relating "), predicate: 0, pattern: 0, pair: [i, j] });
  }

  /**
   * Every feature grown by `meters` as polygons with its properties. A negative distance shrinks polygons and
   * empties lines and points; vanished features keep their row without geometry. A geodesic buffer takes at
   * most 10,000 km, a planar one 1e9 of the CRS's units.
   */
  async buffer(meters: number, { mode = "geodesic", join = "round", cap = "round", arcTolerance = 0, crs = 3857 }: BufferOptions = {}): Promise<Table> {
    if (!(mode in { geodesic: 0, planar: 1 }) || !(join in JOIN) || !(cap in CAP) || !Number.isFinite(meters) || !(arcTolerance >= 0)) {
      throw new Error("mbt-map: analysis: invalid buffer options");
    }
    const code = await crsArg(crs);
    return tableOf(analysisCall("buffer", {
      dataset: await this.#worker("buffered "), meters, mode: mode === "planar" ? 1 : 0, join: JOIN[join], cap: CAP[cap], arcTolerance, crs: code,
    }));
  }

  /**
   * All polygons merged into one feature without properties (lines and points are left out); with `by` (a
   * column's name or names), a feature per group of rows with equal values there, as `groupby` groups them,
   * holding those columns (no geometry for a group without polygons).
   */
  async dissolve({ by = [] }: { by?: string | readonly string[] } = {}): Promise<Table> {
    const names = typeof by === "string" ? [by] : by;
    if (!Array.isArray(names) || !names.every((c) => typeof c === "string")) throw new Error("mbt-map: analysis: dissolve groups by column names");
    const p = new Packer().u32(names.length);
    for (const name of names) p.utf8(name);
    const args = p.finish();
    return tableOf(analysisCall("dissolve", { dataset: await this.#worker("dissolved "), by: args }, [args]));
  }

  async #overlay(other: Table, kind: keyof typeof OVERLAY, roles: [string, string]): Promise<Table> {
    return tableOf(analysisCall("overlay", { a: await this.#worker(roles[0]), b: await other.#worker(roles[1]), kind: OVERLAY[kind] }));
  }

  /** This dataset's features cut to the area of `other`'s polygons, with their properties. */
  clip(other: Table): Promise<Table> {
    return this.#overlay(other, "clip", ["clipped ", "clipping "]);
  }

  /** This dataset's features without the area of `other`'s polygons, with their properties. */
  erase(other: Table): Promise<Table> {
    return this.#overlay(other, "erase", ["erased ", "erasing "]);
  }

  /**
   * One feature per overlap of a feature here with a polygon of `other`, with
   * the properties of both (`other`'s keys also found here get the suffix `_2`).
   */
  intersect(other: Table): Promise<Table> {
    return this.#overlay(other, "intersect", ["intersected ", "intersecting "]);
  }

  /**
   * Each feature split by `lines`' lines, its pieces as features with its properties: a polygon by
   * the stretches that cross it from edge to edge, a line where they cross it; the rest stays whole.
   */
  split(lines: Table): Promise<Table> {
    return this.#overlay(lines, "split", ["split ", "splitting "]);
  }

  /**
   * The features as one with the first one's properties: polygons united, lines joined end to end,
   * points gathered; rejects when their kinds differ.
   */
  async merge(): Promise<Table> {
    return tableOf(analysisCall("merge", { dataset: await this.#worker("merged ") }));
  }

  async #rows(fn: string, args: ArrayBuffer, numbers: number[] = []): Promise<Table> {
    return tableOf(analysisCall("rows", { dataset: await this.#worker(), fn, args, numbers }, [args]));
  }

  /** The table with only `columns`, in that order (Arquero's `select`); rejects for a name that is not a column. */
  async select(columns: readonly string[]): Promise<Table> {
    if (!Array.isArray(columns) || !columns.every((c) => typeof c === "string")) throw new Error("mbt-map: analysis: select takes column names");
    const p = new Packer().u32(columns.length);
    for (const name of columns) p.utf8(name);
    return this.#rows("select", p.finish());
  }

  /**
   * The rows for which `criteria` is true (Arquero's `filter`; an error or another value drops the
   * row), or the rows numbered by an integer array such as `search` and `nearest` give, in its order.
   */
  async filter(criteria: Expression | ArrayBufferView): Promise<Table> {
    if (ArrayBuffer.isView(criteria)) {
      const rows = Uint32Array.from(criteria as unknown as ArrayLike<number>);
      if (!rows.every((r, i) => r === (criteria as unknown as ArrayLike<number>)[i])) throw new Error("mbt-map: analysis: rows must be whole numbers from 0");
      return this.#rows("take", rows.buffer);
    }
    return this.#rows("filter", new Packer().json(criteria).finish());
  }

  /** Rows `start` up to `end` (not included), counted from the end when negative, as `Array.prototype.slice`. */
  async slice(start = 0, end = Infinity): Promise<Table> {
    const at = (i: number) => {
      const n = Math.trunc(Number(i)) || 0;
      return Math.max(0, Math.min(this.length, n < 0 ? this.length + n : n));
    };
    return this.#rows("slice", new ArrayBuffer(0), [at(start), at(end)]);
  }

  /**
   * The table with `columns` (Arquero's `derive`): each an expression computed per row (a result that is not a
   * boolean, number or string is null) or a value per row (a typed array, or `{ values }`; `undefined` leaves the
   * row without the key). One named as an existing column replaces it; the others follow.
   */
  async derive(columns: Record<string, Derived>): Promise<Table> {
    const entries = Object.entries(columns ?? {});
    const p = new Packer().u32(entries.length);
    for (const [name, how] of entries) {
      p.utf8(name);
      const given = ArrayBuffer.isView(how) ? (how as unknown as ArrayLike<unknown>) : how !== null && typeof how === "object" && !Array.isArray(how) ? (how as { values: ArrayLike<unknown> }).values : null;
      if (given === null) {
        p.u8(0).json(how);
        continue;
      }
      if (typeof given?.length !== "number") throw new Error(`mbt-map: analysis: ${name}: values must be an array`);
      p.u8(1).u32(given.length);
      for (let i = 0; i < given.length; i++) p.value(given[i]);
    }
    return this.#rows("derive", p.finish());
  }

  /**
   * The rows ordered by `keys`, the first key first (Arquero's `orderby`): null first, then numbers
   * and strings as JavaScript's `<` orders them, the other way for a `descending` key; rows equal on
   * every key keep their order.
   */
  async orderby(...keys: OrderKey[]): Promise<Table> {
    const p = new Packer().u32(keys.length);
    for (const key of keys) {
      const { by, descending = false } = typeof key === "object" && key !== null && !Array.isArray(key) ? (key as { by: string | readonly unknown[]; descending?: boolean }) : { by: key as string | readonly unknown[] };
      if (typeof by !== "string" && !Array.isArray(by)) throw new Error("mbt-map: analysis: an order key is a column name or an expression");
      p.u8(descending ? 1 : 0).json(typeof by === "string" ? ["get", by] : by);
    }
    return this.#rows("orderby", p.finish());
  }

  /**
   * The rows in groups of equal `keys` (Arquero's `groupby`; null and a missing key are one group, a number and
   * its text are two), for `rollup`.
   */
  groupby(...keys: GroupKey[]): Grouped {
    const pairs = keys.flatMap((k): [string, unknown][] => (typeof k === "string" ? [[k, k]] : Object.entries(k ?? {})));
    return { rollup: (aggregates) => this.#rollup(pairs, aggregates) };
  }

  /**
   * One row without geometry holding `aggregates` of every row (Arquero's `rollup`): they skip null, missing and
   * NaN values, and are null without a value left (docs/data.md has each).
   */
  rollup(aggregates: Record<string, Aggregate>): Promise<Table> {
    return this.#rollup([], aggregates);
  }

  async #rollup(keys: [string, unknown][], aggregates: Record<string, Aggregate>): Promise<Table> {
    const p = new Packer().u32(keys.length);
    for (const [name, value] of keys) p.utf8(name).json(value);
    return this.#rows("rollup", outputsOf(p, aggregates).finish());
  }

  // The rows beside (or, with `rollup`, aggregating) the rows of `other` that `pairs` give them.
  async #pairs(other: Table, pairs: Int32Array, { left = false, suffix = [], rollup }: PairOptions): Promise<Table> {
    const p = new Packer().u8(rollup ? 2 : left ? 1 : 0).utf8(suffix[0] ?? "_1").utf8(suffix[1] ?? "_2").u32(pairs.length).bytes(pairs);
    const args = (rollup ? outputsOf(p, rollup) : p).finish();
    return tableOf(analysisCall("rows", { dataset: await this.#worker("joined "), other: await other.#worker("joining "), fn: "pairs", args }, [args]));
  }

  /**
   * The rows beside the rows of `other` they are in `predicate` with (a relation of `relate`, or
   * `{ pattern }`; `intersects` by default), as `join` puts them: this table's geometry and columns, then
   * `other`'s columns. With `rollup`, every row once, with those aggregates of the rows of `other` it meets.
   */
  async spatialJoin(other: Table, options: PairOptions & { predicate?: Relation | { pattern: string } } = {}): Promise<Table> {
    return this.#pairs(other, await this.relate(other, options.predicate ?? "intersects"), options);
  }

  /**
   * The rows beside their `k` nearest rows of `other` (1 by default) within `maxDistance`, as `nearest`
   * measures from the center of a row's box: put as `spatialJoin` puts them, `rollup` too.
   */
  async nearestJoin(other: Table, options: PairOptions & { k?: number; maxDistance?: number } = {}): Promise<Table> {
    if (!(other instanceof Table)) throw new Error("mbt-map: analysis: a join takes a table");
    const { k = 1, maxDistance = Infinity } = options;
    const pairs = await analysisCall<Int32Array>("nearestPairs", { a: await this.#worker("joined "), b: await other.#worker("joining "), k, maxDistance });
    return this.#pairs(other, pairs, options);
  }

  /**
   * The rows beside the rows of `other` with equal keys in type and value (Arquero's `join`; null never
   * matches): this table's geometry and columns, then `other`'s columns. Without `on`, the columns both have.
   */
  async join(other: Table, on?: JoinKeys, options: JoinOptions = {}): Promise<Table> {
    if (!(other instanceof Table)) throw new Error("mbt-map: analysis: join takes a table");
    const { left = false, suffix = [] } = options;
    const names = (v: unknown): unknown[] => (Array.isArray(v) ? v : [v]);
    const shared = on == null ? this.columns.filter((c) => other.columns.includes(c)) : null;
    const [l, r = l] = shared ? [shared] : typeof on === "string" ? [[on]] : names(on).map(names);
    if (!l.length || l.length !== r.length || ![...l, ...r].every((c) => typeof c === "string")) {
      throw new Error(shared ? "mbt-map: analysis: no column in both tables to join on" : "mbt-map: analysis: join keys are a column name, or [left, right] with as many names each");
    }
    const p = new Packer().u8(left ? 1 : 0).utf8(suffix[0] ?? "_1").utf8(suffix[1] ?? "_2").u32(l.length);
    l.forEach((c, i) => p.utf8(c as string).utf8(r[i] as string));
    const args = p.finish();
    return tableOf(analysisCall("rows", { dataset: await this.#worker("joined "), other: await other.#worker("joining "), fn: "join", args }, [args]));
  }

  /** The values of column `name`, one per row (Arquero's `array`): `undefined` where the row lacks the key. */
  async array(name: string): Promise<(string | number | boolean | null | undefined)[]> {
    if (typeof name !== "string") throw new Error("mbt-map: analysis: array takes a column name");
    return this.#call("column", { name });
  }

  /** What each column's cells hold. */
  async columnTypes(): Promise<Record<string, ColumnType>> {
    const counts = await this.#call<Int32Array>("columnKinds");
    const types: [string, ColumnType][] = this.columns.map((name, i) => {
      const held = (["number", "string", "boolean"] as const).filter((_, k) => counts[i * 5 + k] > 0);
      return [name, held.length === 0 ? "null" : held.length === 1 ? held[0] : "mixed"];
    });
    return Object.fromEntries(types);
  }

  /**
   * The rows as a GeoJSON FeatureCollection, a new one per call (a GeoJSON source's `data`), in `crs` if
   * given. Rows without geometry have `geometry: null`; a table that was read gives its features' ids.
   */
  async toGeoJSON({ crs }: { crs?: Crs } = {}): Promise<TableFeatureCollection> {
    if (this.#disposed) throw new Error("mbt-map: analysis: the dataset was disposed");
    const fc = this.#held && crs === undefined
      ? tableToGeoJSON(this.#held.bytes)
      : await this.#call<TableFeatureCollection>("toGeoJSON", crs === undefined ? {} : { crs: await crsArg(crs) });
    return this.#ids ? withIds(fc, this.#ids) : fc;
  }

  /**
   * The table as Arrow IPC bytes (Arquero's `toArrowIPC`): a stream, or with `format: "file"` the file format
   * (Feather). The geometry is a `geoarrow.wkb` column, or with `geometry: "native"` GeoArrow's type for the rows'
   * kind (rejects for rows of mixed kinds); docs/data.md has the columns' types. Feature ids are not written.
   */
  async toArrowIPC(options: DataOptions & { format?: "stream" | "file"; geometry?: "wkb" | "native" } = {}): Promise<Uint8Array> {
    const { format = "stream", geometry = "wkb" } = options;
    if (!["stream", "file"].includes(format) || !["wkb", "native"].includes(geometry)) throw new Error("mbt-map: data: invalid Arrow options");
    const { table } = await this.writeArgs();
    startData(options);
    return new Uint8Array(await dataClient.call<ArrayBuffer>("write", { format: "arrow", table, options: { file: format === "file", native: geometry === "native" } }, [table]));
  }

  /** @internal The rows and ids as the data worker's `write` takes them (copies). */
  async writeArgs(): Promise<{ table: ArrayBuffer; ids: ArrayBuffer | null }> {
    if (this.#disposed) throw new Error("mbt-map: analysis: the dataset was disposed");
    const table = this.#held ? this.#held.bytes.slice(0) : await this.#call<ArrayBuffer>("table");
    return { table, ids: this.#ids?.slice(0) ?? null };
  }

  /** Frees the rows (in the worker, if they are there); later calls on the table reject. */
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    if (this.#held) {
      this.#held = null;
      return;
    }
    const freed = (id: number) => free("dispose", { dataset: id }, this.#generation);
    if (this.#moving) this.#moving.then(freed, () => {});
    else freed(this.#id);
  }
}

/**
 * `format`: the reader (by default from a URL's or a File's name, see `formatOf`); `transformRequest`:
 * may change a URL's request as the map's does (no credentials are sent otherwise). `crs`: the CRS of
 * coordinates the data does not tag (a shapefile's in place of its .prj, rows without an SRID; by
 * default EPSG:4326): rows are taken to longitude and latitude. `layer`: the shapefile of a .zip
 * (its name without `.shp`, with or without folders) or the TopoJSON object to read, by default the
 * first; `encoding`: a .dbf's text encoding (a label such as `"shift_jis"` or a code page), in place
 * of its .cpg and language driver. `bbox`: `[minX, minY, maxX, maxY]` in a FlatGeobuf's coordinates,
 * to read only the features its index finds there (by HTTP range requests from a URL). `analysis`:
 * where the analysis worker is served, for the table's first operation (if it does not run yet).
 */
export interface ReadOptions extends DataOptions, CsvOptions {
  format?: DataFormat;
  transformRequest?: (url: string) => TransformedRequest | undefined;
  crs?: Crs;
  layer?: string;
  encoding?: string;
  bbox?: [number, number, number, number];
  analysis?: AnalysisOptions;
}

const FORMATS: DataFormat[] = ["csv", "wkt", "wkb", "shapefile", "topojson", "kml", "gpx", "flatgeobuf", "geojson", "arrow"];

function formatFor(options: ReadOptions, name: string | null): DataFormat {
  const format = options.format ?? (name === null ? null : formatOf(name));
  if (!FORMATS.includes(format as DataFormat)) {
    throw new Error(`mbt-map: data: ${options.format === undefined ? "the format cannot be told from the input; give options.format" : `unknown format ${String(options.format)}`}`);
  }
  return format as DataFormat;
}

type Input = string | URL | Blob | ArrayBuffer | ArrayBufferView;

/** `input` as the data worker takes a source: `{ url, init }`, `{ blob }` or `{ bytes }` (copied, and added to `transfer`). */
function sourceOf(input: Input, options: ReadOptions, transfer: Transferable[]): object {
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

async function reading(format: DataFormat, source: object, options: ReadOptions, transfer: Transferable[]): Promise<Table> {
  const { layer, encoding } = options;
  if (layer !== undefined && typeof layer !== "string") throw new Error("mbt-map: data: invalid layer");
  if (encoding !== undefined && typeof encoding !== "string") throw new Error("mbt-map: data: invalid encoding");
  if (options.crs !== undefined && (format === "kml" || format === "gpx" || format === "geojson")) throw new Error("mbt-map: data: KML, GPX and GeoJSON are always in EPSG:4326; options.crs is for other formats");
  if (options.bbox !== undefined && format !== "flatgeobuf") throw new Error("mbt-map: data: options.bbox is for FlatGeobuf");
  const bbox = options.bbox === undefined ? undefined : bboxArg(options.bbox);
  const crs = options.crs === undefined ? undefined : await crsArgOf(options.crs, "data");
  const args = { format, options: { ...(format === "csv" ? csvArgs(options) : {}), crs, layer, encoding, bbox }, ...source };
  startData(options);
  return new Table({ ...(await dataClient.call<ReadResult>("read", args, transfer)), format, analysis: options.analysis ?? {} });
}

/**
 * Reads `input`: an http(s) URL (fetched without credentials), a Blob or File, bytes (copied), a
 * shapefile's files picked together or its `{ shp, dbf, prj, cpg }` (docs/data.md has the rules).
 */
export async function read(input: Input | ArrayLike<File> | ShapefileParts<Input>, options: ReadOptions = {}): Promise<Table> {
  const transfer: Transferable[] = [];
  const files = Array.isArray(input) || (typeof FileList !== "undefined" && input instanceof FileList) ? Array.from(input as ArrayLike<File>) : null;
  if (files?.length === 1) return read(files[0], options);
  const parts = files ? shapefileParts(files) : (input as ShapefileParts<Input>)?.shp !== undefined ? (input as ShapefileParts<Input>) : null;
  if (files && !parts) throw new Error("mbt-map: data: of several files, read takes a shapefile's (one .shp and its .dbf, .prj, .cpg)");
  if (parts) {
    const format = options.format ?? "shapefile";
    if (format !== "shapefile") throw new Error("mbt-map: data: a shapefile's parts need format \"shapefile\"");
    const sources: Record<string, object> = {};
    for (const [k, v] of Object.entries(parts)) if (v !== undefined) sources[k] = sourceOf(v, options, transfer);
    return reading(format, { parts: sources }, options, transfer);
  }
  const single = input as Input;
  const name = typeof single === "string" || single instanceof URL ? new URL(httpUrl(single, document.baseURI, "data: the URL")).pathname : single instanceof File ? single.name : null;
  return reading(formatFor(options, name), sourceOf(single, options, transfer), options, transfer);
}

/**
 * An Arrow IPC stream or file (a URL, a Blob or bytes: what DuckDB-WASM, Arquero's `toArrowIPC` or pyarrow give) as a
 * table, as `read` with `format: "arrow"` (Arquero's `fromArrow`; docs/data.md has the types read).
 */
export function fromArrow(input: Input, options: ReadOptions = {}): Promise<Table> {
  return read(input, { ...options, format: "arrow" });
}

/** Reads `text` (CSV, WKT, hexadecimal WKB, TopoJSON, KML, GPX or GeoJSON) as `options.format`. */
export async function parse(text: string, options: ReadOptions & { format: DataFormat }): Promise<Table> {
  if (typeof text !== "string") throw new Error("mbt-map: data: parse takes a string");
  const bytes = new TextEncoder().encode(text).buffer;
  return reading(formatFor(options, null), { bytes }, options, [bytes]);
}

/** `format` and, for CSV, how its rows are laid out. */
export interface WriteOptions extends DataOptions, CsvWriteOptions {
  format: WriteFormat;
}

/**
 * `input` (a table, or a GeoJSON Feature or FeatureCollection) as `options.format`: GeoJSON as
 * `JSON.stringify` of `toGeoJSON()`, CSV as papaparse's `unparse`, KML as @placemarkio/tokml's
 * `toKML` write them (docs/data.md has the rules).
 */
export async function write(input: Table | object, options: WriteOptions): Promise<string> {
  const { format } = options ?? {};
  if (!["geojson", "csv", "kml"].includes(format)) throw new Error(`mbt-map: data: unknown write format ${String(format)}`);
  if (!(input instanceof Table)) {
    if (!input || typeof input !== "object") throw new Error("mbt-map: data: write takes a table or a GeoJSON object");
    if (format === "geojson") return JSON.stringify(input);
    const { workerUrl, wasmUrl, projWasmUrl, xmlUrl, geotiffUrl } = options;
    input = await parse(JSON.stringify(input), { workerUrl, wasmUrl, projWasmUrl, xmlUrl, geotiffUrl, format: "geojson" });
  }
  const table = input as Table;
  if (format === "geojson") return JSON.stringify(await table.toGeoJSON());
  const args = { format, options: format === "csv" ? csvWriteArgs(options) : {}, ...(await table.writeArgs()) };
  startData(options);
  const bytes = await dataClient.call<ArrayBuffer>("write", args, [args.table, ...(args.ids ? [args.ids] : [])]);
  return new TextDecoder().decode(bytes);
}

/**
 * GeoJSON as a table in the analysis worker: an object, its UTF-8 bytes, or an http(s) URL
 * (resolved against the page, fetched without credentials).
 */
export async function fromGeoJSON(data: unknown, options: LoadOptions = {}): Promise<Table> {
  const crs = options.crs === undefined ? undefined : await crsArg(options.crs);
  startAnalysis(options);
  let args: object;
  let transfer: Transferable[] = [];
  if (typeof data === "string") {
    args = { url: httpUrl(data, document.baseURI, "analysis: data") };
  } else {
    // Copied, so the caller's buffer stays usable after the transfer.
    const bytes =
      data instanceof ArrayBuffer ? data.slice(0) :
      ArrayBuffer.isView(data) ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength).slice().buffer :
      new TextEncoder().encode(JSON.stringify(data)).buffer;
    args = { bytes };
    transfer = [bytes];
  }
  return tableOf(analysisCall("load", { ...args, crs }, transfer));
}


/** Stops the data and analysis workers; tables in the analysis worker are lost and pending calls reject. */
export function terminate(): void {
  dataClient.terminate();
  analysisClient.terminate();
}
