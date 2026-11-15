import { Map } from "mbt-map";
import { classBreaks, classStep, statistics } from "mbt-map/analysis";
import { cellText, createAttributeTable, createFieldEditor } from "mbt-map/ui";

const SOURCE = "countries";
const HEADINGS = { code: "Code", name: "Country", continent: "Continent", population: "Population", gdp: "GDP (million $)", income: "Income group" };
const PALETTE = ["#edf8b1", "#7fcdbb", "#41b6c4", "#1d91c0", "#225ea8"];
const NO_VALUE = "#d5d9e0";
const PICK = "#e8590c";
const picked = ["boolean", ["feature-state", "selected"], false];

// Each preset's column, its style expression as JSON text (`total`: the world's population) and its button.
const PRESETS = [
  { label: "GDP per capita", column: "gdp_per_capita", expression: () => '["round", ["/", ["*", ["get", "gdp"], 1000000], ["get", "population"]]]' },
  { label: "Population share (%)", column: "population_share", expression: (total) => `["/", ["round", ["*", 10000, ["/", ["get", "population"], ${total}]]], 100]` },
  { label: "Over 100 million people", column: "populous", expression: () => '[">=", ["get", "population"], 100000000]' },
  { label: "Economy size", column: "economy", expression: () => '["step", ["get", "gdp"], "small", 100000, "medium", 1000000, "large"]' },
];

const $ = (id) => document.getElementById(id);
const el = (tag, props = {}) => Object.assign(document.createElement(tag), props);
const number = new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 });
const compact = new Intl.NumberFormat("en-US", { notation: "compact", maximumSignificantDigits: 3 });
// Enter or Escape typed for itself, not to confirm an IME conversion (keyCode 229: Safari's).
const plainKey = (e) => !e.isComposing && e.keyCode !== 229;

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      [SOURCE]: { type: "geojson", data: await (await fetch("./countries.json")).json(), promoteId: "code", attribution: "Made with Natural Earth" },
    },
    layers: [
      { id: "sea", type: "background", paint: { "background-color": "#f3f5f8" } },
      { id: "countries", type: "fill", source: SOURCE, paint: { "fill-color": NO_VALUE, "fill-outline-color": "#fff" } },
      { id: "picked-fill", type: "fill", source: SOURCE, paint: { "fill-color": PICK, "fill-opacity": ["case", picked, 0.55, 0] } },
      { id: "picked-line", type: "line", source: SOURCE, paint: { "line-color": PICK, "line-width": 2, "line-opacity": ["case", picked, 1, 0] } },
    ],
  },
  center: [12, 25],
  zoom: 1,
});
await map.once("load");

// One page holds every row, so the table scrolls and a row picked on the map can be scrolled to.
const table = createAttributeTable(map, { source: SOURCE, pageSize: 1000, fitBoundsOptions: { padding: 30, maxZoom: 5 } });
const fields = createFieldEditor(map, { source: SOURCE, table });
let features = [];
let drawn = {};

table.subscribe(draw);
await table.refresh();
await readFeatures();
$("color").value = "population";
colorMap();
wireTable();
wireMap();
wireCalculator();

// Table

function draw(s) {
  if (s.columns !== drawn.columns || s.sort !== drawn.sort) drawHead(s);
  if (s.columns !== drawn.columns || s.rows !== drawn.rows) drawRows(s);
  for (const tr of $("body").rows) tr.setAttribute("aria-selected", String(s.selected.includes(tr.dataset.id)));
  $("empty").hidden = s.filtered > 0 || s.loading;
  $("count").textContent = `${s.filtered} of ${s.total} countries · ${s.selected.length} selected`;
  $("clear").disabled = s.selected.length === 0;
  drawn = s;
}

function drawHead(s) {
  $("head").replaceChildren(...s.columns.map((column) => {
    const direction = s.sort?.column === column ? s.sort.direction : null;
    const th = el("th", { className: numeric(column) ? "number" : "" });
    th.dataset.column = column;
    th.setAttribute("aria-sort", direction ? `${direction}ending` : "none");
    const mark = direction === "asc" ? " ▲" : direction === "desc" ? " ▼" : "";
    th.append(el("button", { className: "sort", type: "button", textContent: (HEADINGS[column] ?? column) + mark }));
    if (!Object.hasOwn(HEADINGS, column)) {
      th.classList.add("computed");
      th.append(tool("rename", "✎", `Rename ${column}`), tool("remove", "✕", `Remove ${column}`));
    }
    return th;
  }));
}

function tool(action, text, label) {
  const button = el("button", { className: "tool", type: "button", textContent: text, title: label });
  button.dataset.action = action;
  button.setAttribute("aria-label", label);
  return button;
}

function drawRows(s) {
  $("body").replaceChildren(...s.rows.map((row) => {
    const tr = el("tr", { tabIndex: 0 });
    tr.dataset.id = row.id;
    for (const column of s.columns) {
      const value = row.properties[column];
      const isNumber = typeof value === "number";
      tr.append(el("td", { className: isNumber ? "number" : "", textContent: isNumber ? number.format(value) : cellText(value) }));
    }
    return tr;
  }));
}

function wireTable() {
  $("filter").addEventListener("input", (e) => table.setQuery(e.target.value));
  $("clear").addEventListener("click", () => table.clear());
  $("head").addEventListener("click", onHeadClick);
  $("body").addEventListener("click", (e) => pickRow(e.target.closest("tr"), e.shiftKey));
  // Shift+click adds a row to the selection instead of selecting text.
  $("body").addEventListener("mousedown", (e) => e.shiftKey && e.preventDefault());
  $("body").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && plainKey(e)) pickRow(e.target.closest("tr"), e.shiftKey);
  });
}

