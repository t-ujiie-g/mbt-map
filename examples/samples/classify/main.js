import { Map } from "mbt-map";
import { classBreaks, classStep } from "mbt-map/analysis";
import { fromGeoJSON, grid } from "mbt-map/table";

const BOX = [139.68, 35.62, 139.83, 35.74];
const CENTERS = [[139.7671, 35.6812], [139.7006, 35.6896], [139.7016, 35.658], [139.7774, 35.7141], [139.7109, 35.7295]];
const COLORS = ["#fef0d9", "#fdcc8a", "#fc8d59", "#e34a33", "#b30000"];

// Seeded random points clustered around a few stations, so every load looks the same.
let seed = 7;
const random = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
const gaussian = () => Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());
const places = {
  type: "FeatureCollection",
  features: Array.from({ length: 4000 }, (_, i) => {
    const [lng, lat] = CENTERS[i % CENTERS.length];
    return { type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [lng + gaussian() * 0.014, lat + gaussian() * 0.011] } };
  }),
};

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      pale: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tileSize: 256,
        minzoom: 2,
        maxzoom: 18,
        attribution: "国土地理院",
      },
      cells: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "cells", type: "fill", source: "cells", paint: { "fill-color": COLORS[0], "fill-opacity": 0.75, "fill-outline-color": "#fff" } },
    ],
  },
  center: [139.755, 35.68],
  zoom: 11.5,
});
await map.once("load");

const cells = await grid(BOX, 1, "square");
const counted = await cells.spatialJoin(await fromGeoJSON(places), { rollup: { count: ["count"] } });
const count = await counted.array("count");
// The table is the source's data as it is.
map.getSource("cells").setData(counted);

const legend = document.getElementById("legend");
const method = document.getElementById("method");

/** A break as the legend shows it: one decimal at most. */
const round = (v) => Number(v.toFixed(1));

function classify() {
  const breaks = classBreaks(count, COLORS.length, method.value);
  map.setPaintProperty("cells", "fill-color", classStep(["get", "count"], breaks, COLORS));
  legend.replaceChildren(
    ...COLORS.flatMap((color, i) => {
      const swatch = document.createElement("i");
      swatch.style.background = color;
      const label = document.createElement("span");
      const [from, to] = [round(breaks[i]), round(breaks[i + 1])];
      // A class of one value (jenks' top class is often the maximum alone) reads as that value.
      label.textContent = from === to ? `${from}` : `${from} – ${to}`;
      return [swatch, label];
    }),
  );
}
classify();
method.onchange = classify;
