# Changelog

All notable changes to the npm package `mbt-map` and the MoonBit modules `t-ujiie-g/mbtmap` and `t-ujiie-g/mbtmap_rabbita`. They share one version.

## 0.2.0

Reading, analysis and display share one table. Some names move or change: [docs/migrating.md](docs/migrating.md) has the list.

- `mbt-map/table` (new): `read`, `parse` and `write` (from `mbt-map/data`) and `Table`, the one type for what was `DataTable` and `Dataset`. What `read` gives is analysed as it is; its rows move into the analysis worker on the first operation.
- `mbt-map/table`: attribute operations named as Arquero's (`select`, `filter`, `derive`, `orderby`, `slice`, `groupby`, `rollup` with 14 aggregates, `join`), with style expressions for conditions and computed values. Results match Arquero 8.0.3.
- `mbt-map/table`: `spatialJoin` and `nearestJoin` give the joined table or, with `rollup`, aggregates per row; `dissolve({ by })` merges per group; `dbscan` and `kmeans` return the table with cluster columns.
- `mbt-map`: a GeoJSON source's `data` may be a `Table`. Its rows go to the source's worker as bytes: nothing is turned into GeoJSON on the page.
- `mbt-map/table`: Arrow IPC (`fromArrow`, `toArrowIPC`; GeoArrow WKB and native geometry; Feather; LZ4 and ZSTD buffers) and GeoParquet (`read`; Snappy, GZIP and ZSTD; `bbox` and `columns` by HTTP range requests, row groups passed over by GeoParquet 1.1's covering column).
- `mbt-map/data` is now rasters only (`readRaster`, `rasterInfo`, `rasterTile`, `reprojectTile`); `mbt-map/analysis` keeps elevation grids, coordinate transforms and classification.
- Removed: `load` and `Dataset` from `mbt-map/analysis` (`fromGeoJSON` and `Table` in `mbt-map/table`), `DataTable.tableBytes`, `Dataset.collect` (`spatialJoin` with `rollup`).

## 0.1.1

- `mbt-map`: a map with `interactive: false` is no longer a tab stop (its canvas gets `tabindex="-1"`, as MapLibre's).
- `mbt-map/ui`: the attribute table's `reveal(id)` goes to the page with a feature's row; `zoomTo` fits a feature split at the antimeridian across it, not to the whole world (so do the dataset search's result boxes).
- `mbt-map/3d`: `hemisphere`, an option of `modelLayer`, `tilesLayer` and `i3sLayer` that shades the ambient light on faces turned away from the directional light, so the side of a model the light does not reach keeps its shape. The default draws as before.
- `mbt-map/analysis`: geodesic `buffer` results stay within ±180° of longitude. A buffer across the antimeridian is cut there into a MultiPolygon, and one that holds a pole runs along ±180° to the pole's latitude, so it fills as a cap in planar tools. Before, longitudes passed ±180° and a buffer over a pole was a ring around it. Buffers that reach neither are unchanged.
- `mbt-map/analysis`: a geodesic `buffer` of a MultiPoint is a circle around each point. Before, points far apart were buffered as the line through them.

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
