// The data and analysis workers' clients, one of each for mbt-map/table, mbt-map/data and
// mbt-map/analysis (dist/clients.js, which the three load): each worker starts on its first use.
import { wasmUrl, workerParts } from "./urls";
import { WorkerClient } from "./worker-client";

/** Where the data worker (`workerUrl`), its wasm (`wasmUrl`), proj.wasm (`projWasmUrl`), xml.wasm (`xmlUrl`) and
 * geotiff.wasm (`geotiffUrl`, each loaded on first use) are served; by default next to this module. */
export interface DataOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  projWasmUrl?: string | URL;
  xmlUrl?: string | URL;
  geotiffUrl?: string | URL;
}

/**
 * Where the analysis worker and its wasm (`workerUrl`, `wasmUrl`), the geometry module
 * (`geometryWasmUrl`), the spatial relation module (`relateWasmUrl`), the shape module
 * (`shapesWasmUrl`), the surface module (`surfaceWasmUrl`), the viewshed module (`viewshedWasmUrl`), the
 * routing module (`routeWasmUrl`) and the coordinate system module (`projWasmUrl`) are served; by default
 * next to this module.
 */
export interface AnalysisOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  geometryWasmUrl?: string | URL;
  relateWasmUrl?: string | URL;
  shapesWasmUrl?: string | URL;
  surfaceWasmUrl?: string | URL;
  viewshedWasmUrl?: string | URL;
  routeWasmUrl?: string | URL;
  projWasmUrl?: string | URL;
}

export const dataClient = new WorkerClient("data");

export function startData(options: DataOptions): void {
  dataClient.start(options.workerUrl, new URL("./data-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./data.wasm", import.meta.url), page),
    proj: wasmUrl(options.projWasmUrl ?? new URL("./proj.wasm", import.meta.url), page),
    prj: new URL("./prjwkt.js", import.meta.url).href,
    parts: workerParts(options.workerUrl, {
      zip: new URL("./data-zip.js", import.meta.url),
      crs: new URL("./data-crs.js", import.meta.url),
      fgb: new URL("./data-fgb.js", import.meta.url),
      geotiff: new URL("./data-geotiff.js", import.meta.url),
      reproject: new URL("./data-reproject.js", import.meta.url),
    }),
    xml: wasmUrl(options.xmlUrl ?? new URL("./xml.wasm", import.meta.url), page),
    geotiff: wasmUrl(options.geotiffUrl ?? new URL("./geotiff.wasm", import.meta.url), page),
  }));
}

export const analysisClient = new WorkerClient("analysis");

export function startAnalysis(options: AnalysisOptions): void {
  analysisClient.start(options.workerUrl, new URL("./analysis-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./analysis.wasm", import.meta.url), page),
    geometry: wasmUrl(options.geometryWasmUrl ?? new URL("./geometry.wasm", import.meta.url), page),
    relate: wasmUrl(options.relateWasmUrl ?? new URL("./relate.wasm", import.meta.url), page),
    shapes: wasmUrl(options.shapesWasmUrl ?? new URL("./shapes.wasm", import.meta.url), page),
    surface: wasmUrl(options.surfaceWasmUrl ?? new URL("./surface.wasm", import.meta.url), page),
    viewshed: wasmUrl(options.viewshedWasmUrl ?? new URL("./viewshed.wasm", import.meta.url), page),
    route: wasmUrl(options.routeWasmUrl ?? new URL("./route.wasm", import.meta.url), page),
    proj: wasmUrl(options.projWasmUrl ?? new URL("./proj.wasm", import.meta.url), page),
    parts: workerParts(options.workerUrl, { viewshed: new URL("./analysis-viewshed.js", import.meta.url) }),
  }));
}

/** A call to the analysis worker, which a `fromGeoJSON`, a table's first operation or a grid has started. */
export function analysisCall<T>(op: string, args: object, transfer: Transferable[] = []): Promise<T> {
  if (!analysisClient.started) return Promise.reject(new Error("mbt-map: analysis: no dataset has been loaded"));
  return analysisClient.call<T>(op, args, transfer);
}

/** A handle's worker id, refused once disposed or when the worker that gave it was stopped (ids start again). */
export function live(id: number, generation: number, disposed: boolean, what: string): number {
  if (disposed) throw new Error(`mbt-map: analysis: the ${what} was disposed`);
  if (generation !== analysisClient.generation) throw new Error(`mbt-map: analysis: the ${what} went with the terminated worker`);
  return id;
}

/** Frees a handle in the analysis worker, unless it went with an earlier one. */
export function free(op: string, args: object, generation: number): void {
  if (generation === analysisClient.generation) analysisCall(op, args).catch(() => {});
}

/** PROJ strings by the names `defineCrs` gave them. */
export const named = new Map<string, string>();

/**
 * Names `projString` so that `name` can be passed wherever a table or the analysis takes a CRS, as
 * `proj4.defs` does (`defineCrs("EPSG:2154", "+proj=lcc ...")`); it overrides
 * a known EPSG code of that name. The string is parsed when first used.
 */
export function defineCrs(name: string, projString: string): void {
  if (typeof projString !== "string" || !projString.trim().startsWith("+")) throw new Error(`mbt-map: analysis: not a PROJ string: ${String(projString)}`);
  named.set(name.trim().toUpperCase(), projString);
}
