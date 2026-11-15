import { Map } from "mbt-map";
import { transform } from "mbt-map/analysis";
import { coordinates, createSearch, datasetSearch } from "mbt-map/search";

const PLACES = [
  ["東京駅", "とうきょうえき", "Tokyo Station", 139.7671, 35.6812],
  ["東京タワー", "とうきょうたわー", "Tokyo Tower", 139.7454, 35.6586],
  ["東京スカイツリー", "とうきょうすかいつりー", "Tokyo Skytree", 139.8107, 35.7101],
  ["浅草寺", "せんそうじ", "Senso-ji", 139.7967, 35.7148],
  ["上野公園", "うえのこうえん", "Ueno Park", 139.7745, 35.7156],
  ["新宿御苑", "しんじゅくぎょえん", "Shinjuku Gyoen", 139.7101, 35.6852],
  ["明治神宮", "めいじじんぐう", "Meiji Jingu", 139.6993, 35.6764],
  ["皇居", "こうきょ", "Imperial Palace", 139.7528, 35.6852],
];
const places = {
  type: "FeatureCollection",
  features: PLACES.map(([name, kana, en, lng, lat]) => ({ type: "Feature", properties: { name, kana, en }, geometry: { type: "Point", coordinates: [lng, lat] } })),
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
        maxzoom: 18,
        attribution: "国土地理院",
      },
      chosen: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
    },
    layers: [
      { id: "pale", type: "raster", source: "pale" },
      { id: "chosen", type: "circle", source: "chosen", paint: { "circle-radius": 8, "circle-color": "#e4572e", "circle-stroke-color": "#fff", "circle-stroke-width": 2 } },
    ],
  },
  center: [139.7671, 35.6812],
  zoom: 12,
});
await map.once("load");

const search = createSearch(map, {
  providers: [coordinates({ transform }), datasetSearch(places, { fields: ["name", "kana", "en"], label: (f) => `${f.properties.name} ${f.properties.en}` })],
});

const input = document.getElementById("query");
const list = document.getElementById("results");

search.subscribe((s) => {
  input.setAttribute("aria-expanded", String(s.open));
  input.setAttribute("aria-activedescendant", s.active >= 0 ? `result-${s.active}` : "");
  list.replaceChildren(
    ...(s.open ? s.results : []).map((r, i) => {
      const li = document.createElement("li");
      li.id = `result-${i}`;
      li.role = "option";
      li.ariaSelected = String(i === s.active);
      li.textContent = r.label;
      li.append(Object.assign(document.createElement("small"), { textContent: r.provider }));
      li.onclick = () => search.select(i);
      return li;
    }),
  );
  if (s.selected) {
    const { lng, lat } = s.selected.lngLat;
    map.getSource("chosen").setData({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [lng, lat] } });
  }
});

input.oninput = () => search.setQuery(input.value);
input.addEventListener("keydown", (e) => {
  if (e.isComposing || e.keyCode === 229) return;
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    search.move(e.key === "ArrowDown" ? 1 : -1);
  } else if (e.key === "Enter") {
    if (search.state.results.length) search.select();
    else search.submit().then(() => search.select());
  } else if (e.key === "Escape") search.close();
});
