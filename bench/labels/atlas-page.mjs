// OpenFreeMap's Liberty on the ofm-planet fixture plus a GeoJSON layer of CJK labels whose text
// changes at each step (`window.__step`), as when flying between cities; bench/labels/atlas.mjs
// drives it. Needs `npm --prefix npm run build`.
import { Map } from "/npm/dist/index.js";

const style = await (await fetch("/bench/fixtures/styles/ofm-liberty.json")).json();
const tiles = { type: "vector", tiles: [`${location.origin}/bench/fixtures/ofm-planet/{z}/{x}/{y}.pbf`], minzoom: 14, maxzoom: 14 };
const vector = new Set(Object.entries(style.sources).filter(([, s]) => s.type === "vector").map(([id]) => id));
const { glyphs, sprite, ...rest } = style;
const params = new URLSearchParams(location.search);
// Distinct characters per step, from U+4E00 on, in labels of LABEL_CHARS each.
const PER_STEP = Number(params.get("chars") ?? 600);
const LABEL_CHARS = 6;
const COLUMNS = 10;
const center = [139.7671, 35.6812];

// Step `k`'s labels on a grid around the center: characters k * PER_STEP onwards.
export function labels(k) {
  const features = [];
  for (let i = 0; i < PER_STEP / LABEL_CHARS; i++) {
    let text = "";
    for (let c = 0; c < LABEL_CHARS; c++) text += String.fromCodePoint(0x4e00 + k * PER_STEP + i * LABEL_CHARS + c);
    const row = Math.floor(i / COLUMNS), col = i % COLUMNS;
    features.push({ type: "Feature", properties: { t: text }, geometry: { type: "Point", coordinates: [center[0] - 0.0135 + col * 0.003, center[1] + 0.0095 - row * 0.0021] } });
  }
  return { type: "FeatureCollection", features };
}

const first = Number(params.get("step") ?? 0);
const map = new Map({
  container: "map",
  pixelRatio: 1,
  center,
  zoom: 15,
  style: {
    ...rest,
    sources: { ...Object.fromEntries([...vector].map((id) => [id, tiles])), cjk: { type: "geojson", data: labels(first) } },
    layers: [
      ...style.layers.filter((l) => l.type === "background" || vector.has(l.source)),
      { id: "cjk", type: "symbol", source: "cjk", layout: { "text-field": ["get", "t"], "text-font": ["Noto Sans Regular"], "text-size": 14, "text-allow-overlap": true, "text-ignore-placement": true }, paint: { "text-color": "#202020" } },
    ],
  },
});
const idle = () => new Promise((r) => map.once("idle", r));
await idle();
// Sets step `k`'s labels and waits until the map has drawn them (idle can come before the
// GeoJSON worker has cut the new data).
window.__step = async (k) => {
  const data = labels(k);
  const texts = new Set(data.features.map((f) => f.properties.t));
  map.getSource("cjk").setData(data);
  for (;;) {
    await Promise.race([idle(), new Promise((r) => setTimeout(r, 200))]);
    const drawn = await map.queryRenderedFeatures({ layers: ["cjk"] });
    if (drawn.length && drawn.every((f) => texts.has(f.properties.t))) return;
  }
};
window.__map = map;
window.__ready = true;
