// The home page's map: PLATEAU's LOD2 buildings around Tokyo Station over GSI's pale map, lit as Tokyo is at
// the visitor's clock time (the sun's shadows by day, a dark map by night; `?time=18:30` for another time).
// It turns slowly until touched; the button swaps in the textured buildings.
import { Map, sunPosition, timeOfDayLights } from "mbt-map";
import { tilesLayer } from "mbt-map/3d";

const TOKYO = [139.7671, 35.6812];
// PLATEAU's LOD2 buildings of Chiyoda, without textures (light to load) and with them (about 1 MB a tile).
const ASSETS = "https://assets.cms.plateau.reearth.io/assets/";
const NAME = "13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2";
const PLAIN = `${ASSETS}72/e900e5-938c-4376-a9de-a124b270880c/${NAME}_no_texture/tileset.json`;
const TEXTURED = `${ASSETS}28/07d0a1-b6be-46ef-bd87-4f0683b5ef6e/${NAME}/tileset.json`;
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station.
const GEOID = -36.7;

/** The visitor's wall-clock time (or `?time=HH:MM`) taken as Tokyo's (UTC+9) today. */
function tokyoNow() {
  const now = new Date();
  const asked = /^(\d{1,2}):(\d{2})$/.exec(new URLSearchParams(location.search).get("time") ?? "");
  const [h, m] = asked ? [Number(asked[1]), Number(asked[2])] : [now.getHours(), now.getMinutes()];
  return { date: new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), h - 9, m)), label: `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}` };
}

const mix = (a, b, t) => a + (b - a) * t;

/** The pale map's paint between night (0, dark gray) and day (1, light gray). */
const basemap = (day) => ({
  "raster-brightness-min": mix(0.42, 0.3, day),
  "raster-brightness-max": mix(0.08, 0.97, day),
  "raster-saturation": -1,
  "raster-contrast": mix(-0.2, -0.1, day),
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
        attribution: "国土地理院 · 3D都市モデル（Project PLATEAU）千代田区（国土交通省）",
      },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#0f141c" } },
      { id: "pale", type: "raster", source: "pale", paint: basemap(0) },
    ],
  },
  center: TOKYO,
  zoom: 16.2,
  pitch: 45,
  bearing: -30,
  maxPitch: 75,
});

const hint = document.querySelector(".map-card .hint");

/** Lights the scene for now: the sun and its shadows while it is up, the map light by day and dark by night. */
function light() {
  const { date, label } = tokyoNow();
  const altitude = sunPosition(date, ...TOKYO).altitude;
  // Day comes in over civil twilight, from the sun 6° below the horizon to 6° above.
  const day = Math.min(1, Math.max(0, (altitude + 6) / 12));
  // The sun as timeOfDayLights gives it; the ambient light kept bright enough at night to tell the buildings apart.
  const sun = timeOfDayLights(date, ...TOKYO).find((l) => l.type === "directional");
  const channel = (night, noon) => Math.round(mix(night, noon, day));
  map.setLights([
    { id: "ambient", type: "ambient", properties: { color: `rgb(${channel(120, 255)}, ${channel(138, 255)}, ${channel(190, 255)})`, intensity: mix(0.75, 0.55, day) } },
    { ...sun, properties: { ...sun.properties, "cast-shadows": altitude > 0, "shadow-intensity": 0.55 } },
  ]);
  for (const [name, value] of Object.entries(basemap(day))) map.setPaintProperty("pale", name, value);
  if (hint) hint.textContent = `${hint.dataset.text ?? (hint.dataset.text = hint.textContent)} · ${label}`;
}

map.on("load", () => {
  light();
  setInterval(light, 60_000);
  // A view this close needs no finer tiles than 16 px of error, which keeps the download small.
  const buildings = (url) => map.addLayer(tilesLayer({ id: "plateau", url, height: GEOID, maximumScreenSpaceError: 16 }));
  buildings(PLAIN);
  const textures = document.querySelector(".map-card .map-toggle");
  textures?.addEventListener("click", () => {
    const on = textures.getAttribute("aria-pressed") !== "true";
    textures.setAttribute("aria-pressed", String(on));
    map.removeLayer("plateau");
    buildings(on ? TEXTURED : PLAIN);
  });
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
