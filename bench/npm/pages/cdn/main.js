// The map's tile workers, its GeoJSON worker and the analysis worker, all from the CDN origin.
import { Map } from "mbt-map";
import { load } from "mbt-map/analysis";

const tokyo = [139.7671, 35.6812];
const places = { type: "FeatureCollection", features: [{ type: "Feature", properties: { name: "東京駅" }, geometry: { type: "Point", coordinates: tokyo } }] };
const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: { places: { type: "geojson", data: places } },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "places", type: "circle", source: "places", paint: { "circle-radius": 20, "circle-color": "#ff0000" } },
    ],
  },
  center: tokyo,
  zoom: 14,
  attributionControl: false,
});
map.once("load", async () => {
  window.__loaded = performance.now();
  await map.once("idle");
  const features = await map.queryRenderedFeatures([400, 300]);
  const centroids = await (await load(places)).centroids();
  window.__cdn = {
    module: import.meta.resolve("mbt-map"),
    names: features.map((f) => f.properties.name),
    centroid: Array.from(centroids),
  };
});
