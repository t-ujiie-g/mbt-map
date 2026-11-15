import { Map } from "mbt-map";
import { transform } from "mbt-map/analysis";
import { createAttribution, createCoordinates, createNavigation, createScale, degrees, degreesMinutesSeconds, projected } from "mbt-map/ui";

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
    },
    layers: [{ id: "pale", type: "raster", source: "pale" }],
  },
  center: [139.7671, 35.6812],
  zoom: 14,
  bearing: -30,
  pitch: 40,
  attributionControl: false,
});
await map.once("load");

const $ = (id) => document.getElementById(id);
const watch = (controller, render) => {
  render(controller.state);
  controller.subscribe(render);
};

const nav = createNavigation(map);
watch(nav, (n) => {
  $("zoom-in").disabled = !n.canZoomIn;
  $("zoom-out").disabled = !n.canZoomOut;
  $("needle").style.transform = `rotateX(${n.pitch}deg) rotateZ(${-n.bearing}deg)`;
});
$("zoom-in").onclick = () => nav.zoomIn();
$("zoom-out").onclick = () => nav.zoomOut();
$("compass").onclick = () => nav.resetNorth(true);
$("home").onclick = () => nav.home();

watch(createScale(map, { maxWidth: 120 }), (s) => {
  $("scale").style.width = `${s.width}px`;
  $("scale").textContent = s.label;
});

watch(createAttribution(map, { customAttribution: "mbt-map" }), (a) => ($("attribution").textContent = a.text));

const systems = [degrees(), degreesMinutesSeconds(), projected({ id: "jgd-ix", title: "JGD2011 / 9", transform, crs: 6677 })];
watch(createCoordinates(map, { systems }), (c) => {
  $("coordinates").textContent = c.values.map((v) => `${v.title}\n  ${v.text}`).join("\n");
});
