// The page around the map for the plain-DOM examples (the React example writes the same markup in
// JSX): a panel with the search and six tabs, the view's buttons, and a status bar. The markup is
// constant; everything that comes from data goes in later through `textContent`.
import { icon } from "./icons.js";
import { MODES } from "./style.js";

/** The panel's tabs as [id, label]. */
export const TABS = [["explore", "Explore"], ["layers", "Layers"], ["draw", "Draw"], ["measure", "Measure"], ["analysis", "Analyze"], ["data", "Data"]];

/** The three ways the showcase is written as [path, label]. */
export const VARIANTS = [["html", "HTML"], ["element", "Element"], ["react", "React"]];

/** The variants to link: all of them, or those the page's `data-variants` names (the site publishes fewer). */
export function variants() {
  const published = document.documentElement.dataset.variants?.split(",");
  return published ? VARIANTS.filter(([path]) => published.includes(path)) : VARIANTS;
}

const TAB_BODIES = {
  explore: `
    <h2>Go to</h2><div id="destinations" class="chips"></div>
    <h2>Clicked feature</h2><dl id="picked" class="rows"><dt>—</dt><dd>Click the map</dd></dl>
    <h2>Places within 5 km of the center</h2><ul id="near" class="plain-list"></ul>
    <h2>Camera</h2><dl id="camera" class="rows"></dl>`,
  layers: `
    <h2>Basemap</h2><div id="basemaps" class="segmented"></div>
    <h2>Layers</h2><div id="layers" class="toggles"></div>
    <details class="legend"><summary>Legend</summary><ul id="legend"></ul></details>`,
  draw: `
    <h2>Shapes</h2><div id="draw-modes" class="chips"></div>
    <div id="draw-actions" class="chips"></div>
    <p id="drawn" class="hint"></p>
    <div id="draw-fields" hidden></div>`,
  measure: `
    <h2>Distance and area</h2><div id="measure" class="chips"></div>
    <dl id="measured" class="rows"></dl>
    <h2>Elevation profile</h2><figure id="profile"></figure>`,
  analysis: `
    <h2>Choropleth</h2><div id="analysis-cells" class="chips"></div><dl id="analysis-cells-rows" class="rows"></dl>
    <h2>Table: read, join, count, draw</h2><div id="analysis-table" class="chips"></div><dl id="analysis-table-rows" class="rows"></dl>
    <h2>Route on roads</h2><div id="analysis-route" class="chips"></div><dl id="analysis-route-rows" class="rows"></dl>
    <h2>Line of sight and viewshed</h2><div id="analysis-sight" class="chips"></div><dl id="analysis-sight-rows" class="rows"></dl>
    <p id="analysis-error" class="hint" hidden></p>`,
  data: `
    <h2>Open data</h2><div id="data"></div>
    <h2>Web services</h2><div id="services"></div>
    <h2>Places table</h2><div id="table"></div>
    <div class="chips"><button id="marker">Add a marker at the center</button></div>`,
};

/** Shows tab `id`, in the markup both ways of drawing the panel share. */
function showTab(root, id) {
  for (const b of root.querySelectorAll(".tabs button")) b.setAttribute("aria-selected", String(b.dataset.tab === id));
  for (const p of root.querySelectorAll("[role=tabpanel]")) p.hidden = p.dataset.panel !== id;
}

/** Adds the panel, the view's buttons and the status bar to the page; `current` is this example's path in VARIANTS. */
export function mountShell(current) {
  const panel = document.createElement("aside");
  panel.className = "panel";
  const card = document.createElement("div");
  card.className = "panel-card";
  const brand = document.createElement("header");
  brand.className = "brand";
  const logo = Object.assign(document.createElement("a"), { className: "logo", href: "../", textContent: "mbt-map" });
  const links = document.createElement("nav");
  links.className = "variants";
  links.setAttribute("aria-label", "Variants");
  for (const [path, label] of variants()) {
    const a = Object.assign(document.createElement("a"), { href: `../${path}/`, textContent: label });
    if (path === current) a.setAttribute("aria-current", "page");
    links.append(a);
  }
  const collapse = Object.assign(document.createElement("button"), { className: "collapse", title: "Collapse the panel" });
  collapse.setAttribute("aria-label", "Collapse the panel");
  collapse.append(icon("chevron"));
  collapse.addEventListener("click", () => card.classList.toggle("collapsed"));
  brand.append(logo, links, collapse);

  const search = Object.assign(document.createElement("div"), { id: "search" });
  const tabs = document.createElement("div");
  tabs.className = "tabs";
  tabs.setAttribute("role", "tablist");
  const body = document.createElement("div");
  body.className = "tab-body";
  for (const [id, label] of TABS) {
    const b = Object.assign(document.createElement("button"), { textContent: label });
    b.dataset.tab = id;
    b.setAttribute("role", "tab");
    b.addEventListener("click", () => showTab(card, id));
    tabs.append(b);
    const section = document.createElement("section");
    section.dataset.panel = id;
    section.setAttribute("role", "tabpanel");
    section.innerHTML = TAB_BODIES[id];
    body.append(section);
  }
  card.append(brand, search, tabs, body);
  panel.append(card);

  const actions = document.createElement("div");
  actions.className = "map-actions";
  const modes = Object.assign(document.createElement("div"), { id: "modes", className: "segmented" });
  for (const [m, label] of MODES) {
    const b = Object.assign(document.createElement("button"), { textContent: label });
    b.dataset.mode = m;
    modes.append(b);
  }
  const save = Object.assign(document.createElement("button"), { id: "save", title: "Save as image" });
  save.setAttribute("aria-label", "Save as image");
  save.append(icon("camera"));
  actions.append(modes, save);

  const status = document.createElement("div");
  status.className = "statusbar";
  document.body.append(panel, actions, status);
  showTab(card, "explore");
  return { status };
}
