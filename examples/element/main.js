// The showcase with <moon-map>: attributes and properties in, CustomEvents out.
import "moon-map/element";
import { mountApp } from "../shared/app.js";
import { mountShell } from "../shared/shell.js";
import { createStyle } from "../shared/style.js";

const { status } = mountShell("element");
const el = document.querySelector("moon-map");
el.addEventListener("moon-map-load", () => {
  window.__loaded = performance.now();
  window.__map = el.map;
  // A new style object goes to the map's setStyle: tiles of what stays alike are kept.
  const app = mountApp(el.map, status, (style) => (el.mapStyle = style));
  el.addEventListener("moon-map-move", app.showCamera);
  el.addEventListener("moon-map-moveend", app.update);
});
el.mapStyle = createStyle("2d");
