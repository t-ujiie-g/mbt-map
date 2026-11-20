# mbt-map

[![npm](https://img.shields.io/npm/v/mbt-map)](https://www.npmjs.com/package/mbt-map)
[![downloads](https://img.shields.io/npm/dm/mbt-map)](https://www.npmjs.com/package/mbt-map)
[![CI](https://github.com/t-ujiie-g/mbt-map/actions/workflows/ci.yml/badge.svg)](https://github.com/t-ujiie-g/mbt-map/actions/workflows/ci.yml)
[![license](https://img.shields.io/npm/l/mbt-map)](https://github.com/t-ujiie-g/mbt-map/blob/main/LICENSE)
[![types](https://img.shields.io/npm/types/mbt-map)](https://www.npmjs.com/package/mbt-map)
[![mooncakes](https://img.shields.io/badge/mooncakes-t--ujiie--g%2Fmbtmap-8a2be2)](https://mooncakes.io/docs/t-ujiie-g/mbtmap)

A lightweight WebGIS library for the browser, written in MoonBit: vector and raster maps, GIS data formats, spatial analysis, GIS web services and 3D city models in one toolkit, each part loaded only when a page first uses it.

```sh
npm install mbt-map
```

```js
import { Map } from "mbt-map";

const map = new Map({
  container: "map",
  style: "https://example.com/style.json",
  center: [139.7671, 35.6812],
  zoom: 14,
});
map.on("click", "stations", (e) => console.log(e.features[0].properties.name));
```

From a CDN, no install: `<script type="importmap">{ "imports": { "mbt-map": "https://cdn.jsdelivr.net/npm/mbt-map@0.2.0/dist/index.js" } }</script>`, then `import { Map } from "mbt-map"` in a module script.

Styles follow the MapLibre style specification and the `Map` API is shaped like MapLibre GL JS's.

| Entry | What it gives |
|---|---|
| `mbt-map` | `Map`, the map |
| `mbt-map/element` | the `<mbt-map>` web component |
| `mbt-map/ui` | headless UI controllers |
| `mbt-map/search` | geographic search |
| `mbt-map/draw` | drawing and editing |
| `mbt-map/geodesic` | distances, areas and circles on the WGS 84 ellipsoid |
| `mbt-map/table` | tables of features: reading and writing GIS data, spatial analysis |
| `mbt-map/data` | GeoTIFF and COG pixels and tiles |
| `mbt-map/analysis` | elevation grids, coordinate systems, class breaks |
| `mbt-map/services` | GIS web services |
| `mbt-map/3d` | 3D models, 3D Tiles, I3S and point clouds |
| `mbt-map/moonbit` | the entry the MoonBit API (`t-ujiie-g/mbtmap` on mooncakes) imports |

The modules load their workers and `.wasm` files from beside themselves: keep the files of `dist/` together. Vite and webpack need no configuration; for other bundlers see ([Getting started](https://t-ujiie-g.github.io/mbt-map/docs/getting-started.html#bundlers)).

Requires WebAssembly GC (Chrome and Edge 119+, Firefox 120+, Safari 18.2+). Under a Content Security Policy, allow `script-src 'wasm-unsafe-eval'` and `worker-src 'self'`.

Documentation and examples: <https://t-ujiie-g.github.io/mbt-map/> · Source: <https://github.com/t-ujiie-g/mbt-map>

Licensed under the Apache License 2.0; ported code keeps its licenses (NOTICE).
