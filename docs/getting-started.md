# Getting started

This page puts a map on a page, from a CDN or from npm, adds data to it, and explains how mbt-map's files are loaded, so that it works from a CDN, served as is, from a bundler, or under a Content Security Policy.

## A first map, from a CDN

The quickest start is one HTML file that loads mbt-map from a CDN through an import map. A map draws into an element that has a size; the style is a URL or a style object in the [MapLibre style specification](https://maplibre.org/maplibre-style-spec/). This one shows the pale map of the Geospatial Information Authority of Japan (国土地理院).

```html
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>A map</title>
<style>html, body, #map { height: 100%; margin: 0; }</style>
<script type="importmap">
  { "imports": { "mbt-map": "https://cdn.jsdelivr.net/npm/mbt-map@0.1.0/dist/index.js" } }
</script>
<div id="map"></div>
<script type="module">
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
</script>
</html>
```

Open it from any http server (module scripts and workers do not load from `file:` URLs), for example with `npx serve`. Other entry points go into the import map the same way, one line each: `"mbt-map/analysis": "https://cdn.jsdelivr.net/npm/mbt-map@0.1.0/dist/analysis.js"`. Pin the version in the URL; every file the modules load next (workers, wasm, parts) comes from the same folder of the CDN. Each [example](https://t-ujiie-g.github.io/mbt-map/examples/) shows its page in this form.

## Install from npm

```sh
npm install mbt-map
```

The package is ES modules with TypeScript types. Besides the entry modules, `dist/` holds module workers and WebAssembly files, which the modules load from beside themselves when they are first needed. Served as they are, the import map points at `./node_modules/mbt-map/dist/index.js` instead of the CDN; with a bundler, see [Bundlers](#bundlers).

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

Every module names its workers, their wasm and the parts the workers import later with `new URL("./worker.js", import.meta.url)`, that is, in the same folder as itself, and loads its own optional parts by dynamic `import()` from the same folder. The main thread sends those URLs to each worker when it starts it. Some examples:

| File | Loaded when |
|---|---|
| `worker.js`, `mbt-map.wasm` | a map is created (the tile workers) |
| `geojson.js`, `geojson-worker.js`, `geojson.wasm` | a style first has a GeoJSON source |
| `sprite.js`, `pmtiles.js`, `media.js`, `custom.js`, `export.js` | a style has a sprite, a `pmtiles://` source, an image or video source; the first custom layer; the first `toBlob` |
| `analysis-worker.js`, `analysis.wasm`, then `geometry.wasm`, `relate.wasm`, `shapes.wasm`, `surface.wasm`, `route.wasm`, `viewshed.wasm`, `proj.wasm` | the first `mbt-map/analysis` call, then the first call of each group |
| `data-worker.js`, `data.wasm`, then `xml.wasm`, `geotiff.wasm`, `proj.wasm` | the first `mbt-map/data` call, then the first KML/GPX, raster or reprojection |
| `geodesic-worker.js`, `geodesic.wasm` | the first `mbt-map/geodesic` call |
| `3d-worker.js`, `3d.wasm`, `3d-tiles.js`, `3d-i3s.js` | the first `mbt-map/3d` layer of each kind |

So the rule is: **keep the files of `dist/` together**. Serving `dist/` as it is (an import map, a CDN, a static copy) needs no configuration. Browsers start no worker script from another origin, so when the library itself comes from another origin (a CDN), its workers start through a small same-origin `blob:` script that imports them from there.

### Bundlers

Bundlers that understand `new URL("./file", import.meta.url)` find every worker, wasm file and worker part by themselves and emit them with the build. Checked by `npm run bundlers` in `bench/` (dev server and production build, in Chromium):

| Bundler | What it needs |
|---|---|
| Vite 8 | Nothing: `vite` and `vite build` work with the default configuration. The build inlines files under 4 KB (`build.assetsInlineLimit`), two small workers among them; see the Content Security Policy below. |
| webpack 5 | Nothing: `webpack serve` and `webpack` work with the default configuration (also with `output.publicPath` on another origin). |
| Rollup 4 | `@rollup/plugin-node-resolve` and [`@web/rollup-plugin-import-meta-assets`](https://www.npmjs.com/package/@web/rollup-plugin-import-meta-assets), which emits the files named by `new URL(…, import.meta.url)`. |
| esbuild | It leaves `new URL(…, import.meta.url)` as it is, so copy the files next to the bundle: every `*.wasm` file and the workers and their parts (`*worker*.js`, `data-*.js`, `analysis-*.js`, `prjwkt.js`, `projstring.js`). The React example does this in [`examples/react/build.mjs`](../examples/react/build.mjs). |
| Parcel 2 | Not supported as a bundled dependency: Parcel compiles every file named by `new URL(…, import.meta.url)` into its own module format, which breaks the library's module workers. Serve the package unbundled instead: copy `node_modules/mbt-map/dist/` next to the build and import it at run time, `const { Map } = await import(new URL("mbt-map/index.js", document.baseURI).href)`. |

When the build's files are served from another origin (a CDN for static assets), that origin must allow the page's with CORS; the workers then start as they do from a CDN.

To serve the workers and wasm yourself, pass their locations:

- `new Map({ workerUrl, wasmUrl, geojsonWorkerUrl, geojsonWasmUrl, geojsonPropertiesWasmUrl })` for the map's workers.
- The last argument of `mbt-map/analysis`, `mbt-map/data` and `mbt-map/geodesic` functions takes `workerUrl`, `wasmUrl` and the URLs of the extra wasm files (`geometryWasmUrl`, `projWasmUrl`, `xmlUrl`, …); the worker starts with the options of the first call.

A worker given by `workerUrl` imports its parts from beside itself (`worker.js` needs `worker-labels.js`, `worker-pmtiles.js` and `worker-query.js`; `data-worker.js` its `data-*.js`; `analysis-worker.js` needs `analysis-viewshed.js`), so copy them together. Workers given as options must come over http(s) from the page's origin or from the library's own folder (on a CDN), and wasm from an http(s) URL; `data:` and `blob:` URLs given as options are refused. Only the library's own default workers may be where a bundler put them, a `data:` URL included.

### Content Security Policy

Compiling wasm needs `script-src 'wasm-unsafe-eval'`, and the workers need `worker-src 'self'` (or `script-src 'self'`). Loaded from a CDN, the library also needs the CDN in `script-src` and `connect-src`, and `worker-src blob:` for the workers' bootstrap scripts; the same holds for a bundler's output served from another origin. A worker that a bundler inlined as a `data:` URL (Vite's build, files under 4 KB) starts from a same-origin `blob:` of the same text and needs `worker-src blob:` too, and a worker part inlined that way is imported from its `data:` URL, which needs `script-src data:`. To keep a strict policy with Vite, set `build.assetsInlineLimit: 0`: nothing is inlined and `'self'` is enough. mbt-map uses no `eval` or `new Function`.

### Requests and credentials

Styles, TileJSON, tiles, sprites, GeoJSON and images are fetched without credentials. `transformRequest` (a `Map` option, or `setTransformRequest`) can change a request's URL, headers and credentials, for example to add an API key; what it sends is the page's responsibility.

## Next steps

- [The map](./map.md) and [style support](./style-support.md)
- [Examples](../examples/): the showcase app (search, layers, drawing, measurement, analysis, data, web services) written with plain HTML and with React (and, in the repository, [with the `<mbt-map>` element alone](../examples/element/)), a 3D city page and a rabbita app
