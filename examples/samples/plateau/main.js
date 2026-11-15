import { Map } from "mbt-map";
import { tilesLayer } from "mbt-map/3d";

const TILESET =
  "https://assets.cms.plateau.reearth.io/assets/72/e900e5-938c-4376-a9de-a124b270880c/13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2_no_texture/tileset.json";
// PLATEAU's heights are above the ellipsoid; the geoid lies 36.7 m above it here.
const GEOID = -36.7;

const SHOWN = {
  "gml:name": "Name",
  "bldg:usage": "Usage",
  "bldg:measuredHeight": "Height (m)",
  "bldg:storeysAboveGround": "Storeys",
  "uro:BuildingIDAttribute_uro:buildingID": "Building ID",
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
        attribution: "国土地理院 | 出典：「3D都市モデル（Project PLATEAU）千代田区（2025年度）」（国土交通省）（https://www.mlit.go.jp/plateau/）",
      },
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: [139.7671, 35.6812],
  zoom: 16.5,
  pitch: 60,
  bearing: -20,
});

const buildings = tilesLayer({ id: "plateau", url: TILESET, height: GEOID });
const status = document.getElementById("status");
const feature = document.getElementById("feature");
buildings.ready.catch((e) => (status.textContent = `The tileset was not read: ${e.message}`));

await map.once("load");
map.addLayer(buildings);

map.on("click", async (e) => {
  const hit = await buildings.queryFeature(e.point);
  feature.textContent = hit
    ? Object.entries(SHOWN)
        .filter(([key]) => hit.properties[key] != null)
        .map(([key, label]) => `${label}: ${hit.properties[key]}`)
        .join("\n")
    : "";
  status.textContent = hit ? "" : "Click a building.";
});
