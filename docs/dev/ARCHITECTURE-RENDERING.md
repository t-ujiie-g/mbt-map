# Architecture: styles and rendering

Part of the architecture reference ([index](ARCHITECTURE.md)). What the engine draws and how: `style`, `worker`, `map`, `render_webgl2`, `core`'s camera, `globe`, `label`, `raster`, and the facade parts that feed them.

## Styles and expressions

### Parsing and compiling

- `style` compiles filters and paint into `Expr` (the subset in `style/expr.mbt`, nesting capped by `MAX_EXPR_DEPTH`) and reports anything else as `Unsupported` with its JSON path.
- Unless `strict`, `Style::from_json` leaves such a property out and parses the layer again (a layer or source that still cannot be drawn is dropped) and lists each in `warnings`.
- Only the main thread parses and compiles styles: display workers get the result as bytes (`Style::to_compiled` / `from_compiled`, `style/compiled_writer.mbt` and `compiled_reader.mbt` with the `EXPR_*` tags, docs/dev/FORMATS.md "Compiled style"; query filters through `write_expr` / `read_expr`), which keeps the parser and compiler out of the worker wasm (about 22KB gzip).
- The main thread alone adds the properties parsed but not drawn yet (`ignored_properties`, `Style::report_ignored`), which the facade fires as `warning` events.
- `npm run style:compat` lists what public styles (`bench/style/public-styles.mjs`) lose that way; `Expr::eval` is generic over a `FeatureContext`.
- Compiling for a type annotates as MapLibre's parser does (an assertion, or `to-color` for colors, around an expression of type `value`), `let`/`var` are inlined (`MAX_EXPR_NODES` caps the expanded size), and MapLibre's evaluation errors are `Value::Failed`, which a property reads as its default.

### Evaluation context and special expressions

- A `FeatureContext` brings the host's `Math` (`trig`), JavaScript's `String(number)` / `Number(string)` (`number_text`, `text_number`) and `Intl` (`number_format`, `collate`, `resolved_locale` for `number-format` and collators; `style/intl_js.mbt` calls it on the js backend, `@style.Intl` carries it into the worker): the display worker passes them in through `host.*` imports (`wasmio/js/host.mjs` `hostText`, `intl`), which keeps float printing and `strconv` out of it.
- `global-state` is compiled to the value the style's `state` gives (`with_global_state`): the facade keeps the global state (`setGlobalStateProperty`) and hands the engine the style with those values as defaults, so layers reading a changed key differ by `same_tiles` and are drawn and loaded again.
- `format` evaluates to `Value::Formatted`; the worker packs its sections with their `font-scale` and `vertical-align` and `worker/js/text.mjs` shapes them as MapLibre's `shapeLines` (sections' `text-font` and `text-color` are drawn too, see "Labels").
- `is-supported-script` is always true, as in MapLibre 6.16 (no host there sets `isSupportedScript`).
- `within` and `distance` (ports of style-spec's, cheap-ruler and tinyqueue included) read the feature's geometry in its canonical tile through `FeatureContext::within` / `distance`: the display worker's `FeatureRef` loads it as MapLibre's `loadGeometry` (`@style.GEOMETRY_EXTENT`, tile x and y from the tile message) for filters, layout, per-vertex paint and queries.
- Elsewhere `within` and `distance` give false and NaN as MapLibre without a canonical tile, so paint drawn by groups on the main thread (symbols, extrusion color, layers reading feature state) refuses them as `Unsupported`.

### Legacy filters and functions

- Legacy filters and property functions never reach the engine: the facade converts them with the lazily loaded `legacy.js` (`npm/src/legacy.ts`, a port of style-spec's `convertFilter` / `convertFunction`; `isLegacyFilter` / `hasLegacy` in `npm/src/style.ts` decide whether to load it).

## Runtime style changes

- The facade edits a copy of the style document (`npm/src/style.ts`, import-free) and hands the whole of it to `Map::set_style` (`map/style.mbt`), which keeps a source's tiles when `Source::same` holds and each of its layers in the new style has a `StyleLayer::same_tiles` twin (by id) in the old one, renumbers their meshes by layer id, and otherwise marks tiles `Stale` (drawn until reloaded).
- Workers get `{type: "style"}`.
- GeoJSON data is compared by identity (`keepGeoJSONData` restores it for equal data), and changed sources are reloaded with `reload_source`.
- Layers with `visibility: none` are dropped when parsing, so hiding one is a removal.

## Data-driven paint

- Data-driven paint of fills, lines and circles goes per vertex (decided in Phase 15): `@style.StyleLayer::vertex_paint` lists the data-driven properties with the outputs at each stop of their top-level zoom curve (so a z14 tile drawn at z18 is exact, as MapLibre is only after re-parsing overscaled tiles).
- The worker evaluates them per feature and repeats the words over its vertices (`Store::repeat`, a doubling `memory.copy`), each layer with its own buffer also over shared geometry.
- The renderer points the slot attributes (`a_color_lo`/`hi`, `a_opacity`, `a_extent`, …) at the stop below the current zoom and mixes with `u_t`, and passes constant paint through the same attributes with `vertexAttrib*`, so there are no shader variants.
- Lines put `line-gap-width` and `line-offset` in the circles' stroke opacity and width slots (`SLOT_GAP_WIDTH`, `SLOT_OFFSET`) and are drawn with MapLibre's line shader math (outset, inset, blur).
- An offset layer's vertices carry MapLibre's `a_offset_normal` (`LineBuffers.offsets`, packed per entry, `a_offset` at location 2), so it shares buffers only with offset layers.
- `*-translate` (a constant or zoom curve over `[x, y]`, `@style.translate_at`) moves a layer's tile matrix (`Map::translated`, MapLibre's `translatePosition`) and its queries.
- `*-sort-key` orders a layer's features in the worker (`feature_order`, `@core.stable_order`, ties in tile order) and such layers never share buffers; circles with one are drawn across tiles in key order from the runs each entry packs (`Map::draw_circles_by_key`).
- `same_tiles` compares the baked paint.
- Layers reading feature state, symbols and extrusions still split features into groups by the values their paint reads (`feature_inputs`, at most `MAX_GROUPS` per layer and tile), an entry per group carrying those values; the main thread evaluates paint per group at the current zoom.
- The main thread evaluates through one context type (`JsProps`), so `Expr::eval` is compiled into the bundle once.

## Fill outlines

- Fill outlines (`fill-antialias`, default true; `fill-outline-color`, default the fill color): tess emits each ring's edges as a line list (an open ring gets its closing edge), packed after the fill's triangle indices.
- The renderer draws them with `gl.LINES` and MapLibre's fill-outline shader (alpha from the pixel's distance to the line), after the fill, with the outline color in the stroke-color slot.
- `npm run style:golden` matches MapLibre exactly on fills.

