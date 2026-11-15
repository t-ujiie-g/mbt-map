# Architecture

How the repository is put together. `AGENTS.md` §4 has the short map and the invariants every change must keep; this file and its three companions are the per-subsystem reference. Goals, budgets and design principles are in [VISION.md](VISION.md), binary layouts and worker messages in [FORMATS.md](FORMATS.md) (code cites its section names instead of restating layouts), commands and goldens in [COMMANDS.md](COMMANDS.md), toolchain notes and measured backend facts in [TOOLCHAIN.md](TOOLCHAIN.md).

| File | Covers |
| --- | --- |
| ARCHITECTURE.md (this file) | Packages and dependency direction, entry points and modules, the MoonBit workspace, the wasm-gc boundary, the tile pipeline (`pbf`, `mvt`, `tess`), the npm facade, `<mbt-map>`, examples, the site, CI |
| [ARCHITECTURE-RENDERING.md](ARCHITECTURE-RENDERING.md) | Styles and expressions, paint, lines, images and patterns, heatmaps, queries, feature state, raster and media sources, custom layers, camera, globe, tracking and export, labels, terrain, fill-extrusion |
| [ARCHITECTURE-MODULES.md](ARCHITECTURE-MODULES.md) | Tables and GeoJSON, GeoJSON sources, `mbt-map/ui`, `mbt-map/search`, `mbt-map/draw`, `mbt-map/geodesic`, `mbt-map/services`, `mbt-map/data`, `mbt-map/analysis`, geometry operations, coordinate systems |
| [ARCHITECTURE-3D.md](ARCHITECTURE-3D.md) | `mbt-map/3d`: glTF models, 3D Tiles, I3S, point clouds; sun, lights and shadows; 3D picking, lines of sight, viewsheds and clipping |

## Packages and dependency direction

Never reverse a dependency:

```
core ← pbf ← mvt ← tess/style ← worker
core ← geom ← formats/tiler ← geojson_tiles ← geojson_worker
style/tiler ← cluster_props ← geojson_props_worker    (the GeoJSON module with expressions)
formats ← data_worker
pbf ← formats ← services_worker
core/geom ← xml ← kml ← xml_worker                    (kml also takes geom)
tiff ← geotiff_worker
geom ← analysis ← analysis_worker
geom/clipper ← overlay ← geometry_worker
geom ← relate ← relate_worker                         (which also takes @analysis.Index)
geom ← robust ← (hull, delaunay)
geom ← (simplify, hull, delaunay, lineops) ← shapes_worker
geom ← (clusters, grids, isolines) ← surface_worker
core ← density ← surface_worker
core ← viewshed ← viewshed_worker
geom ← route ← route_worker
proj ← proj_worker
core ← geodesic ← geodesic_worker
core ← globe ← render_webgl2 ← map ← bundle/main ← (npm, element) ← moonbit/mbtmap ← moonbit/mbtmap_rabbita
(meshopt, draco, lepcc) ← model_worker
wasmio ← (geojson_tiles, *_worker entries)            (wasm-gc only)
```

- Nothing under `map/` may depend on a UI framework.
- `map` must not import `worker` (it would pull mvt/tess into the main bundle); shared constants live in `core` or are mirrored with a pointer to the original.
- `core`, `pbf`, `mvt`, `tess`, `style` are pure MoonBit and must pass tests on every backend.
- `render_webgl2` and `map` are js-target only (`supported_targets = "js"`).
- On the js backend `FixedArray[Byte]`/`Bytes` are `Uint8Array`, but `FixedArray[Float]` is a plain JS `Array`, so GPU buffers need `extern "js"` typed-array wrappers; `Array[T]` is not a JS array, so exports hand JS a `FixedArray`.
- The decode loop is intentionally duplicated there (safe arrays vs raw addresses vs JS typed array); do not "deduplicate" it.

## Entry points and modules

- The data, analysis, services and 3D packages (VISION §3) ship as separate npm entry points with their own lazily loaded wasm and size budgets: `map` must never import them, and they exchange data with the display only through columnar (GeoArrow-compatible) buffers.
- Granularity (decided in Phase 6.5): one wasm module per entry, run in its own lazily started worker; split a feature group into its own module once its own code exceeds ~20KB gzip (each module duplicates ~6KB of core: trig, int formatting).
- Never link analysis into the display worker.
- A new entry or module needs a row in `npm/scripts/size.mjs`.

## MoonBit workspace and API modules

