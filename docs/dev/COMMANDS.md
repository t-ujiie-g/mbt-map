# Commands

The full command list. `AGENTS.md` §1 has the few every session needs (the validation loop, build, test, size, the pack test). A golden compares mbt-map with a reference implementation; "must stay …" is its pass condition.

## MoonBit

Run from the repository root:

```sh
moon check --target all          # type-check every backend (wasm, wasm-gc, js, native)
moon test --target all           # all tests on all backends
moon test <pkg-dir> --target all # one package, e.g. moon test bench/backend/kernel
moon test <pkg-dir> -F "glob"    # filter tests by name
moon test <pkg-dir> -u           # update snapshots (single target only; -u fails with --target all)
moon fmt && moon info            # before committing; regenerates pkg.generated.mbti
```

## npm package

Run from `npm/`:

- `npm ci && npm run build` writes `dist/` (index.js + .d.ts, worker.js, mbt-map.wasm).
- `npm run size` checks the gzip budgets of VISION §2 (rows in `npm/scripts/size.mjs`).
- `npm test` runs the unit tests (`npm/test/*.test.ts`, `element/*.test.ts` and the `*.test.mjs` of `worker/js`, `geojson_worker/js`, `wasmio/js`, `data_worker/js`) with Node type stripping, so modules under test must be import-free or import other files with their extension (`./images.ts`, `./style.ts`, `./urls.ts`, `./camera.ts`).
- `worker/js/mirror.test.mjs` checks the constants JS mirrors from MoonBit (`KIND_*`, `LAYER_ENTRY_WORDS`, `ENTRY_*`, label columns).

## Benchmarks and goldens

Run from `bench/` (Node + Playwright), after `npm ci && npx playwright install chromium firefox webkit`.