## Dashed lines

- Dashed lines (`line-dasharray`, constant or by zoom, or by feature): tess records each vertex's distance along its line (`LineBuffers.distances`, in `TILE_EXTENT` units, even as MapLibre's `linesofar`; sharp corners split and restarted past `MAX_LINE_DISTANCE` as its line bucket does) only for dashed layers, which share buffers only with dashed layers.
- The worker packs them as u16 per vertex.
- The main thread keeps MapLibre's `LineAtlas` (`render_webgl2/line_atlas.mbt`, byte-identical) and draws with its line_sdf shader (`lineDash` program, `a_dist` at location 13): pattern and `line-floorwidth` at the integer zoom, edges smoothed over the shorter of that pattern and the one a zoom away, as MapLibre at rest (no cross-fade animation).
- A data-driven dasharray (`StyleLayer::feature_dashes`; not with feature state or in layers drawn by groups) is evaluated per feature at the tile's zoom and either side and packed as patterns plus four u16s per vertex (docs/dev/FORMATS.md "Packed tile"; such layers never share buffers).
- The main thread puts the patterns in the atlas and uploads per vertex row, height, width (truncated, as MapLibre's Uint16 `a_dasharray_*`) and both edge lengths (`lineDashFeature`, `a_dash` at location 15).

## Line gradients

- Line gradients (`line-gradient` over `["line-progress"]`, which no other property may read; a GeoJSON source's `lineMetrics`): the tiler ports geojson-vt's line metrics (each line its own feature, slices keeping where they lie along it; `CLIP_START`/`CLIP_END` properties; `npm run geojson:golden` compares them).
- Gradient layers record each vertex's share of its line (`LineBuffers.progress`, sharp corners split) and a row per line with its clip, packed per entry.
- The main thread builds MapLibre's `renderColorRamp` per mesh (`color_ramp`, `ramp_width`, evaluated through `JsProps.progress` so `Expr::eval` stays one instantiation: another `FeatureContext` cost 24KB gzip) and draws with its line_gradient shader (`lineGradient`, `a_progress` at location 14).

## Style images and patterns

- The facade keeps the images' names and hands their straight RGBA pixels to the engine (`Map::add_image`; `addImage`, `updateImage`, `removeImage`, `loadImage`, `styleimagemissing` as MapLibre's).
- A style's `sprite` (one URL or `{id, url}` list, @2x on a 2x screen) is read by the lazily loaded `sprite.js` (`npm/src/images.ts` is the import-free part).
- The main thread packs images into one `PatternAtlas` as patterns are first drawn (shelves, 1 px wrapped padding as MapLibre's `ImageAtlas`; cleared when images change) and draws `fill-pattern` and `background-pattern` with MapLibre's fill_pattern, fill_outline_pattern and background_pattern shaders, positioned by the tile's world pixel at the integer zoom (`Placement.pattern`).
- The pattern is taken at the integer zoom (no cross-fade).
- A pattern picked by feature draws the layer by groups (`StyleLayer::paints_by_group`).
- Fill outlines go after all of a tile's fills, as MapLibre draws them.
- Layers are drawn in the style's order, extrusions among them (MapLibre's translucent pass: depth is tested only by 3D layers). A background of one color is the frame's clear color only when it is the lowest layer shown (`Map::base_background`); any other is drawn where it sits over the tiles covering the view (`Map::draw_background`, MapLibre's `drawBackground`), so a translucent one tints the fills below it, is hidden by the extrusions above and covers those below; on terrain it goes into the terrain's textures in order (`npm run style:golden`'s `background-*-extrusions` scenes).
- Icons have their own atlas (`Renderer::icon`: 1 px transparent padding, MapLibre's `ImageAtlas` for icons), whose places never move: an image replaced at the same size is copied over its pixels, one of another size gets a new place.
- The workers lay icons out, so they are told each image's size (`Map::send_images`, once per frame with changes); tiles whose icons used a changed image are loaded again, and while the facade loads a sprite (`Map::hold_images`) the workers hold tiles of styles with icons, as MapLibre's tiles wait for the sprite.
- An image a tile lacks fires `styleimagemissing` once (`Map::report_missing`).
- `line-pattern` (MapLibre's line_pattern: as tall as the floor width, along the line distances, `StyleLayer::line_distances`) and `fill-extrusion-pattern` (fill_extrusion_pattern: walls by their distance along the ring, packed in the extrusion vertex, and height) are drawn too.

## Heatmaps

- Heatmaps (`heatmap` layers; `["heatmap-density"]` only in `heatmap-color`, `Invalid` elsewhere): the worker packs them as circles (`KIND_CIRCLE`, its own buffers), weight and radius per vertex in the opacity and size slots (`SLOT_WEIGHT`), or by group and state range when they read feature state, as circles.
- The main thread ports MapLibre's two passes (`map/heatmap.mbt`, `render_webgl2/heatmap.mbt`): kernels added (`ONE, ONE`) into an RGBA16F texture a quarter of the viewport (RGBA8 without `EXT_color_buffer_float`), unclipped, each tile once (an ancestor standing in draws instead of its children), then colored over the viewport through a 256-px `color_ramp` evaluated via `JsProps.density`.
- On terrain each terrain tile gets its own kernels at 512 px, as MapLibre's per-tile framebuffers (cut at tile edges).
- Ramps are uploaded premultiplied in JS as MapLibre's `premultiplyAlpha` rounds.
- Queries hit points within the radius on the map.

## Feature queries

- The display worker keeps each vector or GeoJSON tile's bytes it sent (until `{type: "drop"}`), and `map/query.mbt` sends each drawn tile a query (docs/dev/FORMATS.md "Query") that `worker/query.mbt` answers as MapLibre's `FeatureIndex` would (`@core.polygon_hits_*`, ports of its intersection tests; the tile's query padding; extrusions projected and hit in 3D).
- Labels are found on the main thread from the boxes of the last placement and named to the worker by feature index.
- The facade orders the hits (`npm/src/query.ts`, MapLibre's merge and 3D sort), so queries return Promises; `querySourceFeatures` gives each feature the source tile it came from as `tile: {z, x, y}` (MapLibre's canonical tile), which the showcase's route uses to cut each road to its own tile.
- Buckets take geometry types as MapLibre's do (fills and extrusions fill lines too; circles go on every vertex).

## Feature state

- Paint may read `["feature-state", key]` (`Expr::FeatureState`; `FeatureContext::state`, None in the worker).
- For layers whose paint reads it (`StyleLayer::reads_state`), the worker records each feature's index range per packed entry with its id (`feature_ranges`; the source's `promoteId` or the tile's / GeoJSON id), which the glue keeps; such layers never alias another's buffers.
- The facade holds the states and hands each feature's to `Map::set_feature_state`, which asks the workers where the stated ids lie (`{type: "ranges"}`) and draws those ranges with their state (`draw_by_state`, `Renderer::set_range`); `idle` waits for the answers.

## Raster tiles and where tiles come from

- A `raster` source's tiles are decoded by a display worker into ImageBitmaps (`KIND_RASTER`, layer -1 like DEM tiles) and drawn with MapLibre's raster shader without its fade, on the pixel grid at rest (`Transform::tile_matrix(aligned=true)`, MapLibre's `alignedProjMatrix`; `npm run raster:golden` must stay pixel-identical).
- Sources given by `url` are completed by the facade (`npm/src/tilejson.ts`, documents cached, sources still loading left out of the engine's style).
- `pmtiles://` archives get their header read by the lazily loaded `pmtiles.js` and their tiles by the worker (`worker/js/pmtiles.mjs`, a port of pmtiles' reader with capped sizes; `npm run pmtiles:golden` against pmtiles 4.5.0).
- `bounds` and `scheme: "tms"` are applied by the engine, and tile templates take MapLibre's placeholders (`{bbox-epsg-3857}` for WMS and ArcGIS `export`, `{quadkey}`, `{ratio}`, `{prefix}`; `npm run raster:golden` compares the URLs requested); `transformRequest` reaches tile fetches as the message's `init`.

## Image, video and canvas sources

- Image, video and canvas sources (MapLibre's `ImageSource`, `VideoSource`, `CanvasSource`): the facade loads `media.js` (`npm/src/media.ts`, import-free) with the first style that has one.
- It fetches images (no credentials, http(s) against the style URL, `transformRequest` as `"Image"`), makes muted looping `<video>`s, finds canvases by `getElementById` (or takes the element `addSource` was given), and computes where the picture goes as MapLibre does (`quadOf`: the center tile, corners rounded in 8192 units, `calculateImageWarp`).
- The engine (`map/media.mbt`, style kind `Image`) uploads the picture without mipmaps, premultiplied, and draws it with the raster shader, whose corners (`u_top`, `u_bottom`) and warp (`u_warp`) MapLibre's tiles take too, over its tile unclipped (16 x 16 quads when MapLibre subdivides).
- A playing video or animating canvas is uploaded every frame and keeps frames coming; the map still goes idle (once, when its tiles have settled).
- `npm run style:golden`'s `images` scenes must stay pixel-identical.

## Custom layers

- Custom layers (MapLibre's `CustomLayerInterface`): `addLayer` puts a placeholder `{id, type: "custom"}` in the style document (so ordering, `moveLayer`, `beforeId` and removal are ordinary edits; `getStyle` leaves it out, a new style drops it as MapLibre's `setStyle` does) and hands the layer to `custom.js` (`npm/src/custom.ts`, import-free, loaded with the first one; `onAdd` runs then).
- The engine (style kind `Custom`, `map/custom.mbt`) calls one JS renderer where the layer sits, `prerender` before the frame is cleared, with `Map::custom_numbers` (`Transform::world_matrix` is MapLibre's `modelViewProjectionMatrix`, `npm run camera:golden` compares it).
- `custom.ts` builds MapLibre's options (`defaultProjectionData.mainMatrix` for Mercator 0 to 1, `getProjectionData`, the Mercator shader prelude), saves the GL state, sets MapLibre's custom-layer defaults and depth mode ("3d" tested, "2d" off) and restores the state after the layer's code.
- Custom layers are drawn over terrain, never into its textures.

## Camera and tile covering

- Camera math and tile covering live in `core` (`Transform`), pure and tested on all targets; `map` only wires DOM events, workers and the frame loop (renders on demand, falls back to a loaded ancestor or loaded children).
- The camera has bearing and pitch (≤ `MAX_PITCH` 85°, as MapLibre).
- Above about 70° the horizon comes on screen: the ground ends at MapLibre's horizon line (`Transform::horizon`, 85% of the way to the true horizon), screen points above it map to the ground at the line, the far plane sits at its depth, and the style's `sky` is drawn above it (MapLibre's sky shader; no `sky`, no sky or fog, as in MapLibre).
- `Transform` keeps a MapLibre-style view-projection (`Mat4`, column-major) over world pixels relative to the center, so precision holds at every zoom.
- `covering_tiles(min_z, max_z)` walks a quadtree over the view's ground footprint and drops a zoom level per doubling of distance beyond `LOD_DISTANCE` camera distances, and leaves ground that wants more than `MIN_ZOOM_SLACK` levels below `min_z` empty; leaves never overlap. What ground wants is measured from the camera's own tile zoom (`tile_size`), never deeper than it: a source starting far below the view (terrain on a DEM of zoom 14 alone, seen at zoom 2) gets no tiles instead of the 4^14 of the whole world, which froze the page.

### World copies

- With `Limits.world_copies` (MapLibre's `renderWorldCopies`, default true) it walks every world copy the view reaches (`Transform::wraps`, up to `MAX_WORLD_COPIES` either side) and returns `@core.UnwrappedTile`s (canonical `TileId` plus `wrap`, MapLibre's `UnwrappedTileID`; `heights` are looked up for the canonical tile): tiles load and cache by `TileId` only, each `Draw` carries its `wrap` (and `copy` when another copy draws the same meshes, which terrain textures skip), `tile_matrix(wrap~)` moves it whole worlds, a tile's labels are placed and drawn in the copy nearest the center (`LabelSet.wrap`), and queries ask each drawn copy, the facade keeping each feature once per tile.
- Without copies the camera keeps the view within ±180° as MapLibre's `defaultConstrain`.

### Tile matrices, clipping and circles

- Shaders take a per-tile `mat4`; lines extrude in tile units (they thin with distance) and scale their antialiasing by depth; an ancestor standing in for a missing tile is clipped in the fragment shader (`u_clip`, tile units), since scissor rectangles fail once the map turns.
- Circles (`KIND_CIRCLE`) reuse the line vertex layout, one quad per point inside the tile (`@tess.add_points`); the shader expands it as MapLibre's circle shader does: around the projected center on screen, or on the map (`circle-pitch-alignment`), scaled by depth or kept on screen (`circle-pitch-scale`).

## Camera moves

- Camera moves are MapLibre's: `core` ports its default constrain (zoom raised until the latitude limit, ±85.051129°, and `maxBounds` fill the view; the zoom set before the center, a move's end point constrained once as `applyConstrain` does), `easeTo`, `flyTo` (van Wijk and Nuij), `cameraForBounds`, `setLocationAtPoint`, `project` / `unproject` / `getBounds` and the CSS `ease` curve (`Bezier`).
- `npm run camera:golden` drives MapLibre's own `Camera` in Node with frozen time (`setNow`) and must stay within 1e-6 px, 1e-7°, 1e-8 zoom.
- `map` runs animations in the frame loop (`step_animation`), keeps `move_start` / `move_end` around gestures, inertia (MapLibre's buffer and decelerations), wheel zoom (ended 200 ms after the last wheel) and animations, and has MapLibre's handlers (`Handler`; 3 px click tolerance, keyboard, double click, shift-drag box zoom, two-finger pitch).
- Touch and the page: the canvas's CSS `touch-action` follows the enabled handlers as MapLibre's canvas container (`touch_action` in `map/camera.mbt`, set by `attach_input` and `Map::set_handler`: `none` with `dragPan` and a two-finger handler, `pinch-zoom` with `dragPan` alone, `pan-x pan-y` with `touchZoomRotate` or `touchPitch` alone, else `auto`). Listeners are passive except `wheel`, `dblclick`, `keydown` and `touchmove`, which cancels the gestures the map takes (`Map::takes_touches`) for browsers that ignore `touch-action`. The pack test's `touch` check drives real touches through CDP on a scrolling page.
- `idle` is MapLibre's (`Map::render`'s end): fired after a frame whose tiles are settled, with no feature-state ranges awaited, no movement (`moving`) and, once fired since the last change (`idle_fired`, which `toBlob` reads through `is_idle`), no further frame requested. So one-frame changes (`trigger_repaint`, `set_viewshed`, `set_clipping`) end in an `idle`, a continuous repaint gets one when it settles and one when it stops, and a gesture's end asks for a frame (`on_pointer_up`, the wheel's timer) so that its `idle` comes. The facade gives the canvas `role="region"` and an `aria-label` (the container's, else `Map`), as MapLibre.
- The facade derives `zoom` / `rotate` / `pitch` events from successive cameras and queues camera calls made before the engine starts.
- Map padding (`setPadding`) is not supported yet.

## Globe

### Camera

- Globe (`globe`, pure, all targets; style `projection`, the facade's `setProjection`): ports MapLibre 6.16's `GlobeTransform` (its vertical perspective and the camera state it shares with mercator, `TransformHelper`), the globe and mercator camera helpers and the handler manager's gesture frames onto one mutable `Globe` that constrains on every change as MapLibre's transform does.
- Drawn as a globe while `transition` is above 0 (style `projection` `"globe"`: 1 up to zoom 11, 0 from 12, `Projection::transition`), and at 0 every query goes to `@core.Transform::exact` of the same state.
- Animations hold their transform and must be stepped with growing fractions (`GlobeEase::at`), which take the transition from the new zoom as MapLibre's next frame does, so a flight crosses between mercator and globe as there.
- `npm run globe:golden` must stay within the camera golden's tolerances.
- `Globe::covering_tiles` ports MapLibre's `coveringTiles` with the globe's bounding volumes (its frustum from the inverse rounded to Float32, as `mat4.clone` does).
- `map` keeps the `Globe` beside a mercator `@core.Transform::exact` of the same state, which the rest of the map reads; camera calls, animations and gestures (`globe_gesture`) go through the globe, the transition is taken each frame.

### Drawing layers on the globe

- While drawn as a globe, layers go onto it through the shaders' `project()` prelude (MapLibre's `projectTile`, the `GlobeTile` of each `Placement`): raster-like layers and backgrounds as tile meshes of `@globe.tile_mesh` reaching the poles.
- Fills, lines, circles and heatmaps from tiles the display worker cuts finer when the tile message says `globe` (`@tess.Subdivider`, a port of MapLibre's `subdivision.ts`: geometry first taken to `TILE_EXTENT` as `loadGeometry` rounds it, fills by `subdividePolygon` with their outlines and pole caps, lines by `subdivideVertexLine`, heatmap and map-pitched circle quads as 3 x 3; `npm run subdivision:golden` must stay 0 differ), lines widened by `lineThickness` and narrowed by MapLibre's pixel scale with its gamma scale, circles and kernels turned on the sphere (`turnOnGlobe`).
- A style whose projection changes loads its vector tiles again.
- Space stays clear (the context has alpha) and the atmosphere comes over it when the style has a `sky`.
- Extrusions are cut as their fills (walls from the subdivided rings) and raised along the sphere's normal (`project3d`), lit by MapLibre's globe light direction, after the globe's surface is written into depth (`draw_globe_depth`); `*-translate` moves the sphere point (`GlobeTile.translate`).

### Queries, terrain, custom layers, export and labels

- Queries project through the sphere in the worker (the query message carries the tile's globe matrix; extrusions are not hit on the globe, as MapLibre).
- Terrain grids go onto the globe through `project3d` with their heights in meters and no fog (as MapLibre); the center does not stand on the terrain there yet.
- Custom layers get MapLibre's globe options (`shaderData` with its globe prelude, the globe's matrices and `defaultProjectionData`); export draws the globe through the window and keeps the space around it clear (straight alpha).
- Labels are placed through the pure globe projection while it is drawn, as MapLibre (`globe/symbols.mbt`: `projectTileCoordinates` with the horizon test, the pitched-text and circle-radius corrections, `getWrap`), and drawn through the same prelude; `npm run labels:golden`'s globe scenes must stay identical.
- Symbol `*-translate` is not on the globe.
- `npm run raster:golden`'s and `npm run style:golden`'s globe scenes must stay pixel-identical, the globe URLs the same.

## Screen tracking and image export

- `Map::locate` projects a place onto the terrain and asks `Transform::occluded` whether the terrain hides it (ports of MapLibre's `isLocationOccluded` and its CPU ray march over the terrain, `core/occlusion.mbt`, through a `@core.Terrain` of the loaded DEM tiles: heights read across tile borders as MapLibre backfills them, flat 0 m where no DEM has loaded).
- `unproject` with terrain marches the same ray.
- The facade's `track` locates every tracked place in one `map_locate` call after each frame (`Render` listeners).
- `toBlob` waits for `idle`, then `Map::render_region` draws the current tiles into an offscreen framebuffer (`Renderer::begin_offscreen`) part by part: a `Window` matrix maps the whole image's clip space to the part's (the sky's horizon is moved by the part's offset), and the facade joins the parts in a 2D canvas.

## Labels

### Packing, glyphs and placement

- Labels (symbol layers, on points and along lines): the worker wasm packs each point's anchor (or a line feature's lines), `text-size` and `text-field` parts, and its `text-font`, `text-transform`, `text-letter-spacing` and `text-rotate` (`worker/labels.mbt`).
- The worker glue draws SDF glyphs with TinySDF on an `OffscreenCanvas` (`worker/js/symbols.mjs`, each glyph sent once per worker in the tile message's `glyphs`) and lays text out in CSS pixels as MapLibre shapes it (`worker/js/text.mjs`, its line breaking included; import-free and unit-tested by `npm test`).
- The main thread packs glyphs into one atlas (`label.Atlas`) and turns each quad's glyph index into atlas pixels before upload (the one place it touches vertices; into a buffer of their own, `uv`).
- When the atlas is full it makes it again from the glyphs of the loaded tiles (`Map::rebuild_atlas`): `Atlas::repack` grows it while they fill more than half, from `ATLAS_SIZE` up to `MAX_ATLAS_SIZE`; loaded labels are re-pointed by `place_glyphs`; the bitmaps left out wait in `label.GlyphStore` until every worker answers the `glyphs` message that makes it send them again.
- It places labels as MapLibre's `Placement` does (`map/labels.mbt`: layers from the top down, tiles in its order, sort keys across tiles, a grid 100 px past the viewport, boxes in whole units of its tiles) when tiles arrive or every `PLACEMENT_INTERVAL` while the camera moves, uploading only the shown labels' indices.
- With `text-variable-anchor` each anchor is tried in turn (the one a label had first); a multi-line label is laid out once per justification and moved by a per-label shift (`a_shift`).

### Along lines

- Along lines (`symbol-placement` `line` and `line-center`) the glue ports MapLibre's `mergeLines`, `getAnchors` and `checkMaxAngle` (`worker/js/line-labels.mjs`) for tiles 1, 2 and 4 times as deep as the source's, since MapLibre lays labels out again past a source's maxzoom.
- The main thread places them with collision circles (`label.Grid`) and, for each frame the camera moved, walks each shown label's glyphs along its line as MapLibre's `updateLineLabels` does, flipped to read upright, into a per-vertex position and angle (`map/line_labels.mbt`, `a_glyph`).
- `npm run labels:golden` must stay all identical (glyphs within 0.5 px).

### Icons

- Icons (`icon-image`): the worker wasm adds each label's image name, `icon-size` (one zoom deeper, as MapLibre lays icons out) and `icon-rotate`; the glue shapes them as MapLibre's `shapeIcon`, `fitIconToText` and `getIconQuads` (`worker/js/symbols.mjs`) into a quad per icon and its collision box, padded and turned.
- The main thread places the icon's box after the text's as `placeLayerBucketPart` does (`text-optional`, `icon-optional`, the allow-overlap rules; with `icon-text-fit` and variable anchors the icon must fit at each anchor tried and moves with the text) and draws a symbol layer's icons before its text, with MapLibre's symbol_icon and symbol_sdf shaders.
- Along lines an icon goes with each instance (the anchors found for the longer of its text and icon, as MapLibre's `getShapedLabelLength`).
- Its box is laid on the map at the anchor and projected (MapLibre's `_projectCollisionBox`, `Map::fits_on_map`) beside the text's circles, and an icon turned with the line is placed each frame as one glyph at its anchor (`render_webgl2` `icon`: the size from a uniform unless data-driven, nearest sampling unless scaled, turned or pitched, `icon-rotation-alignment` / `icon-pitch-alignment`).

### Order, perspective, fonts and drawing

- `symbol-z-order` follows MapLibre: `viewport-y` places each tile's labels from the bottom of the turned screen up, and labels that may overlap are drawn in screen-y order (`y_order`, `sorts_by_y`).
- Text faces the viewer and is scaled by MapLibre's perspective ratio (0.5 + 0.5 × center distance / anchor distance), and labels whose ratio is below `MIN_PERSPECTIVE_RATIO` (beyond 5 camera distances) are not placed.
- Fonts come from the browser, not glyph PBFs: a `text-font` stack becomes MapLibre's local font (its names as CSS families, then the map's `fontFamily` where MapLibre adds sans-serif, the weight and style sniffed from the first name: `@style.font_face`), no `text-font` the map's `fontFamily`.
- Glyph keys carry their font (2^21 per font, numbered by each worker and renumbered by the main thread).
- Text is drawn with MapLibre's symbol_sdf fragment (halo blur, a halo pass of its own when wider than 1 px or letters are spaced closer), `format` sections' colors per vertex (`colors`, `a_section`).
- `*-translate` moves the text's and the icon's matrices in placement and drawing, and `*-overlap: cooperative` boxes meet only those of symbols that never overlap (`label.Grid` `never`).

### On terrain

- On terrain each label's anchor height (meters, from the deepest loaded DEM tile under it, looked up again only when a DEM tile arrives: `dem_version`) goes into a per-vertex attribute.
- Each frame the terrain grids are drawn again into a depth texture, and the symbol shader fades labels behind them out (MapLibre's `calculate_visibility`).

## Terrain (hillshade, color relief)

- A `raster-dem` source (MapLibre's `mapbox`/`terrarium`/`custom` encodings, plus the mbt-map extension `"encoding": "gsi"`) is fetched by a display worker, decoded from PNG with `createImageBitmap` (no color conversion) and turned by `raster` into MapLibre's hillshade-prepare slopes (two bytes per pixel, with its 1-pixel border) plus border elevations.
- The main thread uploads the slopes as an RG8 texture, redoes edge and border pixels against loaded neighbours (`map/dem.mbt`, `@raster.edge_slopes`) and draws MapLibre's hillshade (every `hillshade-method`, one shader) over a tile quad.
- `color-relief` layers repack the tile's heights into RGB by the source's encoding (Terrarium's for `gsi`) with MapLibre's 2-pixel border filled from loaded neighbours, and draw with MapLibre's color_relief shader over the stops of an `interpolate` on `["elevation"]` (allowed nowhere else).
- Tiles of 256 px sit one zoom deeper (`@core.zoom_shift`).
- Terrain analysis (`@analysis.Grid`: gdaldem's Horn slope, aspect, hillshade through `Trig`) runs in the analysis worker on DEM tiles mosaicked by `loadDem`; `npm run terrain:golden` compares it with GDAL's `gdaldem`.

## 3D terrain

- 3D terrain (style `terrain`): DEM tiles also carry their elevations (f32), uploaded as an R32F texture.
- Terrain tiles follow the display zoom (or the DEM's, if deeper) and use their part of the nearest loaded DEM tile (`u_dem`); more than `MIN_ZOOM_SLACK` levels above the DEM's minimum zoom there are none, and nothing is drawn (as MapLibre's terrain below its source's `minzoom`).
- Every layer but symbols is drawn into a per-tile render target, again only when what it holds changes (`Map::texture_signature`; `map/terrain.mbt`, 512 px × device pixel ratio up to 2), then draws a 65×65 grid with skirts raised by the DEM, with the depth test on and MapLibre's terrain fog (depth over `Transform::fog_range`, fading in from 60° to 70° of pitch).
- Symbols go on top.
- `Transform.elevation` lifts the camera's center to the ground height under it (meters times `pixels_per_meter`).

## Fill-extrusion

- `@tess.ExtrusionTessellator` ports MapLibre's bucket (a quad per ring edge, none along the tile's cut lines; roofs triangulated as fills; normals and the top-edge flag packed as MapLibre does).
- The worker bakes each feature's base and height, taken at the tile's zoom and one deeper, into its vertices (the renderer mixes them by the zoom's fraction, as MapLibre does for zoom-and-feature expressions); only the color is grouped.
- The main thread draws extrusion layers on screen (never into terrain textures) with MapLibre's fill_extrusion shader and the style's `light`, depth-tested (a depth-only pass first when translucent); on terrain each feature stands on the ground under its centroid (looked up like label heights, `ExtrusionGround`).

- Translucent or patterned extrusions are drawn as MapLibre does: all of the layer's meshes into depth first, then color with a stencil count so each pixel takes its nearest surface once (coincident roofs included); the context has a stencil buffer for it.
- With the style's `lights`, extrusions are lit and shadowed as [ARCHITECTURE-3D.md](ARCHITECTURE-3D.md) "Sun, lights and shadows" describes.
