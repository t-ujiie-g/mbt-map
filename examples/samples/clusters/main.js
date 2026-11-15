import { Map } from "mbt-map";

// 500 random points scattered around Tokyo Station.
const points = Array.from({ length: 500 }, () => {
  const r = 0.25 * Math.sqrt(Math.random());
  const a = 2 * Math.PI * Math.random();
  return {
    type: "Feature",
    properties: {},
    geometry: { type: "Point", coordinates: [139.7671 + 1.2 * r * Math.cos(a), 35.6812 + r * Math.sin(a)] },
  };
});

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      pale: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tileSize: 256,
        maxzoom: 18,
        attribution: "国土地理院",
      },
      points: {
        type: "geojson",
        data: { type: "FeatureCollection", features: points },
        cluster: true,
        clusterRadius: 50,
        clusterMaxZoom: 14,
      },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      {
        id: "clusters",
        type: "circle",
        source: "points",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": ["step", ["get", "point_count"], "#74c0fc", 20, "#4c6ef5", 100, "#7048e8"],
          "circle-radius": ["step", ["get", "point_count"], 14, 20, 20, 100, 28],
          "circle-stroke-color": "#fff",
          "circle-stroke-width": 2,
        },
      },
      {
        id: "counts",
        type: "symbol",
        source: "points",
        filter: ["has", "point_count"],
        layout: { "text-field": ["get", "point_count_abbreviated"], "text-size": 13, "text-allow-overlap": true },
        paint: { "text-color": "#fff" },
      },
      {
        id: "points",
        type: "circle",
        source: "points",
        filter: ["!", ["has", "point_count"]],
        paint: { "circle-color": "#e8590c", "circle-radius": 5, "circle-stroke-color": "#fff", "circle-stroke-width": 1 },
      },
    ],
  },
  center: [139.7671, 35.6812],
  zoom: 9.5,
});

map.on("click", "clusters", async (e) => {
  const cluster = e.features[0];
  const zoom = await map.getSource("points").getClusterExpansionZoom(cluster.properties.cluster_id);
  map.easeTo({ center: cluster.geometry.coordinates, zoom });
});
map.on("mouseenter", "clusters", () => (map.getCanvas().style.cursor = "pointer"));
map.on("mouseleave", "clusters", () => (map.getCanvas().style.cursor = ""));
