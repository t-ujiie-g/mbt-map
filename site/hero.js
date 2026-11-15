// The map on the home page: PLATEAU's 3D buildings around Tokyo Station (3D Tiles, mbt-map/3d) over GSI's
// pale map turned dark, lit by a low sun with shadows, turning slowly until someone touches it.
import { Map } from "mbt-map";
import { tilesLayer } from "mbt-map/3d";

const TILESET =
  "https://assets.cms.plateau.reearth.io/assets/72/e900e5-938c-4376-a9de-a124b270880c/13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2_no_texture/tileset.json";
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station.
const GEOID = -36.7;

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
        attribution: "国土地理院 · 3D都市モデル（Project PLATEAU）千代田区（国土交通省）",
      },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#0f141c" } },
      {
        id: "pale",
        type: "raster",
        source: "pale",
        // Brightness from light to dark turns the pale map into a night one.
        paint: { "raster-brightness-min": 0.42, "raster-brightness-max": 0.08, "raster-saturation": -1, "raster-contrast": -0.2 },
      },
    ],
  },
  center: [139.7671, 35.6812],
  zoom: 15.25,
  pitch: 60,
  bearing: -30,
  maxPitch: 75,
});

map.on("load", () => {
  map.setLights([
    { id: "ambient", type: "ambient", properties: { color: "#b8c4dd", intensity: 0.45 } },
    { id: "sun", type: "directional", properties: { color: "#fff1dc", intensity: 0.75, direction: [235, 55], "cast-shadows": true, "shadow-intensity": 0.6 } },
  ]);
  map.addLayer(tilesLayer({ id: "plateau", url: TILESET, height: GEOID }));
});

// A slow turn, stopped for good by the first touch (and never started for those who ask for less motion).
const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
let turning = !still;
const stop = () => (turning = false);
for (const type of ["pointerdown", "wheel", "touchstart", "keydown"]) map.getContainer().addEventListener(type, stop, { passive: true });
let last = 0;
const turn = (now) => {
  if (!turning) return;
  if (last && map.loaded()) map.setBearing(map.getBearing() + (now - last) * 0.0025);
  last = now;
  requestAnimationFrame(turn);
};
requestAnimationFrame(turn);
