# Getting started

This page puts a map on a page, adds data to it, and explains how mbt-map's files are loaded, so that it works served as is, from a bundler, or under a Content Security Policy.

## Install

```sh
npm install mbt-map
```

The package is ES modules with TypeScript types. Besides the entry modules, `dist/` holds module workers and WebAssembly files, which the modules load from beside themselves when they are first needed.

## A first map

A map draws into an element that has a size. The style is a URL or a style object in the [MapLibre style specification](https://maplibre.org/maplibre-style-spec/); this one shows the pale map of the Geospatial Information Authority of Japan (国土地理院).

```html
<!doctype html>
<meta charset="utf-8">
<style>#map { height: 480px; }</style>
<script type="importmap">
  { "imports": { "mbt-map": "./node_modules/mbt-map/dist/index.js" } }
</script>
<div id="map"></div>
<script type="module" src="./main.js"></script>
```

```js
// main.js
import { Map } from "mbt-map";

const map = new Map({
  container: "map",
  style: {
    version: 8,
    sources: {
      gsi: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tileSize: 256,
        maxzoom: 18,
        attribution: "国土地理院",
      },
    },
    layers: [{ id: "gsi", type: "raster", source: "gsi" }],
  },
  center: [139.7671, 35.6812],
  zoom: 14,
});
```

Serve the folder over http (module workers do not load from `file:` URLs), for example with `npx serve`.

## Adding data

Sources and layers can be added once the style has loaded. Layer events receive the features under the pointer.

```js
map.on("load", () => {
  map.addSource("stations", {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [
        { type: "Feature", properties: { name: "東京駅" }, geometry: { type: "Point", coordinates: [139.7671, 35.6812] } },
        { type: "Feature", properties: { name: "有楽町駅" }, geometry: { type: "Point", coordinates: [139.7631, 35.6751] } },
      ],
    },
  });
  map.addLayer({
    id: "stations",
    type: "circle",
    source: "stations",
    paint: { "circle-radius": 7, "circle-color": "#2166ac", "circle-stroke-color": "#fff", "circle-stroke-width": 2 },
  });
});

map.on("click", "stations", (e) => {
  map.flyTo({ center: e.lngLat, zoom: 16 });
  console.log(e.features[0].properties.name);
});
```

Feature queries (`queryRenderedFeatures`, `querySourceFeatures`) return Promises, since the geometry lives in the workers. The [map guide](./map.md) covers the camera, styles, queries and the rest of `Map`.

## Other ways to use it

- **Web component**: `import "mbt-map/element"` and write `<mbt-map style-url="…" center="139.77,35.68" zoom="14">`. It works in plain HTML and in frameworks such as React. See [Web component](./web-component.md).
- **MoonBit**: `t-ujiie-g/mbtmap` is a typed MoonBit API over the npm package, and `t-ujiie-g/mbtmap_rabbita` puts the map in rabbita apps. See [MoonBit](./moonbit.md).
- **More entry points**: `mbt-map/ui`, `mbt-map/search`, `mbt-map/draw`, `mbt-map/geodesic`, `mbt-map/data`, `mbt-map/analysis`, `mbt-map/services` and `mbt-map/3d` are separate modules; a page that never imports one never downloads its code. Each has a guide in the [documentation index](./README.md).

## How files are loaded

Every module loads its workers and wasm with `new URL("./worker.js", import.meta.url)`, that is, from the same folder as itself, and its optional parts by dynamic `import()` from the same folder. Some examples:

| File | Loaded when |
|---|---|
| `worker.js`, `mbt-map.wasm` | a map is created (the tile workers) |
| `geojson.js`, `geojson-worker.js`, `geojson.wasm` | a style first has a GeoJSON source |
| `sprite.js`, `pmtiles.js`, `media.js`, `custom.js`, `export.js` | a style has a sprite, a `pmtiles://` source, an image or video source; the first custom layer; the first `toBlob` |
| `analysis-worker.js`, `analysis.wasm`, then `geometry.wasm`, `relate.wasm`, `shapes.wasm`, `surface.wasm`, `route.wasm`, `viewshed.wasm`, `proj.wasm` | the first `mbt-map/analysis` call, then the first call of each group |
| `data-worker.js`, `data.wasm`, then `xml.wasm`, `geotiff.wasm`, `proj.wasm` | the first `mbt-map/data` call, then the first KML/GPX, raster or reprojection |
| `geodesic-worker.js`, `geodesic.wasm` | the first `mbt-map/geodesic` call |
| `3d-worker.js`, `3d.wasm`, `3d-tiles.js`, `3d-i3s.js` | the first `mbt-map/3d` layer of each kind |

So the rule is: **keep the files of `dist/` together**. Serving `dist/` as it is (an import map, a CDN, a static copy) needs no configuration.

### Bundlers

Bundlers differ in how they treat `new URL(…, import.meta.url)`. esbuild leaves it as it is and bundles the dynamic imports, so it works when the workers and wasm are copied next to the bundle: every `*.wasm` file and the worker files and worker parts (`*worker*.js`, `data-*.js`, `analysis-*.js`, `prjwkt.js`, `projstring.js`). The React example does this in [`examples/react/build.mjs`](../examples/react/build.mjs). Other bundlers have not been checked yet; if one rewrites or drops these URLs, serve the files yourself and pass their locations:

- `new Map({ workerUrl, wasmUrl, geojsonWorkerUrl, geojsonWasmUrl, geojsonPropertiesWasmUrl })` for the map's workers.
- The last argument of `mbt-map/analysis`, `mbt-map/data` and `mbt-map/geodesic` functions takes `workerUrl`, `wasmUrl` and the URLs of the extra wasm files (`geometryWasmUrl`, `projWasmUrl`, `xmlUrl`, …); the worker starts with the options of the first call.

Workers must come from the page's origin over http(s), and wasm from an http(s) URL; `data:` and `blob:` URLs are refused.

### Content Security Policy

Compiling wasm needs `script-src 'wasm-unsafe-eval'`, and the workers need `worker-src 'self'` (or `script-src 'self'`). mbt-map uses no `eval` or `new Function`.

### Requests and credentials

Styles, TileJSON, tiles, sprites, GeoJSON and images are fetched without credentials. `transformRequest` (a `Map` option, or `setTransformRequest`) can change a request's URL, headers and credentials, for example to add an API key; what it sends is the page's responsibility.

## Next steps

- [The map](./map.md) and [style support](./style-support.md)
- [Examples](../examples/): the showcase app (search, layers, drawing, measurement, analysis, data, web services) in three styles, a 3D city page and a rabbita app
