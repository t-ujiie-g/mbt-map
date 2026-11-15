// The home page's map: PLATEAU's LOD2 buildings around Tokyo Station over GSI's pale map, lit as Tokyo is at
// the visitor's clock time (the sun's shadows by day, a dark map by night; `?time=18:30` for another time).
// It turns slowly until touched; the button swaps in the textured buildings.
import { Map, sunPosition } from "mbt-map";
import { tilesLayer } from "mbt-map/3d";

const TOKYO = [139.7671, 35.6812];
// PLATEAU's LOD2 buildings of Chiyoda, without textures (light to load) and with them (about 1 MB a tile).
const ASSETS = "https://assets.cms.plateau.reearth.io/assets/";
const NAME = "13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2";
const PLAIN = `${ASSETS}72/e900e5-938c-4376-a9de-a124b270880c/${NAME}_no_texture/tileset.json`;
const TEXTURED = `${ASSETS}28/07d0a1-b6be-46ef-bd87-4f0683b5ef6e/${NAME}/tileset.json`;
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it at Tokyo Station.
const GEOID = -36.7;

/** The visitor's wall-clock time (or `?time=HH:MM`, 00:00 to 23:59) taken as Tokyo's (UTC+9) today. */
function tokyoNow() {
  const now = new Date();
  const asked = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(new URLSearchParams(location.search).get("time") ?? "");
  const [h, m] = asked ? [Number(asked[1]), Number(asked[2])] : [now.getHours(), now.getMinutes()];
  return { date: new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), h - 9, m)), label: `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}` };
}

const mix = (a, b, t) => a + (b - a) * t;

/** The color between `night` and `noon` ([r, g, b]) at `day` (0 to 1). */
const shade = (night, noon, day) => `rgb(${night.map((c, i) => Math.round(mix(c, noon[i], day))).join(", ")})`;

/** The sky between a night and a clear day's. */
const sky = (day) => ({
  "sky-color": shade([9, 13, 28], [120, 178, 236], day),
  "horizon-color": shade([28, 36, 60], [222, 236, 250], day),
  "fog-color": shade([28, 36, 60], [222, 236, 250], day),
  "sky-horizon-blend": 0.7,
  "horizon-fog-blend": 0.6,
  "fog-ground-blend": 0.2,
});

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
        minzoom: 2,
        maxzoom: 18,
        attribution: "国土地理院 · 3D都市モデル（Project PLATEAU）千代田区（国土交通省）",
      },
    },
    sky: sky(0),
    layers: [
      { id: "background", type: "background", paint: { "background-color": shade([15, 20, 28], [233, 237, 242], 0) } },
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

// The one directional light by the sun's altitude, linear between -6° (night: a moon in the south-west), 0° (the
// horizon) and 10° (day). Ambient and directional add up to 0.96 at most, so a white wall facing the sun keeps
// its shape, and never to less than by night; shadows come in as the sun rises.
const ALTITUDES = [-6, 0, 10];
const AMBIENT_COLOR = [[132, 142, 165], [200, 196, 205], [255, 255, 255]];
const AMBIENT = [0.5, 0.58, 0.52];
const SUN_COLOR = [[205, 214, 234], [255, 184, 132], [255, 244, 230]];
const SUN = [0.3, 0.36, 0.44];
const SHADOWS = [0, 0, 0.55];
const MOON = [215, 50];
// A lower sun is drawn at this angle from up: grazing light leaves the roofs dark and one long shadow over all.
const LOWEST = 68;

/** `stops` (numbers or colors at ALTITUDES) at the sun's `altitude`. */
function at(stops, altitude) {
  const i = altitude < ALTITUDES[1] ? 0 : 1;
  const t = Math.min(1, Math.max(0, (altitude - ALTITUDES[i]) / (ALTITUDES[i + 1] - ALTITUDES[i])));
  const [a, b] = [stops[i], stops[i + 1]];
  return Array.isArray(a) ? `rgb(${a.map((c, k) => Math.round(mix(c, b[k], t))).join(", ")})` : mix(a, b, t);
}

/** Lights the scene for now: moonlight by night, the sun and its shadows by day, the map dark or light with them. */
function light() {
  const { date, label } = tokyoNow();
  const { azimuth, altitude } = sunPosition(date, ...TOKYO);
  // Day comes in over civil twilight, from the sun 6° below the horizon to 6° above.
  const day = Math.min(1, Math.max(0, (altitude + 6) / 12));
  // Below the horizon the light turns from the moon's place to the sun's, the short way round.
  const risen = Math.min(1, Math.max(0, (altitude + 6) / 6));
  const turn = ((azimuth - MOON[0] + 540) % 360) - 180;
  const direction = [(MOON[0] + turn * risen + 360) % 360, mix(MOON[1], Math.min(90 - altitude, LOWEST), risen)];
  const shadows = at(SHADOWS, altitude);
  map.setLights([
    { id: "ambient", type: "ambient", properties: { color: at(AMBIENT_COLOR, altitude), intensity: at(AMBIENT, altitude) } },
    { id: "sun", type: "directional", properties: { color: at(SUN_COLOR, altitude), intensity: at(SUN, altitude), direction, "cast-shadows": shadows > 0, "shadow-intensity": shadows } },
  ]);
  map.setSky(sky(day));
  map.setPaintProperty("background", "background-color", shade([15, 20, 28], [233, 237, 242], day));
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
