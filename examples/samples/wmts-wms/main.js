import { Map } from "mbt-map";
import { getCapabilities, wmsSource, wmtsSource } from "mbt-map/services";

// NASA GIBS (https://www.earthdata.nasa.gov/gibs): each service's terms and attribution are the page's to follow.
const WMTS = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml";
const WMS = "https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi";
const ATTRIBUTION = "NASA EOSDIS GIBS";

const map = new Map({
  container: "map",
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#0b1526" } }] },
  center: [137, 36],
  zoom: 4,
});

const select = document.getElementById("layer");
const status = document.getElementById("status");
let wmts = null;
let wms = null;

function showLayer(id) {
  if (map.getLayer("wmts")) map.removeLayer("wmts");
  if (map.getSource("wmts")) map.removeSource("wmts");
  map.addSource("wmts", { ...wmtsSource(wmts, { layer: id }), attribution: ATTRIBUTION });
  map.addLayer({ id: "wmts", type: "raster", source: "wmts" }, map.getLayer("wms") ? "wms" : undefined);
}

async function showWms(on) {
  if (!on) return map.removeLayer("wms").removeSource("wms");
  status.textContent = "Reading the WMS capabilities…";
  wms ??= await getCapabilities(WMS, "WMS");
  map.addSource("wms", { ...wmsSource(wms, { layers: ["Coastlines_15m", "Reference_Labels_15m"] }), attribution: ATTRIBUTION });
  map.addLayer({ id: "wms", type: "raster", source: "wms" });
  status.textContent = "";
}

async function listLayers() {
  wmts = await getCapabilities(WMTS, "WMTS");
  // GIBS also lists vector tile layers; keep the images.
  const layers = wmts.layers.filter((l) => l.formats.some((f) => f.startsWith("image/"))).sort((a, b) => a.title.localeCompare(b.title));
  select.replaceChildren(...layers.map((l) => new Option(l.title, l.id)));
  select.value = "BlueMarble_ShadedRelief_Bathymetry";
  select.disabled = false;
  status.textContent = `${layers.length} layers`;
  showLayer(select.value);
}

const fail = (e) => (status.textContent = e.message);
await map.once("load");
listLayers().catch(fail);
select.addEventListener("change", () => showLayer(select.value));
document.getElementById("wms").addEventListener("change", (e) => showWms(e.target.checked).catch(fail));
