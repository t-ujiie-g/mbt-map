import { Map } from "mbt-map";

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      photo: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg"],
        tileSize: 256,
        maxzoom: 18,
        attribution: "国土地理院",
      },
      dem: {
        type: "raster-dem",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png"],
        tileSize: 256,
        maxzoom: 14,
        // GSI has no elevation tiles over open sea: none are asked for south of the coast.
        bounds: [136.5, 34.61, 141, 37],
        encoding: "gsi",
        attribution: "国土地理院",
      },
    },
    layers: [
      { id: "photo", type: "raster", source: "photo" },
      { id: "hillshade", type: "hillshade", source: "dem", paint: { "hillshade-exaggeration": 0.3 } },
    ],
    terrain: { source: "dem", exaggeration: 1.5 },
    sky: { "sky-color": "#88c6fc", "horizon-color": "#ffffff", "fog-color": "#ffffff" },
  },
  center: [138.79, 35.44],
  zoom: 11.5,
  pitch: 70,
  bearing: -140,
});

const slider = document.getElementById("exaggeration");
const value = document.getElementById("value");
slider.oninput = () => {
  value.textContent = slider.value;
  map.setTerrain({ source: "dem", exaggeration: Number(slider.value) });
};