- Bench entry points that import TypeScript or MapLibre sources run through `node lib/run-bundled.mjs <entry>`; the MoonBit side of every mvt/tess bench is the single export package `bench/entry`.
- Results go to `bench/results/*.json`; numbers in PROGRESS.md must come from there (VISION §2: never claim "fast" without a reproducible script).
- Performance runs (`*:node`, `*:browser`, `render`, `cesium`, `draw:many`, `draw:setdata`) are never run in parallel and count only on the M2 dev machine (`AGENTS.md` §2 and §5).
- Release check: `node lib/release.mjs vX.Y.Z` (tag, versions and CHANGELOG agree; `npm test`'s `release.test.mjs` checks the versions and CHANGELOG without a tag; [RELEASING.md](RELEASING.md)).

### Fixtures, tooling, serving and packaging

- `npm run fixtures`: download GSI tiles, verify against sha256 manifest.
- `npm test`: Node tests for bench tooling (lib/*.test.mjs).
- `npm run example`: serve the repo on 127.0.0.1:8080 (the dev pages bench/pages/{basic,terrain} need only this).
- `npm run examples`: also pack npm/ into examples/{html,element,react} and bench/npm/pages/ (bench/npm/prepare.mjs), then serve /examples/.
- `npm run moonbit:style`: regenerate the MoonBit API's typed layer and source functions (moonbit/mbtmap/style/*.g.mbt) from the pinned style-spec's v8.json, then `moon fmt`; `npm test` fails while they are stale.
- `npm run site`: the GitHub Pages site into _site/ (site/ home pages, docs/*.md through marked, npm/dist once as lib/, the examples on it); serve it with `npm run example` at /_site/. Published by .github/workflows/pages.yml on a v* tag or by hand.
- `npm run bundlers`: mbt-map under bundlers (bench/bundlers/run.mjs): packs npm/, installs the tarball and pinned versions of Vite, webpack, Rollup, esbuild and Parcel into a temporary directory outside the repository (downloads them from npm; not part of CI) and checks in Chromium, for each dev server and build, that the map draws, a query finds its features and mbt-map/analysis, mbt-map/data (with a CRS) and mbt-map/geodesic answer; builds served from another origin too. Parcel's rows are known failures (it must stay "serve unbundled", which is checked); `-- --only=vite,webpack`, `--no-build` (dist/ as it is), `--keep` (leave the projects). Writes bench/results/bundlers.json.
- `npm run npm:pack`: build + npm pack npm/, install it there, check examples and test pages in Chromium (CI runs this; `-- --browser=firefox|webkit` runs them in Firefox or WebKit, as CI's `pack firefox …` / `pack webkit …` jobs; `--only=a,b` / `--except=a,b` pick checks by name; `--no-prepare` reuses the last packing).

### Engine: backends, decode, tessellation, rendering speed

- `npm run backend:node`: backend comparison in Node (builds MoonBit + wasm-opt first).
- `npm run backend:browser`: same, inside a module Worker in Chromium/Firefox/WebKit.
- `npm run maplibre:parse`: MapLibre WorkerTile.parse baseline.
- `npm run maplibre`: MapLibre first-render / frame-time / bundle-size baseline.
- `npm run mvt:golden`: mvt vs @mapbox/vector-tile on all fixtures (must stay 35/35).
- `npm run mvt:node`: mvt decode bench in Node.
- `npm run mvt:browser`: same, inside a module Worker in Chromium/Firefox/WebKit.
- `npm run tess:golden`: fills vs MapLibre's classifyRings + earcut on all fixtures (must stay 35/35).
- `npm run tess:node`: decode + tessellation vs MapLibre WorkerTile.parse in Node.
- `npm run tess:browser`: same, inside a module Worker in Chromium/Firefox/WebKit.
- `npm run subdivision:golden`: tess's globe subdivision vs MapLibre 6.16's subdividePolygon / subdivideVertexLine on GSI polygons and lines and seeded random ones, poles and zoom 0 included (must stay 0 differ).
- `npm run worker:browser`: worker process_tile per fixture, cold and warm, in three browsers.
- `npm run render`: mbt-map vs MapLibre: first render, frame CPU, bundle sizes (same style); node render/run.mjs --labels adds the label layers, --line-labels contour labels along lines.
- `npm run split`: the module-split measurement behind "one wasm per entry" (bench/split; rerun when revisiting that granularity).

### Styles, sources and the map

- `npm run style:golden`: style rendering vs MapLibre 6.16 pixel by pixel, a small style per scene (bench/style/scenes.mjs; each scene's limits must hold).
- `npm run style:public`: the public styles vs MapLibre 6.16 pixel by pixel on tiles of their schema for the GSI area: OpenMapTiles' on OpenFreeMap's (bench/fixtures/ofm-planet), @protomaps/basemaps' five flavors on a Protomaps build (bench/fixtures/protomaps); symbol layers left out; each scene's limits must hold.
- `npm run style:compat`: public styles (bench/style/public-styles.mjs, pinned by sha256) read with every request refused: what mbt-map leaves out of each.
- `npm run expression:golden`: expressions vs style-spec 26.5.0's createExpression on GSI features, legacy filters/functions vs its convertFilter/convertFunction (must stay 0 problems).
- `npm run color:golden`: style's parse_color vs style-spec 26.5.0's parseCssColor: named, hex, rgb() and hsl() in every syntax (must stay 0 differ).
- `npm run fields:golden`: Map.evaluateExpression (the field editor's expressions) vs style-spec 26.5.0's createExpression(...).evaluate on GSI features as GeoJSON: value-typed expression cases and field formulas (must stay all identical).
- `npm run raster:golden`: raster sources and paint vs MapLibre 6.16, pixel by pixel, also on the globe (needs the gsi-std and gsi-std-world fixtures); the tile URLs both request.
- `npm run pmtiles:golden`: PMTiles archives read by worker/js/pmtiles.mjs vs pmtiles 4.5.0, and drawn vs MapLibre from the files.
- `npm run labels:golden`: label placement vs MapLibre 6.16 in Chromium: the labels shown, their anchors (text-variable-anchor), icons and their boxes, and glyphs along lines (GSI contours), same tiles and camera (must stay all identical).
- `npm run labels:atlas`: the glyph atlas over a long session: Liberty on ofm-planet with CJK labels changed step by step; no "atlas is full", the last step drawn as in a fresh page.
- `npm run query:golden`: queryRenderedFeatures / querySourceFeatures vs MapLibre 6.16 in Chromium, same tiles and camera (must stay all identical).
- `npm run track:golden`: project / unproject / Map.track's `covered` on terrain vs MapLibre 6.16 (Mt Fuji DEM as Terrarium; must stay within 1e-6 px and agree).
- `npm run export:golden`: Map.toBlob: parts joined vs drawn whole, pixelRatio 1 vs the canvas, 2x raster vs MapLibre on a 2x screen.
- `npm run camera:golden`: core's camera math vs MapLibre's Camera in Node with frozen time (constrain, project, getBounds, cameraForBounds, easeTo, flyTo).
- `npm run globe:golden`: globe's camera vs MapLibre 6.16's globe projection in Node with frozen time (constrain, project, occlusion, unproject, matrices, getBounds, cameraForBounds, easeTo, flyTo, gestures, inertia, coveringTiles; the transition taken from the zoom each frame; must stay within 1e-6 px, 1e-7°, 1e-8 zoom and give the same tiles).

### GeoJSON sources

- `npm run geojson:golden`: tiler vs @maplibre/geojson-vt, every tile in range (js in full, wasm-gc by hash; must stay 0 differ).
- `npm run cluster:golden`: tiler's ClusterIndex vs geojson-vt's ClusterTileIndex: tiles, expansion zooms, children, leaves (must stay 0 differ).
- `npm run geojson:diffs`: tiler's updates vs @maplibre/geojson-vt 6.3.0's updateable index after seeded updateData diffs: every tile in range, ids, properties and order (js in full, wasm-gc by hash), clusters and clusterProperties too (must stay 0 differ).
- `npm run geojson:update-node`: setData vs updateData in the GeoJSON worker's wasm and in geojson-vt, a few properties or one geometry on GSI features, tiles recut.
- `npm run geojson:update`: updateData's diffs (npm/src/geojson-diff.ts) vs MapLibre 6.16's applySourceDiff / mergeSourceDiffs and the tiles its GeoJSONSource reloads (must stay all identical).
- `npm run geojson:node`: GeoJSON read + index + tiles vs geojson-vt in Node (also geojson:browser).

### UI and drawing

- `npm run ui:golden`: mbt-map/ui controllers vs MapLibre 6.16's controls: scale bars, zoom buttons, attributions, geolocation (fake Geolocation), legend colors.
- `npm run draw:golden`: mbt-map/draw vs terra-draw 1.37 on MapLibre: the same clicks in each mode, shapes compared.
- `npm run draw:many`: pointer moves while drawing over 2000 shapes with mbt-map/draw (frames until on screen).
- `npm run draw:setdata`: setData latency (frames until a moved vertex is on screen), mbt-map vs MapLibre.

### Data (`mbt-map/data`)

- `npm run data:golden`: mbt-map/data's readers (data.wasm) vs papaparse 5.7.0 / betterknown 1.2.0 / wkx 0.5.0 / shpjs 6.2.0 / topojson-client 3.1.0, SRIDs vs proj4 (1e-8°), on hand-written cases and GSI features (must stay 0 differ; `node data/pack-fixtures.mjs` regenerates the pack test's data files).
- `npm run xml:golden`: mbt-map/data's KML and GPX (xml.wasm) vs @tmcw/togeojson 7.1.3 on @xmldom/xmldom 0.9.12: hand-written, hostile and GSI-feature cases, KMZ through the shared zip reader, ids included (must stay 0 differ).
- `npm run fgb:golden`: mbt-map/data's FlatGeobuf (data.wasm, data_worker/js/fgb.mjs) vs flatgeobuf 4.6.1: GSI features, every column and geometry type, bboxes from bytes and over HTTP range requests, hostile files (must stay 0 differ).
- `npm run geotiff:golden`: mbt-map/data's readRaster (geotiff.wasm) vs geotiff 3.0.5's readRasters on the Mt Fuji DEM and a GSI map tile written as TIFFs of every layout read (strips, tiles, planar 2, LZW, Deflate, PackBits, predictors, sample formats, BigTIFF, big-endian, overviews), from bytes and over HTTP (must stay 0 differ).
- `npm run geotiff:tiles`: geotiff sources' tiles (rasterTile in Chromium) vs the pixels they hold: a GSI map COG identical to its PNG tiles, the Mt Fuji DEM as Terrarium within 1/256 m, EPSG:4326 and EPSG:6677 rasters vs an independent sampling (proj4js for 6677), and a map of the COG as the map of the PNGs.
- `npm run write:golden`: mbt-map/data's writers vs papaparse 5.7.0's unparse (WKT by betterknown 1.2.0), @placemarkio/tokml 0.4.0 and JSON.stringify: GSI features and hand-written cases, byte for byte (must stay 0 differ).

### Services (`mbt-map/services`)

- `npm run services:golden`: mbt-map/services vs OpenLayers 10.11.0 (WMS and WMTS capabilities, TileWMS / WMTS / TileArcGISRest URLs) and @camptocamp/ogc-client 2.0.2 (WFS capabilities, OGC API collections and tilesets) on live public services, plus a tile fetched from each source made (needs the services' hosts; must stay all ok).
- `npm run services:style`: ArcGIS VectorTileServer styles (arcgisVectorStyle) drawn by mbt-map and MapLibre 6.16 from the live service, pixel by pixel, symbol layers left out (each scene's limits must hold).
- `npm run esri:golden`: services.wasm's ArcGIS readers vs @terraformer/arcgis 2.2.2 (f=json, exactly) and arcgis-pbf-parser 0.0.4 (f=pbf: attributes and ids, geometry within 1e-7° of f=json) on live public layers, plus malformed input (needs the services' hosts; must stay all ok).
- `npm run reproject:golden`: reprojected sources (wmtsSource / wmsSource of other CRSs, reprojectTile in Chromium) vs proj4js 2.22.0: synthetic WMTS sets and GetMaps in EPSG:4326, 6677 and 32654 whose pixels hold their index (must stay all ok).

### Analysis, geometry, CRS and geodesics

- `npm run analysis:golden`: analysis wasm vs Turf.js 7.4.0 / flatbush 4.6.2 on all fixtures (must stay all identical).
- `npm run analysis:node`: analysis vs Turf.js + flatbush in Node (also analysis:browser).
- `npm run terrain:golden`: terrain analysis vs GDAL gdaldem (slope, aspect, hillshade) and gdallocationinfo (bilinear samples) on the Mt Fuji DEM fixtures, also read from a GDAL-written COG by readRaster and loadGrid; needs GDAL.
- `npm run relate:golden`: relate.wasm vs JSTS 2.12.1: DE-9IM matrices and predicates on hand-written, random grid and GSI features (must stay all identical).
- `npm run relate:node`: relate.wasm vs JSTS 2.12.1: predicates on GSI tile pairs and random sets, DE-9IM matrices (tables copied in per call, as the worker does).
- `npm run shapes:golden`: shapes.wasm vs Turf 7.4.0 (simplify, convex, nearestPointOnLine, lineSlice), concaveman 2.0.0 and d3-delaunay 6.0.6 on GSI features and random points (must stay all identical).
- `npm run shapes:node`: shapes.wasm vs Turf (simplify, convex, nearestPointOnLine, lineSlice), concaveman, d3-delaunay and delaunator on GSI features and random points.
- `npm run surface:golden`: surface.wasm vs Turf 7.4.0 (grids, interpolate, isolines, isobands, clustersDbscan, clustersKmeans) and d3-contour 4.0.3 (contourDensity) on random points and GSI features (must stay all identical).
- `npm run surface:node`: surface.wasm vs Turf (grids, IDW, isolines, isobands, DBSCAN, k-means) and d3-contour (density).
- `npm run viewshed:golden`: viewshed.wasm vs GDAL 3.13's gdal_viewshed on the Mt Fuji DEM (summit, slope, valley, edge; every mode, range and curvature), size, geotransform and every cell; needs GDAL (M2).
- `npm run viewshed:node`: viewshed.wasm vs gdal_viewshed processes (net of a 2 x 2 run) on the Mt Fuji DEM and a 4096 x 4096 mirror of it; needs GDAL (M2).
- `npm run route:golden`: route.wasm vs geojson-path-finder 2.1.0: shortest paths (every coordinate, weight) on jittered grids and GSI roads (must stay all identical).
- `npm run route:snap`: network({ snap }): noding vs a brute-force oracle, routes over GSI roads cut to their tiles vs uncut, T-junctions and tile-edge offsets (must stay all ok).
- `npm run route:node`: route.wasm vs geojson-path-finder: network build and paths on GSI roads and a jittered grid.
- `npm run classify:golden`: mbt-map/analysis's classBreaks / statistics (npm/src/classify.ts) vs simple-statistics 8.0.0 and geostats 2.1.0 on random numbers and GSI attributes (must stay all identical).
- `npm run classify:node`: classify.ts vs simple-statistics and geostats on random numbers and GSI attributes.
- `npm run clipper:golden`: clipper vs Clipper2 (clipper2-wasm 0.4.0): boolean ops, trees, offsets (must stay all identical).
- `npm run buffer:check`: geodesic buffers measured on WGS84 with GeographicLib.
- `npm run geometry:node`: dissolve / buffer / clip on GSI buildings vs Turf.js.
- `npm run proj:golden`: proj vs proj4js 2.22.0: every EPSG code it knows and PROJ strings for each projection, both ways (must stay within 1 mm / 1e-8°).
- `npm run proj:node`: proj.wasm vs proj4js speed, 1M points per CRS.
- `npm run geodesic:golden`: geodesic.wasm vs geographiclib-geodesic 2.2.0: inverse, direct, polygons, densified paths (must stay all identical).

### 3D (`mbt-map/3d`), lights and sight

- `npm run meshopt:golden`: meshopt's decoder vs meshoptimizer 1.3.0's MeshoptDecoder (js and wasm-gc builds; must stay 0 differ).
- `npm run draco:golden`: draco's decoder vs draco3d 1.5.7 on seeded meshes and point clouds (sequential and kd-tree, older kd-tree framings too), Draco's test files and PLATEAU's tiles, plus hostile copies (js and wasm-gc; must stay 0 differ).
- `npm run lepcc:golden`: lepcc's decoders vs Esri's LEPCC C++ (pinned commit, fetched and built with g++ by bench/lepcc/upstream.mjs) on blobs its encoder writes (xyz, rgb, intensity), plus hostile copies checked under AddressSanitizer (js and wasm-gc; must stay 0 differ).
- `npm run model:golden`: mbt-map/3d's loadModel in Chromium vs @loaders.gl/gltf 4.5.4 and gltf-transform 4.5.1's world matrices; hostile files refused.
- `npm run tiles:golden`: mbt-map/3d's 3D Tiles selection vs @loaders.gl/tiles 4.5.4's Tileset3D on PLATEAU (plateau-chiyoda fixture) and synthetic tilesets, and b3dm tables (must stay all the same).
- `npm run tiles:contents`: i3dm, pnts and cmpt contents (content.ts) vs @loaders.gl/3d-tiles 4.5.4 on synthetic tiles: instance matrices and batch ids, points (positions, colors, normals, batch ids; RGB565 and oct normals vs Cesium's decoding), inner tiles; hostile files refused (must stay all the same).
- `npm run tiles:properties`: 3D Tiles feature properties (properties.ts: batch tables, EXT_structural_metadata) vs @loaders.gl 4.5.4's Tile3DBatchTable and EXT_structural_metadata on PLATEAU and synthetic b3dm and written glbs (deviations from the spec checked against the values written; must stay all the same).
- `npm run i3s:golden`: mbt-map/3d's I3S node selection (npm/src/i3s/scene.ts: node pages, loaders.gl's getLodStatus / getProjectedRadius on the shared traversal) vs @loaders.gl/tiles 4.5.4's Tileset3D with @loaders.gl/i3s 4.5.4 on Esri's San Francisco sample (i3s-sf-pages fixture), same frame states (must stay all the same).
- `npm run i3s:contents`: I3S node contents (npm/src/i3s/content.ts, Draco by 3d.wasm) vs @loaders.gl/i3s 4.5.4 on Esri's sample layers (i3s-sf 3DObject, i3s-frankfurt IntegratedMesh fixtures) and the synthetic layer (`npm run i3s:synthetic`): positions (loaders.gl's ECEF in our east-north-up frame, rounded to f32), normals, uvs, colors, uv regions, indices, feature ids, attribute buffers; hostile copies refused (must stay 0 differ).
- `npm run i3s:slpk`: mbt-map/3d's SLPK reader (npm/src/i3s/slpk.ts) vs the files packed and @loaders.gl/i3s 4.5.4's parseSLPKArchive: SLPKs written from the synthetic layer and Esri's San Francisco sample (i3s-sf, i3s-sf-pages fixtures, when there), stored, deflated, zip64, with and without the hash table, from bytes, a Blob and a local server with and without ranges; requests and bytes counted, hostile copies refused (must stay 0 differ).
- `npm run las:golden`: mbt-map/3d's LAS reader (npm/src/model/las.ts) vs @loaders.gl/las 4.5.4 (its laz-rs and laz-perf parsers) on synthetic files of every version 1.0-1.4 and point format 0-10 and PDAL 2.8.0's samples (fetched, pinned by sha256), hostile copies refused; the 3D worker's `las` op vs proj4js 2.22.0 and math.gl's east-north-up frame (within 5 mm; must stay 0 differ).
- `npm run sun:golden`: sun.ts's sunPosition vs suncalc 2.1.1's getPosition, 1900-2100 and every kind of place (must stay all identical), and sunDirection vs CesiumJS 1.146.0's Simon1994PlanetaryPositions in east, north, up (1975-2050, its XYS data; within 0.05°).
- `npm run sight:golden`: Map.pickPosition / castRay / setViewshed / setClipping (3D picking, lines of sight, viewsheds and clipping through the shadow map) vs the analytic answers on extrusions and a glTF box of known size (bench/sight/page): segments' first hits within 5 cm, clipped or not, picks on a surface, ground pixels tinted seen or hidden (must stay 0 differ).
- `npm run clip:cesium`: Map.setClipping vs CesiumJS 1.146.0's ClippingPlaneCollection / ClippingPolygonCollection on PLATEAU (plateau-chiyoda): the same planes and polygons at two of bench/cesium's cameras, where buildings are drawn over black (both faces drawn), each clipping within 2% more pixels apart than unclipped.
- `npm run cesium`: mbt-map/3d's tilesLayer vs CesiumJS 1.146.0 on PLATEAU (plateau-chiyoda), same viewport and cameras: tiles selected, tile requests and bytes, time until settled, screenshots side by side (bench/results/cesium/, gitignored), frame CPU over an orbit, code gzip; requests leaving 127.0.0.1 fail it; `-- --gpu` on the M2 (frame numbers count only there).