function pickRow(tr, add) {
  if (!tr) return;
  table.select(tr.dataset.id, { add });
  table.zoomTo(tr.dataset.id);
}

function onHeadClick(e) {
  const button = e.target.closest("button");
  if (!button) return;
  const th = button.closest("th");
  const { column } = th.dataset;
  if (button.dataset.action === "remove") edit(() => fields.removeColumn(column), `Removed “${column}”`);
  else if (button.dataset.action === "rename") askName(th, column);
  else table.setSort(column);
}

// The heading becomes an input: Enter renames the column, Escape or leaving the input gives up.
function askName(th, column) {
  const input = el("input", { value: column });
  input.setAttribute("aria-label", `New name of ${column}`);
  const close = () => drawHead(table.state);
  input.addEventListener("keydown", (e) => {
    if (!plainKey(e)) return;
    if (e.key === "Escape") close();
    if (e.key !== "Enter") return;
    const to = input.value.trim();
    if (to === column) close();
    else edit(() => fields.renameColumn(column, to), `Renamed “${column}” to “${to}”`).then(close);
  });
  input.addEventListener("blur", close);
  th.replaceChildren(input);
  input.select();
}

// Map

function wireMap() {
  map.on("click", async (e) => {
    const [hit] = await map.queryRenderedFeatures([e.point.x, e.point.y], { layers: ["countries"] });
    if (!hit) return table.clear();
    table.select(hit.properties.code, { add: e.originalEvent.shiftKey });
    scrollToRow(hit.properties.code);
  });
  map.on("mousemove", "countries", () => (map.getCanvas().style.cursor = "pointer"));
  map.on("mouseleave", "countries", () => (map.getCanvas().style.cursor = ""));
  $("color").addEventListener("change", colorMap);
  $("method").addEventListener("change", colorMap);
  $("globe").addEventListener("click", (e) => {
    const globe = e.target.getAttribute("aria-pressed") !== "true";
    e.target.setAttribute("aria-pressed", String(globe));
    map.setProjection({ type: globe ? "globe" : "mercator" });
  });
}

function scrollToRow(id) {
  const tr = [...$("body").rows].find((r) => r.dataset.id === id);
  if (tr) $("rows").scrollTo({ top: tr.offsetTop - $("rows").clientHeight / 2, behavior: "smooth" });
}

// The source's features as they are now, and with them the numeric columns the map can be colored by.
async function readFeatures() {
  features = (await map.getSource(SOURCE).getData()).features;
  const select = $("color");
  const now = select.value;
  const columns = table.state.columns.filter(numeric);
  select.replaceChildren(el("option", { value: "", textContent: "nothing" }), ...columns.map((c) => el("option", { value: c, textContent: HEADINGS[c] ?? c })));
  select.value = columns.includes(now) ? now : "";
  drawHead(table.state);
}

function numeric(column) {
  return features.some((f) => typeof f.properties[column] === "number");
}

// Breaks at three significant digits, so the legend says exactly where the colors change.
function colorMap() {
  const column = $("color").value;
  const breaks = column ? classBreaks(features.map((f) => f.properties[column]), PALETTE.length, $("method").value)?.map((b) => Number(b.toPrecision(3))) : null;
  const classes = breaks && classStep(["get", column], breaks, PALETTE);
  map.setPaintProperty("countries", "fill-color", classes ? ["case", ["==", ["typeof", ["get", column]], "number"], classes, NO_VALUE] : NO_VALUE);
  drawLegend(column, breaks);
}

function drawLegend(column, breaks) {
  if (!breaks) return $("legend").replaceChildren();
  const entries = el("div");
  PALETTE.forEach((color, i) => {
    const swatch = el("i");
    swatch.style.background = color;
    entries.append(swatch, el("span", { textContent: `${compact.format(breaks[i])} – ${compact.format(breaks[i + 1])}` }));
  });
  $("legend").replaceChildren(el("b", { textContent: HEADINGS[column] ?? column }), entries);
}

// Field calculator

function wireCalculator() {
  $("calc").open = innerWidth > 640 && innerHeight > 620;
  $("field").addEventListener("submit", (e) => {
    e.preventDefault();
    calculate($("field-name").value.trim(), $("field-expression").value);
  });
  for (const preset of PRESETS) {
    const button = el("button", { type: "button", textContent: preset.label });
    button.addEventListener("click", () => {
      const total = statistics(features.map((f) => f.properties.population)).sum;
      $("field-name").value = preset.column;
      $("field-expression").value = preset.expression(total);
      calculate(preset.column, $("field-expression").value);
    });
    $("presets").append(button);
  }
}

async function calculate(column, text) {
  let expression;
  try {
    expression = JSON.parse(text);
  } catch {
    return say('Write the expression as JSON, like ["get", "gdp"]', true);
  }
  if (Object.hasOwn(HEADINGS, column)) return say(`“${column}” is one of the source's columns: choose another name`, true);
  if (!(await edit(() => fields.calculate(column, expression), `Calculated “${column}” for ${features.length} countries`))) return;
  if (numeric(column)) $("color").value = column;
  colorMap();
}

// Runs a field edit and reads the result; false, with the reason shown, when the editor refuses it.
async function edit(change, done) {
  try {
    await change();
  } catch (err) {
    say(String(err.message).replace(/^mbt-map: /, ""), true);
    return false;
  }
  await readFeatures();
  colorMap();
  say(done, false);
  return true;
}

function say(text, isError) {
  $("field-status").textContent = text;
  $("field-status").classList.toggle("error", isError);
}
