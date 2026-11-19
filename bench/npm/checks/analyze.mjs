// The showcase's analysis tab at Tokyo Station: the places' Voronoi cells classed by area (the
// legend lists the five classes), a route between two clicks along the drawn roads, the viewshed
// from the center and a line of sight to a click.
import { existsSync } from "node:fs";
import path from "node:path";
import { ROOT } from "../../lib/root.mjs";
import { clipLine, tileBounds, tileLines } from "../../../examples/shared/tile-lines.js";
import { openTab } from "./step.mjs";

// The stations with parks nearest them (examples/shared/sample-parks.csv), in the places' order: how many, and the first.
const TALLY = [["有楽町駅", 2, "日比谷公園"], ["新宿駅", 1, "新宿御苑"], ["渋谷駅", 1, "代々木公園"], ["上野駅", 1, "上野恩賜公園"]];

export async function analyzeChecks(page) {
  const camera = await page.evaluate(() => ({ center: window.__map.getCenter(), zoom: window.__map.getZoom(), bearing: window.__map.getBearing(), pitch: window.__map.getPitch() }));
  await page.evaluate(() => window.__map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 }));
  await page.evaluate(() => window.__map.once("idle"));
  await openTab(page, "analysis");
  const a = () => page.evaluate(() => window.__analysis.state);
  await page.click("#analysis-cells button >> nth=0");
  await page.waitForFunction(() => window.__analysis.state.cells?.breaks || window.__analysis.state.error, null, { timeout: 30_000 });
  await page.evaluate(() => window.__map.once("idle"));
  const cells = await page.evaluate(async () => {
    const s = window.__analysis.state;
    const legend = window.__panel.legend.state.entries.find((e) => e.id === "analysis-cells");
    const data = await window.__map.getSource("analysis-cells").getData();
    return {
      error: s.error, count: s.cells?.count, breaks: s.cells?.breaks, labels: legend?.items.map((i) => i.label),
      areas: data.features.map((f) => [f.properties.name, f.properties["area"], f.properties["area_km2"]]),
    };
  });
  // The table pipeline: parks from the CSV, counted at their nearest station and drawn from the table.
  await page.evaluate(() => { window.__tableErrors = []; window.__map.on("error", (e) => window.__tableErrors.push(String(e.error?.message ?? e.error))); });
  await page.click("#analysis-table button >> nth=0");
  await page.waitForFunction(() => { const t = window.__analysis.state.table; return (t && t !== "loading") || window.__analysis.state.error; }, null, { timeout: 30_000 });
  // The table's rows reach the source's worker after the state is set.
  const asked = Date.now();
  await page.waitForFunction(async () => (await window.__map.querySourceFeatures("analysis-table")).length > 0, null, { timeout: 30_000 }).catch(() => {});
  const tiledAfter = Date.now() - asked;
  // When the tiles never came: whether a frame asked for brings them.
  const late = tiledAfter < 30_000 ? null : await page.evaluate(async () => {
    window.__map.triggerRepaint();
    await new Promise((f) => setTimeout(f, 3000));
    return { errors: window.__tableErrors, moving: window.__map.isMoving(), features: (await window.__map.querySourceFeatures("analysis-table")).length, geojson: (await (await window.__map.getSource("analysis-table").getData()).toGeoJSON()).features.length };
  });
  const table = await page.evaluate(async () => {
    const data = await window.__map.getSource("analysis-table").getData();
    return {
      state: window.__analysis.state.table, error: window.__analysis.state.error, isTable: typeof data?.toGeoJSON === "function", columns: data?.columns,
      // In the tiles around Tokyo Station (有楽町駅 is just south of the view).
      tiled: [...new Set((await window.__map.querySourceFeatures("analysis-table")).map((f) => `${f.properties.name} ${f.properties.parks}`))].sort(),
      layer: window.__map.getLayer("analysis-table")?.type,
      rows: document.getElementById("analysis-table-rows").textContent,
    };
  });
  // Two clicks east of the station (the panel covers the west), snapped to road vertices.
  const at = (lng, lat) => page.evaluate(([x, y]) => window.__map.project([x, y]), [lng, lat]);
  const box = await page.locator("#map, mbt-map").first().boundingBox();
  const click = async (lng, lat) => {
    const p = await at(lng, lat);
    await page.mouse.click(box.x + p.x, box.y + p.y);
  };
  await page.click("#analysis-route button >> nth=0");
  await click(139.7676, 35.6795);
  await click(139.7705, 35.6830);
  await page.waitForFunction(() => { const r = window.__analysis.state.route; return r && r !== "loading"; }, null, { timeout: 30_000 });
  const route = (await a()).route;
  const roads = await page.evaluate(async () => (await window.__map.querySourceFeatures("gsi", { sourceLayer: "road" })).map((f) => ({ tile: f.tile, geometry: f.geometry })));
  const routeLine = await page.evaluate(async () => (await window.__map.getSource("analysis-route").getData()).features.map((f) => f.geometry.type));
  await page.click("#analysis-sight button >> nth=0");
  await page.waitForFunction(() => { const s = window.__analysis.state.sight; return (s && s !== "loading") || window.__analysis.state.error; }, null, { timeout: 30_000 });
  const sight = (await a()).sight;
  const viewshed = await page.evaluate(() => ({ layer: window.__map.getLayer("analysis-viewshed")?.type, source: window.__map.getSource("analysis-viewshed")?.type }));
  await page.click("#analysis-sight button >> nth=1");
  await click(139.7705, 35.6830);
  await page.waitForFunction(() => window.__analysis.state.target, null, { timeout: 30_000 });
  const target = (await a()).target;
  const rows = await page.evaluate(() => ["cells", "route", "sight"].map((k) => document.getElementById(`analysis-${k}-rows`).textContent));
  // A click while picking does not identify.
  const picked = await page.evaluate(() => window.__identify?.state.point ?? null);
  for (const tool of ["cells", "table", "route", "sight"]) await page.click(`#analysis-${tool} button >> text=Clear`);
  const cleared = await page.evaluate(() => ({ layers: ["analysis-cells", "analysis-viewshed"].map((id) => Boolean(window.__map.getLayer(id))), state: window.__analysis.state }));
  await page.evaluate((c) => window.__map.jumpTo(c), camera);
  await page.evaluate(() => window.__map.once("idle"));
  // CI has no fixtures: no roads to route along, and the DEM tiles 404 as flat ground (everything seen).
  const fixtures = existsSync(path.join(ROOT, "bench/fixtures/gsi-bvmap/14"));
  const routed = fixtures ? route?.length > 100 && route.length < 2000 && routeLine.includes("LineString") : route?.error === "No road found";
  const clipped = clipChecks(roads);
  const sorted = [...(cells.breaks ?? [])].every((b, i, xs) => i === 0 || b >= xs[i - 1]);
  const ok =
    !cells.error && cells.count >= 10 && cells.breaks?.length === 6 && sorted && cells.labels?.length === 5 &&
    cells.areas.every(([, m2, km2]) => m2 > 0 && km2 === Math.round(m2 / 10000) / 100) &&
    routed && clipped.ok &&
    sight?.visible > 0 && sight.visible <= 1 && viewshed.layer === "raster" && viewshed.source === "canvas" &&
    typeof target?.visible === "boolean" && rows.every((r) => r.length > 0) &&
    // Each bound is listed once, also when a class holds one value.
    rows[0].split("Breaks")[1] === [...new Set(cells.breaks.map((b) => b.toFixed(2)))].join(" / ") &&
    JSON.stringify(cleared.layers) === JSON.stringify([false, false]) && cleared.state.cells === null && cleared.state.route === null && cleared.state.sight === null &&
    // Five parks, each at its nearest station; the source holds the table itself.
    !table.error && table.state?.parks === 5 && table.isTable && JSON.stringify(table.state.stations) === JSON.stringify(TALLY) &&
    JSON.stringify(table.columns) === JSON.stringify(["name", "kind", "name_station", "parks", "first"]) &&
    table.tiled.includes("有楽町駅 2") && table.layer === "circle" && table.rows.includes("Parks read5") && cleared.state.table === null;
  return { ok, fixtures, table, tiledAfter, late, cells, route, routeLine, clipped, sight, viewshed, target, rows, picked, cleared: cleared.layers };
}

