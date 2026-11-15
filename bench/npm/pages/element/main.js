// Registers <moon-map>; the element in the page then creates its map. Events
// are recorded for bench/npm/pack-test.mjs.
import "moon-map/element";

window.__events = [];
for (const type of ["moon-map-load", "moon-map-move", "moon-map-idle", "moon-map-error"]) {
  document.addEventListener(type, (e) => window.__events.push({ type, zoom: e.detail.zoom, error: e.detail.error?.message }));
}
document.addEventListener("moon-map-load", () => { window.__loaded = performance.now(); }, { once: true });
