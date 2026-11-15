// A page taller than the viewport with a `Map`, an `<mbt-map>` and a plain box, for the pack test's
// touch check: the map's gestures must not scroll or zoom the page.
import { Map } from "mbt-map";
import "mbt-map/element";

const map = new Map({ container: "map", style: "/bench/pages/basic/style.json", center: [139.7671, 35.6812], zoom: 14.5 });
map.on("error", (e) => console.error(e.error));
window.__map = map;
window.__errors = [];
const el = document.querySelector("mbt-map");
el.addEventListener("mbt-map-error", (e) => window.__errors.push(e.detail.error.message));
const loaded = new Promise((done) => (el.map?.loaded() ? done() : el.addEventListener("mbt-map-load", done, { once: true })));
Promise.all([map.once("load"), loaded]).then(() => {
  window.__loaded = performance.now();
});