- The repository is a `moon.work` workspace. With several members, build outputs sit under the module name: `_build/<target>/<mode>/build/t-ujiie-g/mbtmap_engine/<package>/` (scripts use that path).
- `t-ujiie-g/mbtmap_engine` (the root): the engine, workers and bench packages; internal, not published.
- `t-ujiie-g/mbtmap` (`moonbit/mbtmap/`, js only, published to mooncakes): the MoonBit API for apps, a typed binding to the npm package's implementation, which it imports with `#module("mbt-map/...")` on `extern "js"`.
  - `#module("x")` imports are called as functions, so the npm package has `mbt-map/moonbit` (`npm/src/moonbit.ts`: `createMap`, the constructor as a function); the rest are `Map`'s methods, called through one generic `js_call`.
  - Its typed layer and source functions (`moonbit/mbtmap/style/*.g.mbt`) are generated from the pinned style-spec's `v8.json` (`npm run moonbit:style`, [COMMANDS.md](COMMANDS.md)).
- `t-ujiie-g/mbtmap_check` (`bench/moonbit/`): a MoonBit app on that API, built by `bench/npm/prepare.mjs` and run by the pack test's `moonbit` page.
- `t-ujiie-g/mbtmap_rabbita` (`moonbit/mbtmap_rabbita/`, js only, published): puts `<mbt-map>` in rabbita apps.
  - rabbita's public API cannot set arbitrary attributes or listen to custom events on an element, so `view` places the element by id, `setup` (a Cmd after render) sets its camera properties and style, `events` (a Sub) listens on `document` for the element's bubbling `mbt-map-*` events and filters by id, and `with_map` / `query_features` reach the typed `@mbtmap.Map`.
  - It imports `mbtMapElement` from `mbt-map/element`, which also defines the element.
- `examples/rabbita/` (module `t-ujiie-g/mbtmap_rabbita_example`): the rabbita demo (Chinese and Japanese cities on OpenFreeMap or GSI, label languages, 3D buildings), built and minified into `examples/rabbita/app.js` (gitignored) by `bench/npm/prepare.mjs`, which also fetches the pinned OpenFreeMap Liberty style for `?local=1` (`loadPublicStyle`), and checked by the pack test's `rabbita`.
- An executable package is `pkgtype(kind: "executable")`.

## The wasm-gc boundary

