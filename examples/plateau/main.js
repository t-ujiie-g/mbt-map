// PLATEAU's LOD2 buildings of Chiyoda as 3D Tiles (mbt-map/3d's tilesLayer) over GSI's vector map; a click
// shows the building's attributes. `?local=1` reads the bench fixture (the tiles around Tokyo Station).
import { Map } from "mbt-map";
import { lineOfSight, measure3d, tilesLayer } from "mbt-map/3d";
import { createMeasurement } from "mbt-map/ui";
import { GSI_LAYERS } from "../shared/layers.js";
import { BUILDINGS_3D, gsiSource } from "../shared/style.js";

const local = new URLSearchParams(location.search).get("local") === "1";
const TILESET = local
  ? new URL("../../bench/fixtures/plateau-chiyoda/tileset.json", location.href).href
  : "https://assets.cms.plateau.reearth.io/assets/72/e900e5-938c-4376-a9de-a124b270880c/13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2_no_texture/tileset.json";
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station.
const GEOID = -36.7;

const PLACES = [
  ["東京駅", { center: [139.7671, 35.6812], zoom: 16.5, pitch: 60, bearing: -20 }],
  ["丸の内", { center: [139.7638, 35.6829], zoom: 17, pitch: 55, bearing: 60 }],
  ["大手町", { center: [139.7651, 35.6868], zoom: 16.5, pitch: 60, bearing: 160 }],
  ["皇居外苑", { center: [139.7565, 35.6802], zoom: 15.5, pitch: 50, bearing: 80 }],
];

/** The attributes shown first, as [key, label, unit]. */
const SHOWN = [
  ["gml:name", "Name"],
  ["bldg:usage", "Usage"],
  ["bldg:class", "Class"],
  ["bldg:measuredHeight", "Measured height", " m"],
  ["bldg:storeysAboveGround", "Storeys above ground"],
  ["bldg:storeysBelowGround", "Storeys below ground"],
  ["uro:BuildingDetailAttribute_uro:fireproofStructureType", "Fireproof structure"],
  ["uro:BuildingDetailAttribute_uro:districtsAndZonesType", "Zoning district"],
  ["uro:lodType", "LOD"],
  ["uro:BuildingIDAttribute_uro:buildingID", "Building ID"],
];

