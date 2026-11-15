# mbt-map

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

Styles follow the MapLibre style specification and the `Map` API is shaped like MapLibre GL JS's.

| Entry | What it gives |
|---|---|
| `mbt-map` | `Map`, the map |
| `mbt-map/element` | the `<mbt-map>` web component |
| `mbt-map/ui` | headless UI controllers |
| `mbt-map/search` | geographic search |
| `mbt-map/draw` | drawing and editing |
| `mbt-map/geodesic` | distances, areas and circles on the WGS 84 ellipsoid |
| `mbt-map/data` | reading and writing GIS data |
| `mbt-map/analysis` | spatial analysis and coordinate systems |
| `mbt-map/services` | GIS web services |
| `mbt-map/3d` | 3D models, 3D Tiles, I3S and point clouds |
| `mbt-map/moonbit` | the entry the MoonBit API (`t-ujiie-g/mbtmap` on mooncakes) imports |

The modules load their workers and `.wasm` files from beside themselves: keep the files of `dist/` together. With a bundler, copy the workers and wasm next to the bundle or pass their URLs ([Getting started](https://github.com/t-ujiie-g/mbt-map/blob/main/docs/getting-started.md#bundlers)).

Requires WebAssembly GC (Chrome and Edge 119+, Firefox 120+, Safari 18.2+). Under a Content Security Policy, allow `script-src 'wasm-unsafe-eval'` and `worker-src 'self'`.

Documentation: <https://github.com/t-ujiie-g/mbt-map/blob/main/docs/README.md>

Licensed under the Apache License 2.0; ported code keeps its licenses (NOTICE).
