# Changelog

All notable changes to the npm package `mbt-map` and the MoonBit modules `t-ujiie-g/mbtmap` and `t-ujiie-g/mbtmap_rabbita`. They share one version.

## 0.1.0

The first release.

- `mbt-map`: a map drawn with WebGL2 from styles in the MapLibre style specification, with a `Map` API shaped like MapLibre GL JS's: vector and raster tiles, GeoJSON (clusters, updates), PMTiles, images and video, labels and icons, 3D terrain, sky, globe, world copies across the antimeridian, extrusions, lights and shadows, feature queries and state, custom layers, image export, touch gestures.
- `mbt-map/element`: the `<mbt-map>` web component.
- `mbt-map/data`: CSV, WKT/WKB, GeoJSON, Shapefile, TopoJSON, KML/KMZ, GPX, FlatGeobuf and GeoTIFF/COG in; GeoJSON, CSV and KML out; coordinate systems.
- `mbt-map/analysis`: measures, spatial indexes and relations, buffers and overlays, shapes, surfaces and clustering, routing, classification, terrain analysis and viewsheds.
- `mbt-map/services`: WMS, WMTS, WFS, OGC API and ArcGIS REST.
- `mbt-map/3d`: glTF models, 3D Tiles, I3S and LAS point clouds; picking, lines of sight, viewsheds and clipping.
- `mbt-map/ui`, `mbt-map/search`, `mbt-map/draw`, `mbt-map/geodesic`: headless UI controllers, search, drawing and editing, geodesic measurement.
- `t-ujiie-g/mbtmap`: a typed MoonBit API (styles and expressions generated from the style specification); `t-ujiie-g/mbtmap_rabbita`: the map in rabbita apps.
- Loading: from a CDN in one HTML file (an import map; workers start through a same-origin blob), served as is, or through a bundler. Vite and webpack need no configuration, Rollup one plugin, esbuild a copy step; Parcel only with the library served unbundled.
- Browsers: Chrome and Edge 119+, Firefox 120+, Safari 18.2+ (WebAssembly GC). The test pages run in Chromium, Firefox and WebKit.

Documentation, examples and samples: <https://t-ujiie-g.github.io/mbt-map/>.
