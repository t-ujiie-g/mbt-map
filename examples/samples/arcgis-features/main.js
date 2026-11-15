import { Map } from "mbt-map";
import { arcgisFeatures, followView } from "mbt-map/services";

// Esri's sample layer of US cities; the service's terms and attribution are the page's to follow.
const CITIES = "https://services.arcgis.com/P3ePLMYs2RVChkJx/ArcGIS/rest/services/USA_Major_Cities_/FeatureServer/0";

const map = new Map({
  container: "map",
  style: "https://tiles.openfreemap.org/styles/positron",
  center: [-98, 39],
  zoom: 5,
});

const status = document.getElementById("status");
const city = document.getElementById("city");

await map.once("load");
map.addSource("cities", { type: "geojson", data: { type: "FeatureCollection", features: [] }, attribution: "Esri, U.S. Census Bureau" });
map.addLayer({
  id: "cities",
  type: "circle",
  source: "cities",
  paint: {
    "circle-radius": ["interpolate", ["linear"], ["get", "POPULATION"], 10000, 3, 1000000, 14],
    "circle-color": ["case", ["!=", ["get", "CAPITAL"], ""], "#d6342c", "#2f5bd0"],
    "circle-opacity": 0.7,
    "circle-stroke-color": "#fff",
    "circle-stroke-width": 1,
  },
});

followView(
  map,
  "cities",
  async (bbox, signal) => {
    status.textContent = "Loading…";
    const data = await arcgisFeatures(CITIES, { bbox, signal, outFields: ["NAME", "STATE_ABBR", "POPULATION", "CAPITAL"] });
    status.textContent = `${data.features.length} cities in view (red: capitals)`;
    return data;
  },
  { minzoom: 4 },
);
map.on("moveend", () => {
  if (map.getZoom() < 4) status.textContent = "Zoom in to load the cities.";
});

map.on("click", async (e) => {
  const [hit] = await map.queryRenderedFeatures(e.point, { layers: ["cities"] });
  const p = hit?.properties;
  city.textContent = p ? `${p.NAME}, ${p.STATE_ABBR}\npopulation ${p.POPULATION.toLocaleString("en-US")}` : "";
});
