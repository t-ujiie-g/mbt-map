# Architecture: data, analysis, services and UI modules

Part of the architecture reference ([index](ARCHITECTURE.md)). The entry points beside the map (`mbt-map/ui`, `search`, `draw`, `geodesic`, `services`, `data`, `analysis`) and the packages under them. Each ships as its own npm entry with its own lazily loaded worker and wasm and a row in `npm/scripts/size.mjs`; `map` and the facade never import them.

## Feature tables and the GeoJSON tiler

### `geom`

- `geom` holds columnar feature tables (`Table`: kinds, nested part/ring/point offsets over interleaved coordinates, GeoArrow's multipolygon layout for every kind; properties as one `Column` per key, padded by `TableBuilder::finish`).

### `formats`: the GeoJSON reader

- `formats` reads GeoJSON straight from UTF-8 into a table (no JSON tree; sticky errors; `MAX_GEOJSON_DEPTH` and `MAX_GEOJSON_KEYS`; numbers take Clinger's exact fast path up to 15 digits and core `strconv` beyond, which is the reader's main cost on full-precision data).

### `tiler`

- `tiler` is an exact port of @maplibre/geojson-vt 6.3.0 (`npm run geojson:golden` must stay at 0 differences).
  - Updates included (geojson-vt's `updateable` index, `Tiler::update` / `ClusterIndex::update` taking a `Diff`): the converted features kept with their table rows, rows appended for new and changed properties and compacted once dead ones dominate, a property-only update giving the features their new row in place, tiles invalidated as `invalidateTiles` and the top tile cut again (`npm run geojson:diffs`, 0 differences).
  - One deliberate deviation from geojson-vt (6.3.0, 6.3.1 and its main branch alike): an update with `removeAllProperties` and `addOrUpdateProperties` removes all and then adds (`Source::updated_row`), as MapLibre's `applySourceDiff` and the documented `GeoJSONSourceDiff` do; geojson-vt's `applyPropertyUpdates` returns `{}` and drops the added ones, which left the tiles drawn without the properties `getData()` had (every edit of `createFieldEditor`). The golden hands geojson-vt such an update as `removeProperties` of every key instead.
  - Clustering included (`ClusterIndex`, its `ClusterTileIndex` over a kdbush 4.1.0 port; `npm run cluster:golden`, 0 differences).
  - Clipped features live in per-clip `Store`s referenced by `FRef`, so a feature kept whole is shared and stores are freed like geojson-vt's objects.
- `@core.Trig` lets a wasm-gc build project with the host's `Math.sin`/`Math.log` (bit-identical to geojson-vt; the pure `@math` differs in the last bit now and then, which changed 314 of 4336 golden tiles), which moonrun cannot provide, so tests use the default.

## GeoJSON sources

- GeoJSON sources (`geojson.js`, loaded by the facade with a dynamic `import("./geojson.js")` only when a style has one): `npm/src/geojson.ts` starts `geojson_worker` (wasm-gc: `formats` + `tiler`, host `Math` for `Trig`), sends each source's data (URL fetched in the worker without credentials, or the object as UTF-8), and serves tiles by source id.
- `map` asks the facade's provider (`map/dom.mbt` `Provider`) for a GeoJSON tile, gets an `@tiler.encode_tile` buffer and posts it to a display worker as `bytes`; the display worker reads it as a `ColumnTile` (bounds-checked) behind the same `Features` enum as MVT layers, so filters, grouping and tessellation are shared.
- `map` keeps one `SourceTiles` per source its layers use; the facade strips GeoJSON `data` from the style the engine parses.

### Clusters

- A source with `cluster: true` is cut by a `ClusterIndex` instead (options derived as MapLibre's GeoJSONSource does, in `npm/src/geojson.ts`).
- `clusterProperties` are compiled on the main thread (engine export `compile_cluster_properties`, `["accumulated"]` in reduce) and reduced in `ClusterIndex` through `@tiler.ClusterProperties` (`cluster_props`), in a second module with expressions, `geojson-properties.wasm`, loaded only for such sources (expressions cost about 20KB gzip, past `geojson.wasm`'s budget), and `getSource(id)` answers `getClusterExpansionZoom` / `getClusterChildren` / `getClusterLeaves` through the GeoJSON worker.

### `updateData`

- `updateData` (MapLibre's `GeoJSONSourceDiff`; `npm/src/geojson-diff.ts`, `npm run geojson:update`) applies diffs in `geojson.js` to the features by id (MapLibre's error when ids are missing or repeated; a URL source's data comes back from the worker), one load per source at a time with the diffs meanwhile merged, edits the facade's style document and reloads only the tiles MapLibre's `shouldReloadTile` picks (`Map::reload_tiles` with a predicate from `geojson.js`; every tile for clusters and `removeAll`).
- The worker gets only the diff (docs/dev/FORMATS.md "GeoJSON diff", encoded in `geojson.js` by `geojson_worker/js/diff.mjs`) and applies it as geojson-vt's `updateData` (`@geojson_tiles.update`; feature ends from `@formats.read_geojson_features`, ids by the source's `promoteId`, which the worker loads with).

### Clipping

- Every tile is clipped to its own extent in the fragment shader (features reach into a buffer the neighbours draw too).

## `mbt-map/ui`

- `mbt-map/ui` (`npm/src/ui.ts`, built into `dist/ui.js` with no part of the main entry): headless controllers that take a `Map` and use only its public API, each in its own module under `npm/src/ui/` so a bundle keeps only those imported.
- All share `Store` (`ui/controller.ts`: `state` as a new object per change, `subscribe` returning the unsubscribe, `destroy`); what they compute follows MapLibre's controls (`npm run ui:golden`).
- Pure parts live in import-free modules (`ui/controller.ts`, `ui/measure.ts`, `attribution.ts`) for `npm test`; the controllers themselves are checked by the golden and the pack test.
- Things to draw (the location dot) are left to the page, with `map.track`.
- The legend splits a layer's color by the property a `match` / `step` / `interpolate` / `case` reads (`ui/legend-rules.ts`) and asks the engine for each entry's paint (`Map.evaluatePaint` → `Map::paint_at`, the same `paint_of` that draws).
- Basemaps swap styles with `setStyle`'s `transformStyle`, keeping overlay layers (`ui/overlays.ts`).

### Attribute table and field editor

- `createAttributeTable` lists one source's features (a GeoJSON source through `getSource(id).getData()`, a vector source through `querySourceFeatures` of the drawn tiles, one row per id), refreshed on that source's `sourcedata` (and `idle` for vector sources) and coalesced.
- It sorts with `Intl.Collator` (numbers, then text, then missing values; stable), filters with mbt-map/search's folding (`ui/table-rows.ts` is the pure part) and mirrors the selection with feature state.
- `createFieldEditor` (`ui/field-editor.ts`; `ui/table-fields.ts` is the pure part) edits a GeoJSON source's columns, read with `getData` and written with `updateData` (only the changed features' properties; `setData` when ids are missing, repeated or edited), values by style expression (`Map.evaluateExpression` → `@map.evaluate_expression`: the style's compiler and `Expr::eval` on the main thread, through `JsProps` with `$id` and `$type`; `npm run fields:golden` against style-spec) or by a function of the row, and keeps a table's columns with its `setColumns`.
- The facade fires `sourcedata` (`{ sourceId, dataType: "source" }`, after `styledata`, for each source whose spec object changed; unlike MapLibre, not on tile loads); `getSource` gives `promoteId`, and GeoJSON sources have `getData()` (a copy, or the URL fetched through `transformRequest` as `"Source"`).

## `mbt-map/search`

- `mbt-map/search` (`npm/src/search.ts`, `dist/search.js`): GeoSearch with `mbt-map/ui`'s `Store` (bundled into its own file).
- The controller debounces `setQuery`, aborts stale searches and drops their results; the bundled providers ask no server (`search/coordinates.ts` reads degrees, DMS, plane rectangular and UTM, the projected ones through a `transform` the page passes; `search/dataset.ts` matches GeoJSON properties folded by NFKC, case and kana).
- External APIs are providers of the same shape, their terms the page's concern.

## `mbt-map/draw`

- Drawing (`mbt-map/draw`, its own entry, ~4.9KB of a 10KB budget; under 8KB is better): `npm/src/draw/controller.ts` is a `Store` controller whose clicks follow terra-draw 1.37's modes and thresholds (`draw/shapes.ts`, import-free: 40 px to close, 20 px freehand steps, 64-point circles on the ellipsoid through mbt-map/geodesic's `circle`; coordinates rounded to 9 decimals, outer rings counter-clockwise and holes clockwise).
- Hits and snapping are pure functions of `draw/edit.ts` over `project`/`unproject` (Multi geometries flattened).
- `"select"` mode edits (`draw/edit.ts`, import-free: vertices, midpoints, moves, deletions, screen hit tests): a press on the selected shape disables `dragPan` until the release (the engine checks it on every move), one drag is one undo step; snapping goes to other shapes' vertices, then edges.
- Split and merge go through mbt-map/analysis (`splitFeatures`, `mergeFeatures` → `@overlay.split` / `merge`: chords from Clipper's open-path intersection cut a ring one at a time, holes go to the piece around them; pieces find their source by a temporary property).
- Shift+click adds to the selection, so drawing modes turn box zoom off too.
- `npm run draw:golden` drives the same clicks and drags on terra-draw.
- Shapes are drawn through two GeoJSON sources of its own (`npm/src/ui/overlays.ts` `addOverlay`, shared with the measurement controller): the features, set only when they or the selection change, and a small sketch source (the shape under way, vertices, handles) set on every move, which keeps a move at the same frames with 100 or 2000 shapes (`npm run draw:many`).
- In general a reloaded source asks for its tiles at once (`Map::reload_source`), so an update is on screen in the next frame, as with MapLibre (`npm run draw:setdata`).

## `mbt-map/geodesic`

- Geodesics (`mbt-map/geodesic`, its own entry, worker and wasm, decided in 14.1 because the analysis worker had no room): `geodesic` ports geographiclib-geodesic 2.2.0 (`Geodesic`: inverse and direct problems, `GeodesicLine`, `PolygonArea`; WGS 84 by default) and gives its numbers bit for bit given the host's `Math` (`npm run geodesic:golden`; engines' `Math` differ in the last bit now and then, so the pack test compares with geographiclib in the same page).
- `measure_path` and `densify` work on longitude, latitude pairs; `npm/src/geodesic.ts` is the Promise API (`inverse`, `direct`, `measure` with `step` for the drawn path).
- `mbt-map/ui`'s `createMeasurement` takes that `measure` from the page (as the coordinates controller takes `transform`), so `mbt-map/ui` loads no geodesic code; it draws its overlay through a GeoJSON source of its own (`mbt-map-measure`, layers marked `mbt-map:overlay`).
- `createProfile` (no map) takes the same `measure` and an `elevation` function (`mbt-map/analysis`'s `sampleDem`: the deepest DEM zoom whose tiles fit one grid, `DemGrid.sample` bilinear as GDAL's `-r bilinear`, checked by `npm run terrain:golden`).
- `npm/src/worker-client.ts` is the call plumbing the module entries share.

## `mbt-map/services`

- `mbt-map/services` (`npm/src/services.ts`, `dist/services.js`; Phase 18): reads GIS web services into style sources on the main thread, with the host's `DOMParser` for capabilities (`services/xml.ts` matches elements by local name; ServiceExceptionReport and ows:ExceptionReport throw).
- WMS 1.1.1/1.3.0 layers inherit as WMS 1.3.0 §7.2.4.8 says.
- These make `raster`/`vector` sources:
  - `wmsSource`;
  - `wmtsSource` (Web Mercator quadtree sets whose matrix ids are the zooms, `zoomTemplate`);
  - `arcgisSource` (a Web Mercator cache's `tile/{z}/{y}/{x}`, else `export` / `exportImage`; a VectorTileServer's vector tiles);
  - `arcgisVectorStyle` / `arcgisStyle` (Esri's `root.json` with its relative URLs made absolute and the service's source written out, which MapLibre needs; the facade reads the relative ones as is);
  - `ogcTileSource` (WebMercatorQuad).
- `ogcFeatures` / `wfsFeatures` / `arcgisFeatures` gather GeoJSON features page by page (`services/features.ts` `gather`: `next` links, STARTINDEX, `resultOffset`; capped by `MAX_FEATURES` and `MAX_PAGES`, a repeated page URL stops it), which `followView` re-asks for each view (aborting the last).
  - `wfsFeatures` reads GML 2/3.1/3.2 in EPSG:4326 when no GeoJSON is offered: `services/gml.ts` `readGml`, properties as OpenLayers' GMLBase, axis order by srsName and what was asked, `srsNorthFirst`.
  - `arcgisFeatures` asks for `f=pbf` when the layer lists it, else `f=geojson`, else `f=json`, and reads the Esri formats in `services_worker` (services.wasm, its own size row): `@formats.read_esri_json` ports terraformer's `arcgisToGeoJSON`, `read_esri_pbf` reads FeatureCollection.proto as arcgis-pbf-parser does; `npm run esri:golden`.
- `followImage` keeps an image source on one `export` / GetMap of the view (`wmsImage`, `arcgisImage`, as OpenLayers' `ImageWMS` / `ImageArcGISRest`), and `wmsFeatureInfo` / `arcgisIdentify` ask about a 101-pixel window around a click (OpenLayers' `getFeatureInfoUrl`).
- Tile sources in EPSG:3857 use the engine's placeholders (`{bbox-epsg-3857}`).

### Reprojected sources

- Layers and tile matrix sets without Web Mercator become mbt-map's own `reprojected` source (`ReprojectedSource` in `services/common.ts`; a raster source without `tiles` in the engine, like `geotiff`): the facade asks mbt-map/data's worker for its tiles (`reprojectTile`, `data_worker/js/reproject.mjs` → `data-reproject.js`), which takes each pixel's center to the service's CRS through proj.wasm and reads the WMTS tiles of the coarsest matrix still finer than the tile, or one GetMap of the tile's box, nearest-sampled (`npm run reproject:golden`; axis order by `northFirst`).

### Tests and limits

- `services/common.ts`, `arcgis.ts`, `ogcapi.ts` and `features.ts` are import-free for `npm test` (the others need only `xml.ts` and `common.ts`).
- The readers are checked by `npm run services:golden` against OpenLayers and ogc-client on live services (Node, xmldom with `firstElementChild` added for OpenLayers) and by the pack test's `services` page.
- Fetches go through `transformRequest` as `"Source"`, without credentials, capped at `MAX_DOCUMENT_BYTES` a document and `MAX_GATHERED_BYTES` a gathering.
- WMS capabilities at `MAX_WMS_LAYERS`, Esri pages at `MAX_RING_STEPS` (formats).
- The data worker's reprojection refuses images larger than asked, gives up on one after 30 s and keeps `MAX_KEPT_PIXELS`.

## `mbt-map/data`

### CSV, WKT, WKB, shapefiles and TopoJSON

- Data reading (`mbt-map/data`, its own entry, worker and wasm; Phase 17): `formats` reads CSV (RFC 4180; papaparse's delimiter guess, header renaming and `dynamicTyping`; points from latitude/longitude columns, 緯度/経度 included, or a WKT / hex WKB column found by name), WKT/EWKT and WKB/EWKB/hex into a `@geom.Table` (collections flattened, Z/M dropped).
- `data_worker` outputs Table bytes, which `wasmio/js/table.mjs` decodes, and `npm/src/table.ts` wraps them in a `Table` (the bytes stay on the page for `toGeoJSON` until the first operation transfers them to the analysis worker; `layer` / `layers` for shapefiles in a zip and TopoJSON objects).
- `formats` also reads shapefiles (`read_shapefile`: clockwise rings outer, holes to the smallest outer ring containing them, written counter-clockwise; DBF text through a host `decode` callback by `.cpg`, language driver or option; deleted records skipped; dates as `YYYY-MM-DD`) and TopoJSON (`read_topojson`, topojson-client's `feature`).
- The WKT/WKB/CSV readers report each row's SRID (`srids?`), and the worker takes rows to 4326 through proj.wasm, loaded on first use (`data_worker/js/crs.mjs` → `data-crs.js`; f64 pairs per CRS, never per point; an explicit SRID wins, then `crs`, then the `.prj`).
- `.prj` WKT1 is read by `npm/src/prjwkt.ts` (a wkt-parser port, imported by the worker only for a `.prj`) and zips by `npm/src/zip.ts` (`data-zip.js`: central directory, stored and `DecompressionStream` deflate, caps on entries and the inflated total).
- `crsArg` (`npm/src/crs.ts`) is shared with mbt-map/analysis.
- `npm run data:golden` must stay 0 differ.

### KML, KMZ and GPX

- KML/KMZ and GPX are read by a second module, `xml.wasm` (`xml_worker`, its own size row, loaded by the data worker on the first such read): `xml` is an XML reader as lenient as xmldom 0.9.12's DOMParser (sticky errors, caps on depth, attributes and nodes; declared entities never expanded), and `kml` ports togeojson 7.1.3's `kml()` and `gpx()` into a `@geom.Table` (MultiGeometry flattened to rows, styles as simplestyle values, nested values as JSON text, Placemark ids through `ids_out`).
- A KMZ is a zip read by the shared `npm/src/zip.ts` (`kmlOfKmz` in `data_worker/js/read.mjs`: `doc.kml`, else the first `.kml`).
- KML and GPX are in EPSG:4326: they skip the CRS step and refuse `crs`.
- `npm run xml:golden` must stay 0 differ.

### FlatGeobuf

- FlatGeobuf (`@formats.read_flatgeobuf`, flatgeobuf 4.6.1's `deserialize`: Json values as their text, Binary as base64, curves refused) is read whole by data.wasm.
- With `bbox`, `data_worker/js/fgb.mjs` (`data-fgb.js`, import-free) reads the header, walks the packed R-tree (flatgeobuf's `streamSearch`, capped against trees that loop) and gathers the features found, by HTTP range requests from a URL, into the header plus those features and their indices for `read_flatgeobuf(ids)`.
- The header's CRS is the data's unless `crs` is given.
- `npm run fgb:golden` must stay 0 differ.

### Writing

- Writing (`write`): GeoJSON is `JSON.stringify(toGeoJSON())` in the facade.
- CSV is `@formats.write_csv` in data.wasm (papaparse's `unparse`, WKT as betterknown's `geoJSONToWkt`), KML `@kml.write_kml` in xml.wasm (tokml's `toKML`), both from Table bytes with numbers by the host's `String(x)`.
- A GeoJSON object is first read by data.wasm's `read_geojson`.
- `npm run write:golden` must stay 0 differ.

### GeoTIFF and COG

- GeoTIFF and COG (`readRaster`, geotiff 3.0.5's `readRasters`): `tiff` (pure) reads the IFDs (BigTIFF, either byte order) and decodes blocks (none, LZW, PackBits; predictors 2 and 3; bits narrower than a byte; float16) into a window's bands.
- `geotiff_worker` (geotiff.wasm, its own size row with `data-geotiff.js`) is loaded by the data worker on the first raster read, and `data_worker/js/geotiff-read.mjs` chooses the image and window as geotiff does, fetches the blocks the window meets (range requests from a URL, merged when close; slices of a Blob), inflates Deflate with `DecompressionStream` and decodes JPEG and WebP with the browser, and resamples.
- `mbt-map/analysis`'s `loadGrid` makes a band an `@analysis.Grid` (`load_grid`; samples taken to the raster's CRS through proj.wasm, PixelIsPoint as GDAL reads it).
- `npm run geotiff:golden` must stay 0 differ.

### `geotiff` sources

- A style's `geotiff` source (mbt-map's own type) is a raster source (a `raster-dem` one with `dem: true`, Terrarium) without `tiles` in the engine (`style/source.mbt`).
- The facade completes its `bounds` and `maxzoom` from the file as it does TileJSON (`GEOTIFF` keys, `geotiff-source.js`).
- The engine asks its provider for the tiles, which `rasterTile` draws in the data worker and a display worker decodes as raster or DEM bytes.
  - `renderTile`: each pixel's center taken to the file's CRS, by proj.wasm (`transformPairs` in `crs.mjs`, one call per tile) unless it is EPSG:3857 or 4326; `rasterInfo`'s bounds from its edges taken to 4326, the coarsest image still finer than the tile, colors, Terrarium; headers and blocks kept per URL.
- `npm run geotiff:tiles` must stay all ok.

## `mbt-map/analysis`

- Analysis (`mbt-map/analysis`, its own entry, worker and wasm; never imported by `map` or the facade): `analysis` is pure MoonBit (a flatbush port `Index`, measures and `contains_point` matching Turf.js bit for bit given the host's `Math`, `points_within`, `nearest_pairs`, `grid_count`).
- `analysis_worker` keeps datasets by handle with their index built on first use.
- Attribute operations: `tableops` is pure MoonBit (select, filter, derive, orderby, slice, rollup and join over `@geom.Table`, rows read by a `@style.FeatureContext`, the order of two values as Arquero's comparator, a stable merge sort, Arquero's aggregates and the row order of its hash join; rows group and match by an identity string of their keys' types and values; `join_pairs` and `rollup_pairs` put together or aggregate rows paired elsewhere, which is how spatial joins are made: relate.wasm or the analysis wasm gives the pairs, table.wasm the table; `column_groups` gives `@overlay.dissolve_groups` its groups in geometry.wasm) and `table_worker` (table.wasm, its own size row, the host's `Math`, `Number`, `String` and `Intl`, loaded by the analysis worker on the first such operation) compiles the expressions it is sent: `npm/src/pack.ts` packs their JSON into bytes (docs/dev/FORMATS.md "Table operations"), so the wasm links no JSON parser (measured: compiling on the page in JS takes 41.8KB gzip beside a 25.5KB evaluator, compiling in the wasm 11KB more in one module). `npm run table:golden` compares it with Arquero 8.0.3 (must stay 0 differ).
- `npm/src/table.ts` (`mbt-map/table`) is the Promise API of tables: `read` / `parse` / `write` through the data worker, `fromGeoJSON` and a `Table`'s operations through the analysis worker. A `Table` is its rows on the page (as read) or a handle to them in the analysis worker; results come back with their row count and column names (`columns_out`). `npm/src/analysis.ts` keeps grids, transforms and class breaks, `npm/src/data.ts` rasters. The three load `clients.js` (`npm/src/clients.ts`: one `WorkerClient` per worker and `defineCrs`'s names), so a page has one data and one analysis worker whichever entries it imports.
- `npm run analysis:golden` must stay all identical.

### Spatial relations

- `relate` ports JSTS 2.12.1's `RelateOp` (GeometryGraph, monotone-chain sweep, `RobustLineIntersector` with its DD orientation; OGC SFS boundary rule) and its `Geometry` predicates over `@geom.Table` rows.
- `relate_worker` (relate.wasm, its own size row, loaded by the analysis worker on the first `relate`) finds candidate pairs by their boxes and keeps those in the relation or matching a DE-9IM pattern (`npm/src/relate-pattern.ts` packs it and refuses patterns disjoint pairs match).
- `npm run relate:golden` must stay all identical.

### Shapes

- `robust` ports robust-predicates' `orient2d`, `simplify` Turf's `simplify`, `hull` concaveman (and Turf's `convex` through it), `delaunay` delaunator and d3-delaunay's Voronoi, `lineops` Turf's `nearestPointOnLine` and `lineSlice` (spherical, through `@core.Trig`).
- `shapes_worker` (shapes.wasm, its own size row, the host's `Math`, loaded by the analysis worker on first use) runs them over a dataset's Table bytes.
- `npm run shapes:golden` must stay all identical.

### Surfaces

- `grids` ports Turf's point, square, hex and triangle grids and `interpolate` (IDW), `clusters` its `clustersDbscan` and `clustersKmeans` (skmeans), `isolines` its `isolines` and `isobands`, `density` d3-contour's `contours` and `contourDensity` (d3-array's ticks and blur, Float32 grids emulated).
- `surface_worker` (surface.wasm, its own size row, the host's `Math` and `String(number)` for band labels) takes a table, a property name and f64s (breaks) as one input, and maps points to `density`'s pixel grid and back.
- `npm run surface:golden` must stay all identical.

### Viewsheds

- `viewshed` ports GDAL 3.13.3's `gdal_viewshed` (`Viewshed`, `ViewshedExecutor` single-threaded in the order its threads produce the same values, x86 casts, the curvature factor from the CRS's semi-major; `a * b + c` fused where clang on arm64 contracts it, through a software `fma`, so it matches the M2's GDAL bit for bit and an x86-64 build without FMA by a few ulps in DEM and GROUND modes).
- `viewshed_worker` (viewshed.wasm, its own size row with `analysis-viewshed.js`, the glue `analysis_worker/js/viewshed.mjs` the analysis worker imports on the first viewshed) gets a grid's elevations from the analysis worker, a DEM grid in ground meters per cell at its middle latitude (its slopes' scale) and a GeoTIFF grid in its projected CRS.
- `DemGrid.lineOfSight` samples the grid and decides in `npm/src/sight.ts` (import-free).
- `npm run viewshed:golden` needs GDAL, so it runs on the M2 (all identical; GDAL reads the AAIGrid it is handed as Float32 unless opened with `DATATYPE=Float64`).

### Routing

- `route` ports geojson-path-finder 2.1.0 (rounded vertex keys by their doubles' bits, which group as its `String` keys do; insertion-ordered neighbour maps with JS objects' delete and re-insert order; tinyqueue; phantom vertices removed after each query).
- `route_worker` (route.wasm, its own size row) keeps `Network`s by handle for repeated `Network.route` calls.
- `npm run route:golden` must stay all identical.
- `network({ snap })` (meters, default 0: the graph as geojson-path-finder's) nodes the lines first (`@route.snap_lines`, as pgRouting's `pgr_nodeNetwork` or GRASS's `v.clean tool=snap,break`): line ends join the earliest group of ends within `snap`.
- Each group then moves to the nearest point of a segment within `snap` of it, which that segment gets as a vertex (to another group's end: where that group goes).
- Distances are in the equirectangular plane at the end's latitude on Turf's sphere; a line's own segments within 2 × `snap` of its end along it (as routes weigh it) and its own other end on a line no longer than that are left out.
- Segments sit in a grid hash of cells the larger of `snap` and the mean segment extent, capped by `MAX_SNAP_CELLS` and `MAX_SNAP_TESTS`.
- `npm run route:snap` checks it with a brute-force oracle (every end with something within `snap` shares a vertex, moved at most 2 × `snap`; vertices added lie on their segments) and routes over GSI roads cut to their tiles against the uncut ones (none lost); the showcase routes with `snap: 2`.

### Classification and statistics

- Classification and statistics run on the main thread in `npm/src/classify.ts` (import-free, re-exported by `mbt-map/analysis`): simple-statistics' jenks, ckmeans, quantile, equal intervals and statistics, geostats' standard deviation classes with unrounded mean and deviation, and `classStep` for the `step` expressions the legend splits.
- `npm run classify:golden` must stay all identical.

- Terrain analysis on DEM grids (`@analysis.Grid`, `loadDem`) is under "Terrain" in [ARCHITECTURE-RENDERING.md](ARCHITECTURE-RENDERING.md); `loadGrid` under "GeoTIFF and COG" above.

## Geometry operations

- `clipper` (the module `t-ujiie-g/clipper` in `ports/clipper`, published on its own) ports Clipper2 2.0.1 (boolean operations, open paths, solution trees, offsetting) and must give exactly the paths of the C++ library (`npm run clipper:golden` against clipper2-wasm, built from the same commit: must stay all identical).
- Its intersection list is sorted by a port of libc++'s `std::sort` (`libcxx_sort.mbt`), since ties make results differ and `std::sort` is not stable; do not swap in another sort.
- `overlay` runs it over `@geom.Table`s: geodesic buffers in a per-feature azimuthal equidistant plane scaled by the ellipsoid's two radii of curvature (edges split to 0.01° first; `bench/clipper/buffer-check.mjs` measures it with GeographicLib), planar ones in the coordinates' own plane (the worker takes the dataset into the CRS first and back after), and clip/erase/intersect/dissolve/split/merge in 1e-7° integers.
- Geodesic buffers come out within ±180° (`overlay/antimeridian.mbt`): `may_wrap` lets features that cannot reach ±180° or a pole through untouched; for the rest each ring is unprojected with continuous longitudes (every edge the short way round), which shows how often it turns around the axis. Rings that close go in as they are with their copies a turn away, rings around a pole as one path through the copies closed along -90°, plus the whole world once per time the polygons cover the north pole; Clipper cuts the positive winding to the world's rectangle in 1e-7° integers. Output edges are not split: a long straight side of a buffer is still two vertices.
- Buffer distances: a negative one shrinks polygons and leaves lines and points without geometry (Clipper offsets open paths by the distance's size, so `@overlay.buffer` leaves them out; Turf's `buffer` gives nothing for them); a geodesic buffer takes at most `MAX_GEODESIC_BUFFER` (10,000 km: a point's circle within a hemisphere, the plane within 0.6% of GeographicLib's distance there, 0.1% at 1,000 km), a planar one `MAX_COORDINATE` (`buffer_refusal`).
- `geometry_worker` (geometry.wasm, its own size row) is loaded by the analysis worker on the first geometry call; datasets cross between the two modules as Table bytes inside that worker.

## Coordinate systems

- `proj` (pure) ports proj4js 2.22.0's pipeline (27 projections of lib/projections/, 3- and 7-parameter `towgs84` shifts through WGS 84, prime meridians, units; `npm run proj:golden` against proj4js must stay within 1 mm / 1e-8°).
- A CRS is a `Definition` (a parsed PROJ string; radians, NaN for a parameter not given) or an EPSG code `Crs::from_epsg` knows (Japan's datums, plane rectangular zones and UTM, WGS 84 UTM, Web Mercator).
- Where proj4js is plainly wrong the port follows PROJ and says so in a comment (false origins it drops, `+R_A`'s radius).
- Projections give NaN out of reach and `transform` turns that into `None`.
- Computing goes through `Trig` (call-site default `Trig::moonbit()`): `proj_worker` (proj.wasm, its own size row, loaded by the analysis and data workers on first CRS use) passes the host's `Math`, which leaves core math out of it, computes as proj4js does and is faster than `@math` in wasm-gc (PROGRESS.md).
- Datasets in the analysis worker are always in 4326; the worker takes coordinates through proj.wasm as f64 pairs (`coords_out` / `with_coords`, `@geom.Table::map_coords`), never Table bytes.
- PROJ strings are parsed on the TS side (`npm/src/projstring.ts`, its own lazily imported file) into docs/dev/FORMATS.md "CRS definition"; `ports/proj/encoding.mbt` reads them.
