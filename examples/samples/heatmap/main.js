import { Map } from "mbt-map";

// Points clustered around a few centers, each with a random weight from 0 to 1.
const centers = [[139.7671, 35.6812], [139.7005, 35.6905], [139.7016, 35.658], [139.7109, 35.7295], [139.7774, 35.7141]];
const features = Array.from({ length: 2000 }, (_, i) => {
  const [lng, lat] = centers[i % centers.length];
  const r = 0.03 * Math.sqrt(-2 * Math.log(1 - Math.random()));
  const a = 2 * Math.PI * Math.random();
  return {
    type: "Feature",
    properties: { weight: Math.random() },
    geometry: { type: "Point", coordinates: [lng + r * Math.cos(a), lat + r * Math.sin(a)] },
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
      points: { type: "geojson", data: { type: "FeatureCollection", features } },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      {
        id: "heat",
        type: "heatmap",
        source: "points",
        maxzoom: 14,
        paint: {
          "heatmap-weight": ["get", "weight"],
          "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 9, 0.1, 14, 1],
          "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 9, 16, 14, 40],
          "heatmap-color": [
            "interpolate", ["linear"], ["heatmap-density"],
            0, "rgba(33, 102, 172, 0)",
            0.2, "rgb(103, 169, 207)",
            0.4, "rgb(209, 229, 240)",
            0.6, "rgb(253, 219, 199)",
            0.8, "rgb(239, 138, 98)",
            1, "rgb(178, 24, 43)",
          ],
          "heatmap-opacity": ["interpolate", ["linear"], ["zoom"], 13, 1, 14, 0],
        },
      },
      {
        id: "points",
        type: "circle",
        source: "points",
        minzoom: 13,
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["get", "weight"], 0, 3, 1, 9],
          "circle-color": ["interpolate", ["linear"], ["get", "weight"], 0, "rgb(103, 169, 207)", 1, "rgb(178, 24, 43)"],
          "circle-opacity": ["interpolate", ["linear"], ["zoom"], 13, 0, 14, 0.8],
          "circle-stroke-color": "#fff",
          "circle-stroke-width": 1,
          "circle-stroke-opacity": ["interpolate", ["linear"], ["zoom"], 13, 0, 14, 1],
        },
      },
    ],
  },
  center: [139.735, 35.69],
  zoom: 10.5,
});