const style = {
  version: 8,
  sources: { gsi: gsiSource() },
  layers: [
    { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
    ...GSI_LAYERS.flatMap((l) => (l.id === "building-outline" ? [] : l.id === "building" ? [{ ...BUILDINGS_3D, layout: { visibility: "none" } }] : [l])),
  ],
};

const map = new Map({ container: "map", style, ...PLACES[0][1], attributionControl: false });
const layer = tilesLayer({ id: "plateau", url: TILESET, height: GEOID });
window.__map = map;
window.__layer = layer;

const status = document.getElementById("status");
const feature = document.getElementById("feature");
layer.ready.catch((e) => (status.textContent = `Could not read PLATEAU's tileset: ${e.message}`));
map.on("error", (e) => console.error(e.error));

function showStatus() {
  if (!map.getLayer("plateau")) status.textContent = "The map's extruded buildings (heights guessed from GSI's building types)";
  else if (layer.selected.length) status.textContent = `Tiles drawn: ${layer.selected.length}${layer.idle ? "" : " (loading)"}`;
}

/** Shows PLATEAU's buildings, or else the map's extruded ones. */
function showPlateau(on) {
  if (on && !map.getLayer("plateau")) map.addLayer(layer);
  if (!on && map.getLayer("plateau")) map.removeLayer("plateau");
  map.setLayoutProperty("building-3d", "visibility", on ? "none" : "visible");
  feature.replaceChildren();
  showStatus();
}

const format = (v, unit = "") => (typeof v === "number" ? `${v.toLocaleString("en-US", { maximumFractionDigits: 1 })}${unit}` : String(v));

function row(label, value) {
  const tr = document.createElement("tr");
  const th = document.createElement("th");
  const td = document.createElement("td");
  th.textContent = label;
  td.textContent = value;
  tr.append(th, td);
  return tr;
}

/** The building's attributes: the usual ones, its flood ranks, then every attribute it has. */
function showFeature(hit) {
  feature.replaceChildren();
  if (!hit) return;
  const p = hit.properties;
  const given = (v) => v !== null && v !== undefined && v !== "" && typeof v !== "object";
  const table = document.createElement("table");
  for (const [key, label, unit] of SHOWN) if (given(p[key])) table.append(row(label, format(p[key], unit)));
  for (const [key, v] of Object.entries(p)) {
    if (!key.endsWith("_浸水ランク") || !given(v)) continue;
    // "<river>（<section>）_<scale>（<case>）_浸水ランク": the river and L1 / L2.
    const scale = key.match(/_(L\d)/)?.[1];
    table.append(row(`Flood rank (${key.split(/[（_]/)[0]}${scale ? ` ${scale}` : ""})`, format(v)));
  }
  const all = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "All attributes";
  const rest = document.createElement("table");
  for (const [key, v] of Object.entries(p)) if (given(v)) rest.append(row(key, String(v)));
  all.append(summary, rest);
  feature.append(table, all);
}

// The tools: a building's attributes, measuring in 3D, a line of sight, a viewshed. Eyes stand 1.6 m up.
const EYE = 1.6;
const result = document.getElementById("tool-result");
const meters = (m) => `${m.toLocaleString("en-US", { maximumFractionDigits: 1 })} m`;
let tool = "feature";
let measurement = null;
let sightFrom = null;

function showMeasurement(s) {
  if (!s.mode || s.positions.length < 2) return (result.textContent = "Click buildings or the ground in turn; double-click to finish.");
  result.textContent = `Straight ${meters(s.length)} · horizontal ${meters(s.horizontal ?? 0)} · height difference ${meters(s.vertical ?? 0)}`;
}

function drawSight(features) {
  map.getSource("sight")?.setData({ type: "FeatureCollection", features });
}

function chooseTool(name) {
  tool = name;
  measurement?.destroy();
  measurement = null;
  sightFrom = null;
  drawSight([]);
  map.setViewshed(null);
  map.setClipping(null);
  feature.replaceChildren();
  result.textContent = { feature: "", measure: "", sight: "Click where to look from, then where to look at.", viewshed: "Click where to look from (facing the map's bearing).", section: "Click where to cut (a vertical plane across the map's bearing)." }[name];
  if (name === "measure") {
    measurement = createMeasurement(map, { measure3d });
    measurement.subscribe(showMeasurement);
    window.__measurement = measurement;
    measurement.start("distance");
  }
}

async function click(e) {
  if (tool === "feature") return showFeature(map.getLayer("plateau") ? await layer.queryFeature(e.point) : null);
  const at = map.pickPosition(e.point);
  if (!at) return;
  const eye = [at[0], at[1], at[2] + EYE];
  if (tool === "section") {
    // A vertical plane through the point, across the view: what lies before it (toward the camera) is cut.
    const b = (map.getBearing() * Math.PI) / 180;
    map.setClipping({ origin: [at[0], at[1], 0], planes: [[Math.sin(b), Math.cos(b), 0, 0]], edgeWidth: 2, edgeColor: [1, 0.55, 0.1] });
    result.textContent = "Cut away the near side (orange marks the cut)";
  } else if (tool === "viewshed") {
    map.setViewshed({ position: eye, heading: map.getBearing(), pitch: -10, horizontalFov: 90, verticalFov: 60, distance: 400 });
    result.textContent = "Green: visible, red: hidden";
  } else if (tool === "sight" && !sightFrom) {
    sightFrom = eye;
    drawSight([]);
    result.textContent = "Click where to look at.";
  } else if (tool === "sight") {
    const s = lineOfSight(map, sightFrom, at);
    const line = (a, b, seen) => ({ type: "Feature", properties: { seen }, geometry: { type: "LineString", coordinates: [a.slice(0, 2), b.slice(0, 2)] } });
    drawSight(s.visible ? [line(sightFrom, at, true)] : [line(sightFrom, s.obstruction, true), line(s.obstruction, at, false)]);
    result.textContent = s.visible ? "Visible" : `Blocked ${meters(measure3d([sightFrom, s.obstruction]).length)} away, at a height of ${meters(s.obstruction[2])}`;
    sightFrom = null;
  }
}

map.once("load").then(() => {
  showPlateau(true);
  map.addSource("sight", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
  map.addLayer({ id: "sight", type: "line", source: "sight", paint: { "line-width": 3, "line-color": ["case", ["get", "seen"], "#2a9d4b", "#d6342c"] } });
  map.on("render", showStatus);
  map.on("click", click);
  window.__loaded = performance.now();
});
for (const input of document.querySelectorAll("#tools input")) input.addEventListener("change", (e) => chooseTool(e.target.value));

document.getElementById("plateau").addEventListener("change", (e) => showPlateau(e.target.checked));
const places = document.getElementById("places");
for (const [name, camera] of PLACES) {
  const b = document.createElement("button");
  b.textContent = name;
  b.addEventListener("click", () => map.flyTo({ ...camera, duration: 1500 }));
  places.append(b);
}

const credit = document.getElementById("credit");
const link = document.createElement("a");
link.href = "https://www.mlit.go.jp/plateau/";
link.textContent = "https://www.mlit.go.jp/plateau/";
credit.append(
  `国土地理院ベクトルタイル提供実験 | 出典：「3D都市モデル（Project PLATEAU）千代田区（2025年度）」（国土交通省）（`,
  link,
  local ? "）を加工して作成（東京駅周辺のタイルを抜き出したもの）" : "）",
);
