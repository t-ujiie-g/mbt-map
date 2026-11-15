import { Map } from "mbt-map";

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
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: [139.7671, 35.6812],
  zoom: 14,
});
