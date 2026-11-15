import assert from "node:assert/strict";
import test from "node:test";
import { attributionParts, attributionsOf, attributionText } from "../src/attribution.ts";

const style = {
  sources: {
    a: { attribution: "Long source A" },
    b: { attribution: "B" },
    c: { attribution: "source A" },
    dem: { attribution: "DEM" },
    unused: { attribution: "never" },
    blank: { attribution: "  " },
  },
  layers: [
    { id: "a", source: "a" },
    { id: "b", source: "b", minzoom: 10 },
    { id: "c", source: "c", maxzoom: 14 },
    { id: "hidden", source: "unused", layout: { visibility: "none" } },
    { id: "blank", source: "blank" },
  ],
  terrain: { source: "dem" },
};

test("attributionsOf: sources of layers shown at the zoom and of the terrain, shortest first", () => {
  assert.deepEqual(attributionsOf(style, 12), ["B", "DEM", "Long source A"]);
});

test("attributionsOf: a layer outside its zoom range leaves its source out", () => {
  assert.deepEqual(attributionsOf(style, 8), ["DEM", "Long source A"]);
  assert.deepEqual(attributionsOf(style, 14), ["B", "DEM", "Long source A"]);
  assert.deepEqual(attributionsOf({}, 3), []);
});

test("inZoomRange and layerShown: MapLibre's isHidden, the zoom range alone or with visibility", async () => {
  const { inZoomRange, layerShown } = await import("../src/attribution.ts");
  const layer = { minzoom: 10, maxzoom: 14, layout: { visibility: "none" } };
  assert.deepEqual([9.9, 10, 13.9, 14].map((z) => inZoomRange(layer, z)), [false, true, true, false]);
  assert.equal(layerShown(layer, 12), false);
  assert.equal(layerShown({ minzoom: 10 }, 12), true);
  assert.equal(inZoomRange({}, 0), true);
});

test("attributionParts keeps http(s) links and text, drops other tags and decodes entities", () => {
  const html = '<a href="https://openfreemap.org" target="_blank">OpenFreeMap</a> <a href="https://www.openmaptiles.org/">&copy; OpenMapTiles</a> Data from <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
  assert.deepEqual(attributionParts(html), [
    { text: "OpenFreeMap", href: "https://openfreemap.org" },
    { text: " " },
    { text: "© OpenMapTiles", href: "https://www.openmaptiles.org/" },
    { text: " Data from " },
    { text: "OpenStreetMap", href: "https://www.openstreetmap.org/copyright" },
  ]);
  assert.equal(attributionText(html), "OpenFreeMap © OpenMapTiles Data from OpenStreetMap");
  assert.deepEqual(attributionParts("国土地理院"), [{ text: "国土地理院" }]);
});

test("attributionParts refuses links that are not http(s) and keeps their text only", () => {
  assert.deepEqual(attributionParts('<a href="javascript:alert(1)">x</a><b>bold</b><script>y</script>a&lt;b<br>c'), [{ text: "xboldya<b c" }]);
  assert.deepEqual(attributionParts("<a href='http://a.example'>A</a>&#169;&#xA9;&bogus;"), [{ text: "A", href: "http://a.example" }, { text: "©©&bogus;" }]);
  assert.deepEqual(attributionParts("1 < 2"), [{ text: "1 < 2" }]);
});
