// Registers <mbt-map>; the element in the page then creates its map. Events
// are recorded for bench/npm/pack-test.mjs.
import "mbt-map/element";

window.__events = [];
for (const type of ["mbt-map-load", "mbt-map-move", "mbt-map-idle", "mbt-map-error"]) {
  document.addEventListener(type, (e) => window.__events.push({ type, zoom: e.detail.zoom, error: e.detail.error?.message }));
}
document.addEventListener("mbt-map-load", () => { window.__loaded = performance.now(); }, { once: true });
