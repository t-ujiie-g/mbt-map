# mbt-map

A lightweight WebGIS library for the browser, written in [MoonBit](https://www.moonbitlang.com/). Vector and raster maps, GIS data formats, spatial analysis, GIS web services and 3D city models come together in one toolkit, and each part loads only when a page first uses it.

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

Documentation, examples and a live demo: **<https://t-ujiie-g.github.io/mbt-map/>**

## What it does

- **Maps**: vector tiles, raster and terrain tiles, GeoJSON (clustering, live updates), PMTiles, images and video; styles in the MapLibre style specification, labels and icons, 3D terrain, sky, globe view, extruded buildings, lights and shadows. The `Map` API is shaped like MapLibre GL JS's.
- **Data** (`mbt-map/data`): read CSV, WKT/WKB, GeoJSON, Shapefile, TopoJSON, KML/KMZ, GPX, FlatGeobuf and GeoTIFF/COG; write GeoJSON, CSV and KML; reproject between coordinate systems, Japan's plane rectangular systems included.
- **Analysis** (`mbt-map/analysis`): measures, spatial indexes and relations, buffers and overlays, simplification, hulls, Voronoi diagrams, interpolation, contours, clustering, routing, classification, terrain slope and viewsheds.
- **Web services** (`mbt-map/services`): WMS, WMTS, WFS, OGC API and ArcGIS REST layers as map sources and features.
- **3D** (`mbt-map/3d`): glTF models, 3D Tiles, I3S scene layers and LAS point clouds, with picking, lines of sight, viewsheds and clipping.
- **Tools**: headless UI controllers (`mbt-map/ui`: scale, legend, layer list, measurement, attribute table, …), search (`mbt-map/search`), drawing and editing (`mbt-map/draw`), measurement on the ellipsoid (`mbt-map/geodesic`).
- **Ways to use it**: a JavaScript/TypeScript API, the `<mbt-map>` web component (works in React and other frameworks), and a typed MoonBit API with a binding for the [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) web framework.

The engine and the heavy parts (tile decoding, tessellation, analysis, format readers) are MoonBit compiled to WebAssembly and run in workers; the main thread keeps a small TypeScript layer.

## Install

```sh
npm install mbt-map
```

Or without installing, from a CDN in one HTML file:

```html
<script type="importmap">
  { "imports": { "mbt-map": "https://cdn.jsdelivr.net/npm/mbt-map@0.1.0/dist/index.js" } }
</script>
<script type="module">
  import { Map } from "mbt-map";
  new Map({ container: "map", style: "https://example.com/style.json", center: [139.7671, 35.6812], zoom: 14 });
</script>
```

The package is plain ES modules plus workers and `.wasm` files that load from beside the module. Served as is (an import map, or a static copy of `dist/`), it works without configuration; with a bundler, see [Getting started](docs/getting-started.md#bundlers).

For MoonBit apps (js target):

```sh
moon add t-ujiie-g/mbtmap            # typed API
moon add t-ujiie-g/mbtmap_rabbita    # rabbita binding
```

## Entry points

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

## Documentation

- [Getting started](docs/getting-started.md)
- [Documentation index](docs/README.md): the map, styles, the web component, MoonBit, and a guide for each entry point
- [Examples](examples/): one showcase app written with the JavaScript API, the web component and React, a 3D city (PLATEAU) page and a rabbita app

## Browsers

mbt-map needs WebAssembly GC: Chrome and Edge 119+, Firefox 120+, Safari 18.2+. Every release is tested in Chromium, Firefox and WebKit (Safari's engine) by the same browser checks. Pages using a Content Security Policy need `script-src 'wasm-unsafe-eval'` and `worker-src 'self'`; mbt-map uses no `eval`.

## Development

The repository holds the MoonBit engine, the npm package (`npm/`), the web component (`element/`), the MoonBit API (`moonbit/`), examples and the test and comparison scripts (`bench/`). Contributor notes are in [AGENTS.md](AGENTS.md), the design in [docs/dev/VISION.md](docs/dev/VISION.md), the architecture reference in [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md) and the state of work in [PROGRESS.md](PROGRESS.md).

## License

[Apache License 2.0](LICENSE). Ported code keeps its original licenses, listed in [NOTICE](NOTICE). The examples read tiles of the Geospatial Information Authority of Japan (国土地理院) and PLATEAU's 3D city models (国土交通省).