// The route's roads: each feature's tile, its lines cut to that tile (inside it, of the deepest
// zoom only), and a line crossing two tiles cut at one shared point.
function clipChecks(roads) {
  const within = (c, [w, s, e, n]) => c[0] >= w && c[0] <= e && c[1] >= s && c[1] <= n;
  const tiled = roads.every((f) => Number.isInteger(f.tile?.z) && Number.isInteger(f.tile.x) && Number.isInteger(f.tile.y));
  const z = Math.max(...roads.map((f) => f.tile?.z ?? -1));
  const deepest = roads.filter((f) => f.tile?.z === z);
  const inside = deepest.every((f) => tileLines([f]).every((l) => l.every((c) => within(c, tileBounds(f.tile)))));
  const [w, s, e, n] = tileBounds({ z: 14, x: 14552, y: 6451 });
  const across = [[(w + e) / 2, (s + n) / 2], [e + (e - w) / 20, (s + n) / 2 + (n - s) / 10]];
  const halves = tileLines([
    { tile: { z: 14, x: 14552, y: 6451 }, geometry: { type: "LineString", coordinates: across } },
    { tile: { z: 14, x: 14553, y: 6451 }, geometry: { type: "LineString", coordinates: [...across].reverse() } },
    { tile: { z: 13, x: 7276, y: 3225 }, geometry: { type: "LineString", coordinates: across } },
  ]);
  const joined = halves.length === 2 && halves[0][1][0] === e && JSON.stringify(halves[0][1]) === JSON.stringify(halves[1][1]);
  const pieces = clipLine([[-1, 0.5], [0.5, 0.5], [0.5, 2], [0.8, 2], [0.8, 0.2], [3, 0.2]], [0, 0, 1, 1]);
  const cut = JSON.stringify(pieces) === JSON.stringify([[[0, 0.5], [0.5, 0.5], [0.5, 1]], [[0.8, 1], [0.8, 0.2], [1, 0.2]]]);
  const fixtures = roads.length > 0;
  return { ok: (fixtures ? tiled && inside : true) && joined && cut, features: roads.length, zoom: z, deepest: deepest.length, tiled, inside, joined, cut };
}
