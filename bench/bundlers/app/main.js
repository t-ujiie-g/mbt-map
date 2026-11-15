// The app every bundler builds (bench/bundlers/run.mjs): a map of GeoJSON circles, a feature query (a display
// worker part), and one call each of mbt-map/analysis, mbt-map/geodesic (a worker small enough for Vite to
// inline) and mbt-map/data with a CRS (a data worker part and proj.wasm). The result goes to `window.__result`.
import { Map } from "mbt-map";
import { load } from "mbt-map/analysis";
import { parse } from "mbt-map/data";
import { inverse } from "mbt-map/geodesic";

const STEP_TIMEOUT = 15000;
const points = {
  type: "FeatureCollection",
  features: [
    { type: "Feature", id: 1, properties: { name: "a" }, geometry: { type: "Point", coordinates: [139.7671, 35.6812] } },
    { type: "Feature", id: 2, properties: { name: "b" }, geometry: { type: "Point", coordinates: [139.7631, 35.6751] } },
  ],
};
const polygons = {
  type: "FeatureCollection",
  features: [{ type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [[[139.76, 35.67], [139.77, 35.67], [139.77, 35.68], [139.76, 35.68], [139.76, 35.67]]] } }],
};
const result = { map: null, query: null, analysis: null, geodesic: null, data: null, errors: [] };

async function step(name, f) {
  try {
    const late = new Promise((_, no) => setTimeout(() => no(new Error(`timed out after ${STEP_TIMEOUT} ms`)), STEP_TIMEOUT));
    result[name] = await Promise.race([f(), late]);
  } catch (e) {
    result.errors.push(`${name}: ${e?.message ?? e}`);
  }
}

async function run() {
  let map;
  await step("map", async () => {
    map = new Map({
      container: "map",
      style: {
        version: 8,
        sources: { points: { type: "geojson", data: points } },
        layers: [
          { id: "bg", type: "background", paint: { "background-color": "#dde" } },
          { id: "points", type: "circle", source: "points", paint: { "circle-radius": 12, "circle-color": "#c00" } },
        ],
      },
      center: [139.7671, 35.6812],
      zoom: 14,
    });
    map.on("error", (e) => result.errors.push(`map error: ${e?.error?.message ?? e?.message ?? e}`));
    await map.once("idle");
    return "idle";
  });
  await step("query", async () => (await map.queryRenderedFeatures({ layers: ["points"] })).map((f) => f.properties.name).sort());
  await step("analysis", async () => Array.from(await (await load(polygons)).centroids()).map((v) => Math.round(v * 1e3) / 1e3));
  await step("geodesic", async () => Math.round((await inverse([139.7671, 35.6812], [139.7631, 35.6751])).distance));
  await step("data", async () => {
    const table = await parse("POINT (-6000 -35000)", { format: "wkt", crs: 6677 });
    return table.toGeoJSON().features[0].geometry.coordinates.map((v) => Math.round(v * 1e3) / 1e3);
  });
  window.__result = result;
}

run();