- `worker` ships as **wasm-gc** (decided in Phase 0).
- Tile bytes and output buffers cross the JS boundary through a linear-memory region managed by the worker, using inline-wasm load/store.
- Keep that wasm-gc-specific I/O inside wasm-gc-only packages: `wasmio` (input at `PAGE`, output after it, `MAX_INPUT_BYTES` for every entry, f64 input read as is by `input_f64s`; the entries wrap its functions in their own `#export_name`s, which imported packages do not export) serves every wasm-gc-only entry (and `geojson_props_worker` the host's `Number`, `String` and `Intl` for expressions, `wasmio/text.mbt`), and its JS side `wasmio/js/host.mjs` gives them `hostNumber` and `writeInput`.
- An all-targets package cannot import a wasm-gc-only one, so `worker` (and the bench entries) keep their own few load/store helpers.
- Do not pass data element-by-element through exported functions: per-element calls on GC arrays were 5–50× slower in Phase 0 benchmarks.

### Binary forms that cross workers

- Binary forms that cross workers (group properties, columnar tiles, `Table` bytes; docs/dev/FORMATS.md) are written and read with `@core.ByteWriter`/`ByteReader` (sticky errors) and share the `@core.PROP_*` value tags.
- Group properties are binary, not JSON, because stringify pulled float printing into the worker; `worker/js/worker.mjs` decodes them into prototype-less objects.
- Layers share buffers when their filters are written identically (`filter_id`), not by comparing `Expr`s.

### Elementary functions and text

- `@core.Trig` (sin … pow, cbrt, atanh) is the one seam for the host's `Math`.
- `@wasmio.host_trig` gives it to the wasm-gc-only entries and `worker/host_math.mbt` to the display worker (style's math and interpolation through `FeatureContext::trig`, DEM slopes, round line joins), which keeps core `@math` (about 5KB gzip) out of it and computes as MapLibre does.
- The clipper port keeps `@math`, since it must match the C++ library's libm.
- Small JS and Turf helpers that ports share (`EARTH_RADIUS`, `PI`, `turf_radians`, `haversine`, `turf_ring_area`, `js_round`, `js_min`/`js_max`, `stable_sort`) live in `core` (`core/jsmath.mbt`); priority queues stay per port, since their tie rules differ.
- UTF-8 is decoded by `@core.utf8_lossy` (one pass, same output as `@utf8.decode_lossy`, which links a strict and a lossy decoder: about 2.7KB gzip in each module).

### JSON without core `@json` / `strconv`

- JSON in wasm-gc entries never goes through core `@json`/`strconv` (about 27KB gzip in the display worker, 24KB in each GeoJSON reader): numbers past `@core.read_json_number`'s fast path go to the host's `Number()` (`wasmio/js/host.mjs`, imported as `host.number`).
- Both GeoJSON readers pass `read_geojson` `@wasmio.input_number`, which reads straight from linear memory (`geojson_tiles.load` takes it and the host's `Trig` from each entry, so the package also tests under moonrun).
- A second optional argument of `read_geojson` links its default `slow_number`, strconv, into the module (about 24KB).
- Firefox reads full-precision GeoJSON about 20% slower that way (PROGRESS.md).

## Tile pipeline

- `map` (main thread) asks a worker for a tile → `worker/js/worker.mjs` fetches it, places it in linear memory and calls the wasm-gc exports of `worker` (`prepare_input`, `init_style`, `process_tile`, `output_addr`) → `TileProcessor` decodes, tessellates and packs every fill/line layer of the style into one `PackedTile` blob (header of `LAYER_ENTRY_WORDS` u32s per layer, named `ENTRY_*`, Int16 positions, 16- or 32-bit indices, coordinates rescaled to `@core.TILE_EXTENT`, MapLibre's 8192; layers with the same geometry, like a road and its casing, share one buffer) → the glue slices it into ArrayBuffers and transfers them → `render_webgl2` uploads them as they are.
- In wasm-gc the blob is written in place in linear memory (`store_memory.mbt`); other targets use an array (`store_array.mbt`).
- The linear-memory files are wasm-gc only: in the wasm backend MoonBit's own heap lives in linear memory.
- The main thread never touches geometry (VISION §4-3).

### `pbf`

- `pbf` reads never raise: a `Reader` records its first error, jumps to the end so loops stop, and its `error()` is checked once at a boundary.
- Nested messages are read in place with `enter`/`exit`; `reset` re-points one reader instead of allocating another.

### `mvt`

- `mvt` decodes layer tables, feature headers and tags in `Tile::parse` (raising `MvtError` once per tile) and stores features column-wise; per-feature calls take an index (`layer.decode_geometry(i, out)`, `layer.property(i, key)`) and don't raise.
- Geometry is decoded lazily into a reusable `Geometry` buffer.

### `tess`

- `tess` triangulates fills with a port of earcut 3.2.4 whose output matches the JS library exactly, after grouping rings like MapLibre's `classifyRings`, and extrudes lines into quads plus join/cap geometry (vertex layout in `LINE_VERTEX_STRIDE`).
- Tessellators and buffers are reusable objects so steady-state use does not allocate.

## The npm facade

- `npm/`, `element/`, `examples/` are not MoonBit packages (TS/HTML side).
- `npm/src/index.ts` is a MapLibre-shaped TS facade (`Map`, `on`/`once`, `jumpTo`, …) over the `bundle/main` exports; esbuild aliases `mbt-map-engine` to that build and `npm/src/engine.d.ts` types it, so keep both in sync with `bundle/main/main.mbt` (`map_frame_count` and `map_placed_labels` are test hooks).
- Pure parts of the facade live in their own modules for `npm test` (`engine-style.ts`, `feature-state.ts`, `query.ts`, `camera.ts` with the zoom and pitch limits that `element/parse.ts` mirrors).
- The build rewrites `dist/*.d.ts` relative imports to `.js` so `moduleResolution: nodenext` resolves them, keeps only the declarations the entries' `types` reach (`npm/scripts/declarations.mjs`; internal modules' are deleted), and `package.json` exports every file reached by URL (workers, wasm, worker parts).
- Sibling chunks by dynamic import need no entry.
- `bench/pages/basic`, `bench/pages/terrain` and `bench/render/page.mjs` call those exports directly (`create_map` and others): change them with the signatures (the pack test starts both examples).
- The facade resolves tile URLs against the style URL and loads `worker.js`/`mbt-map.wasm` next to itself via `new URL(..., import.meta.url)`.
- Bundlers (docs/getting-started.md "Bundlers", `npm run bundlers`): every file a worker loads later is named on the main thread by a literal `new URL("./file", import.meta.url)`, which bundlers emit as an asset, and sent in the worker's init message (wasm URLs, and `parts`: `workerParts` in `npm/src/urls.ts`; the display worker's go through `create_map` to `post_init`). A worker imports a part from the URL given, else from beside itself (the page's own `workerUrl`, the bench pages). Never write `new URL("./", import.meta.url)` (Parcel fails on it, Vite emits the module again for it).
- `workerScriptUrl` (`npm/src/urls.ts`) tells the page's `workerUrl` (on the page's origin or in the library's folder, AGENTS.md §8.3) from the library's own default, which is where a bundler put it: http(s) on any origin (through the importing blob off the page's), or a `data:` URL (Vite inlines small files), started from a same-origin blob of the same text.

## `<mbt-map>` (`mbt-map/element`)

- `element/element.ts` is `<mbt-map>` (entry `mbt-map/element`, ~1.6KB on top of the main entry, which it imports as `./index.js` rather than bundling).
- The map lives in an open shadow root; attributes are parsed strictly (invalid values fire `mbt-map-error` and are kept out); `center`/`zoom` properties also take the attribute strings because React 19 sets props as properties when the element has one.
- Style the shadow box inline: a `div` rule in the shadow stylesheet also hit the facade's attribution overlay.

## Examples

- `examples/` is one showcase app written three ways (`html/` with `Map`, `element/` with `<mbt-map>`, `react/`), sharing `examples/shared/` (style, places, analysis, the look in `app.css`; `shell.js` and `app.js` are the plain-DOM page, which React writes as the same markup in JSX, so the pack test finds the same ids in all three; tabs hide their tools, so a check opens one with `openTab` first).
- It reads GSI's live tiles (`?local=1`: the bench fixtures, as the pack test does) and must stay deployable as static files (relative URLs).
- Each phase adds its features to all three.
- `examples/plateau/` is a page of its own (the user's choice for 3D Tiles): PLATEAU's Chiyoda buildings streamed from PLATEAU's CDN (the fixture with `?local=1`, checked by the pack test's `plateau`), attributes by `queryFeature`.
- Dev pages that call the engine directly live in `bench/pages/`, test-only pages in `bench/npm/pages/`.

### Samples

- `examples/samples/` are small samples, one thing each, written to be read (no test hooks): a folder per sample with `index.html` (the shared import map to `../node_modules/mbt-map`, `../sample.css`, `<title>` and `<meta name="description">`) and `main.js`, listed with their gallery group in `index.json`.
- They read live services (GSI, OpenFreeMap, PLATEAU, GIBS, Esri).
- The pack test's `samples` opens each and needs a canvas and no page error.

### Key handlers and IME

- Key handlers in examples (and anything a page wires to a controller) leave keys of an IME composition alone: `isComposing`, or `keyCode` 229 (Safari's confirming Enter after `compositionend`); a Japanese user's confirming Enter must not choose a search result (`examples/shared/search.js` `onSearchKey`).

## The site

- `site/index.html` is the hand-written home page, with PLATEAU's 3D buildings turning slowly (`site/hero.js`).
- `bench/site/build.mjs`:
  - renders `docs/*.md` (not `docs/dev/`) with marked, highlights code blocks at build time (`bench/site/highlight.mjs`: highlight.js, MoonBit by `moonbit-highlight.mjs`), anchors as GitHub's and links rewritten by `bench/site/links.mjs` (docs pages and the published examples stay on the site, other repository files go to GitHub);
  - copies `npm/dist`'s modules, workers and wasm once to `lib/` and the example apps (`SITE_EXAMPLES`: html, react, plateau, rabbita) without their sources, their import maps pointed at `lib/` and `data-variants` on their `<html>` naming the showcase variants published (`variants` in `examples/shared/shell.js` links only those);
  - makes the examples gallery from `examples/samples/index.json` (each sample's `<title>` and description, a page per sample with it running in an iframe beside its `main.js` and `index.html` as one would copy them: the package from jsDelivr, the shared CSS and the sample's binary files by their site URLs, its other text files shown as further code blocks);
  - fails when an internal link of the built pages leads nowhere (`bench/site/dead-links.mjs`: every `href` and `src` outside shown code, fragments against the target's ids, the showcase's variant links).
- Every page has the light/dark switch (`site/theme.js`, remembered in localStorage); the same script folds the documentation's navigation (a `<details>`) at phone width.
- `bench/lib/site.test.mjs` checks the docs' relative links and anchors and `deadLinks`; CI builds the site in the pack job; `.github/workflows/pages.yml` publishes it on a `v*` tag or by hand (the `github-pages` environment allows `main` and `v*` tags).

## CI

- CI (`.github/workflows/ci.yml`) runs side by side a `moon` job (check, tests on the shipped backends wasm-gc and js, fmt, info, npm build, test and size) four pack-test jobs in Chromium (the small pages, then each showcase; their names are required checks) and four more in Firefox and WebKit (`pack-browsers`: the small pages, then the three showcases).
- wasm and native are tested by the local validation loop only.
- Each job prepares its runner with `scripts/setup.sh` (the pinned MoonBit toolchain verified by sha256, npm dependencies), the same script Claude Code on the web runs; bumping `moon` means updating `MOONBIT_VERSION` and both hashes in `scripts/toolchain.env`.
