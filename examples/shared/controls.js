// The map's controls drawn with plain DOM from `mbt-map/ui`'s controllers (the
// React example draws the same controllers its own way): zoom, compass, home,
// location, full screen, a scale bar and the attributions.
import { icon } from "./icons.js";
import { createAttribution, createFullscreen, createGeolocation, createNavigation, createScale } from "mbt-map/ui";

export const LOCATION_LABELS = {
  unavailable: "Location unavailable",
  off: "Show my location",
  waiting: "Finding your location",
  active: "Following your location",
  "active-error": "Could not find your location",
  background: "Back to my location",
  "background-error": "Could not find your location",
};

function button(label, name, onClick) {
  const b = document.createElement("button");
  b.type = "button";
  b.append(icon(name));
  b.setAttribute("aria-label", label);
  b.title = label;
  b.addEventListener("click", onClick);
  return b;
}

/** Controls over `map` in `parent` (which covers the map), the scale and credits in `status`; returns their removal. */
export function mountControls(map, parent, status) {
  const nav = createNavigation(map);
  const geo = createGeolocation(map, { trackUserLocation: true });
  const full = createFullscreen(map, { container: document.documentElement });
  const scale = createScale(map, { maxWidth: 120 });
  const attribution = createAttribution(map);
  const controllers = [nav, geo, full, scale, attribution];

  const box = document.createElement("div");
  box.className = "controls";
  const zoomIn = button("Zoom in", "plus", () => nav.zoomIn());
  const zoomOut = button("Zoom out", "minus", () => nav.zoomOut());
  const compass = button("Reset north", "north", () => nav.resetNorth(true));
  const needle = document.createElement("span");
  needle.className = "needle";
  needle.append(compass.firstChild);
  compass.append(needle);
  const home = button("Back to start", "home", () => nav.home());
  const locate = button(LOCATION_LABELS.off, "locate", () => geo.trigger());
  const fullscreen = button("Full screen", "fullscreen", () => full.toggle());
  const group = (...buttons) => {
    const g = document.createElement("div");
    g.className = "control-group";
    g.append(...buttons);
    return g;
  };
  box.append(group(zoomIn, zoomOut, compass), group(home, locate, fullscreen));

  const bar = document.createElement("div");
  bar.className = "scale";
  const credits = document.createElement("div");
  credits.className = "credits";
  // The user's location: a dot with its accuracy circle, kept on its place by `track`.
  const dot = document.createElement("div");
  dot.className = "location";
  dot.hidden = true;
  parent.append(box, dot);
  status.append(bar, credits);
  let tracker = null;

  const draw = () => {
    const n = nav.state;
    zoomIn.disabled = !n.canZoomIn;
    zoomOut.disabled = !n.canZoomOut;
    needle.style.transform = `rotateX(${n.pitch}deg) rotateZ(${-n.bearing}deg)`;
    const g = geo.state;
    locate.disabled = g.status === "unavailable";
    locate.dataset.status = g.status;
    locate.setAttribute("aria-pressed", String(g.status !== "off" && g.status !== "unavailable"));
    locate.title = LOCATION_LABELS[g.status];
    locate.setAttribute("aria-label", LOCATION_LABELS[g.status]);
    dot.hidden = !g.position;
    dot.style.setProperty("--accuracy", `${g.accuracyRadius}px`);
    if (g.position && !tracker) tracker = map.track(g.position.lngLat, ({ x, y }) => (dot.style.transform = `translate(${x}px, ${y}px)`));
    else if (g.position) tracker.setLngLat(g.position.lngLat);
    else if (tracker) (tracker.remove(), (tracker = null));
    fullscreen.setAttribute("aria-pressed", String(full.state.active));
    document.documentElement.classList.toggle("pseudo-fullscreen", full.state.pseudo && full.state.active);
    bar.style.width = `${scale.state.width}px`;
    bar.textContent = scale.state.label;
    credits.textContent = attribution.state.text;
  };
  const offs = controllers.map((c) => c.subscribe(draw));
  map.on("load", draw);
  draw();
  window.__controls = { nav, geo, full, scale, attribution, elements: { box, bar, credits, dot, locate } };
  return () => {
    offs.forEach((off) => off());
    controllers.forEach((c) => c.destroy());
    tracker?.remove();
    box.remove();
    bar.remove();
    credits.remove();
    dot.remove();
  };
}
