// The showcase with <mbt-map>: attributes and properties in, CustomEvents out.
import "mbt-map/element";
import { mountApp } from "../shared/app.js";
import { mountPanelPadding } from "../shared/padding.js";
import { mountShell } from "../shared/shell.js";
import { createStyle } from "../shared/style.js";

const { status } = mountShell("element");
const el = document.querySelector("mbt-map");
el.addEventListener("mbt-map-load", () => {
  window.__loaded = performance.now();
  window.__map = el.map;
  // A new style object goes to the map's setStyle: tiles of what stays alike are kept.
  const app = mountApp(el.map, status, (style) => (el.mapStyle = style));
  el.addEventListener("mbt-map-move", app.showCamera);
  el.addEventListener("mbt-map-moveend", app.update);
  // The element's `padding` property (or attribute) sets the map's padding at once.
  mountPanelPadding((padding) => (el.padding = padding));
});
el.mapStyle = createStyle("2d");
