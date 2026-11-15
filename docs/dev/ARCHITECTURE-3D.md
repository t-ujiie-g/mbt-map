# Architecture: 3D

Part of the architecture reference ([index](ARCHITECTURE.md)). `mbt-map/3d` (its own entry, worker and wasm: `model_worker`, 3d.wasm, with the `meshopt`, `draco` and `lepcc` ports) and the engine features its layers share with extrusions: lights, shadows, picking and clipping.

## 3D models

- 3D models (`mbt-map/3d`, its own entry, worker and wasm; Phase 20.3): `npm/src/model/gltf.ts` (importing only `tiles/geo.ts`) reads glTF 2.0 (.glb, or .gltf with its buffers and images beside it) into flat primitives, each attribute its own compact typed array (sparse accessors applied, KHR_mesh_quantization kept quantized for the GPU), the nodes' world matrices, materials (base color, its texture with KHR_texture_transform, alpha modes, KHR_materials_unlit) and image bytes (EXT_texture_webp preferred), refusing other required extensions and capped by `MAX_MODEL_BYTES`, `MAX_GLTF_JSON_BYTES` and `MAX_NODE_DEPTH`.
- It runs in the 3D worker (`model_worker/js/worker.mjs`), whose wasm (3d.wasm, `model_worker`) decodes:
  - EXT_/KHR_meshopt_compression buffer views with `meshopt`, a port of meshoptimizer 1.3.0's decoder (`npm run meshopt:golden` against its wasm decoder, 0 differ);
  - KHR_draco_mesh_compression primitives with `draco`, a port of Draco 1.5.7's mesh decoder (bitstreams 2.0 to 2.2, edgebreaker and sequential connectivity, its prediction schemes and transforms) that also decodes point clouds (bitstreams 2.0 to 2.3, sequential and kd-tree, the float kd-tree of the older bitstreams included). `@draco.decode` takes either, as the header says; capped by `MAX_FACES`, `MAX_POINTS`, `MAX_ATTRIBUTES`, `MAX_ATTRIBUTE_BYTES`, `MAX_KD_DIMENSIONS`; `draco_decode` writes docs/dev/FORMATS.md "Draco output"; `npm run draco:golden` against draco3d, 0 differ;
  - I3S point clouds' LEPCC blobs (`lepcc-xyz`, `lepcc-rgb`, `lepcc-intensity`) with `lepcc`, a port of Esri's LEPCC decoders (`lepcc_decode` writes docs/dev/FORMATS.md "LEPCC output", capped by `MAX_POINTS`; `npm run lepcc:golden` against the C++, 0 differ).
- Images become ImageBitmaps there.
- `npm run model:golden` compares `loadModel` in Chromium with @loaders.gl/gltf 4.5.4 (attributes, indices, materials, texture transforms) and gltf-transform 4.5.1's world matrices, and checks hostile files are refused.

### `modelLayer`

- `modelLayer` is a custom layer (renderingMode "3d") drawing the model at each GeoJSON point: glTF's +Y up turned to up, `scale` / `rotation` / `translation` (constants or `["get", key]`, Mapbox's `model-*` names) in east, north, up meters, then per instance in f64 to Mercator (`defaultProjectionData`, its fallback on the globe) and to the unit sphere (`modelViewProjectionMatrix` on the globe), mixed by the projection transition in the shader as `interpolateProjectionFor3D`.
- Instances behind the globe's horizon plane are skipped.
- Lighting is Lambert from Mapbox's default light direction, unlit for KHR_materials_unlit; normals missing are taken from screen derivatives; faces are drawn double-sided; blended materials and translucent instances go in a second pass without depth writes (not sorted).

## 3D Tiles

- 3D Tiles (`mbt-map/3d`'s `tilesLayer`, whose work is `npm/src/3d-tiles.ts`, loaded as `3d-tiles.js` with the first; Phase 20.4): `npm/src/tiles/` is import-free.

### Tree and selection

- `geo.ts` ports what @loaders.gl/tiles 4.5.4 selects with through math.gl 4.1 (the WGS 84 ellipsoid, east-north-up frames, oriented boxes from `box` and `region` as `createObbFromRegion` makes them, spheres, plane masks).
- `tileset.ts` builds the tree (`buildTree`; tiles keyed by `path`, child indices from the root, `t` under an external tileset's tile) and ports `TilesetTraverser` with `Tileset3DTraverser`'s visibility (no skipped levels, loaders.gl's `sseDenominator` 1.15 and `maximumScreenSpaceError` 8; children sorted farthest first in place).
- `implicit.ts` reads subtree files and expands implicit tiling eagerly as loaders.gl's `parseImplicitTiles` (regions split per level; boxes split by the specification, which loaders.gl leaves whole).

### Contents and properties

- `content.ts` reads:
  - b3dm (feature table, RTC_CENTER, batch table and its binary body, glb);
  - i3dm (each instance's matrix as loaders.gl builds it, RTC included, with Cesium's explicit and oct-encoded normals where loaders.gl leaves them out);
  - pnts (one POINTS primitive, +Z up: positions dequantized with the volume's offset moved into the RTC in f64, RGBA / RGB / RGB565 and oct normals as Cesium decodes them where loaders.gl shifts and reads at 256, CONSTANT_RGBA as the material, BATCH_ID or a batch table row per point as `_BATCHID`, 3DTILES_draco_point_compression semantics and batch properties through the Draco port);
  - cmpt (parts flattened);
  - glTF contents (CESIUM_RTC; points drawn too, a Draco point primitive without indices).
- `properties.ts` turns feature ids into properties: batch tables (JSON and binary) and EXT_structural_metadata property tables by the 3D Metadata specification (where loaders.gl departs from it, `npm run tiles:properties` checks the values written), with `Primitive.featureIds` (EXT_mesh_features attribute or implicit ids, `_BATCHID`) and `Model.metadata` from `gltf.ts`.

### Golden

- `npm run tiles:golden` traverses with loaders.gl's own `Tileset3D` and the same frame states (a 60° camera of its own) until nothing more loads, on PLATEAU's Chiyoda buildings (`plateau-chiyoda` fixture: the tiles around Tokyo Station, their ancestors and siblings, since a REPLACE tile gives way only once all its children load; the others are missing on both sides) and synthetic tilesets (boxes with transforms, spheres with ADD, empty tiles, a viewer request volume, an external tileset, implicit quadtree and octree), and compares b3dm tables: all identical.

### Frame state, loading and drawing

- `frame.ts` takes the frame state from the matrix a custom layer draws with (Web Mercator's, or the globe's unit sphere past half the transition): eye, direction and frustum corners to ECEF, side planes through the eye.
- The layer loads contents in the 3D worker (op `tile`, six at a time, nearest first), keeps at most `maximumLoadedTiles` (default 256), and draws each tile's meters in east, north, up at its bounding volume's center (`Y_UP` for glTF contents, RTC, the tile's transform), with the model layer's program (`npm/src/model/draw.ts`).
- `height` shifts ellipsoidal heights onto the map's ground.
- With terrain (exaggeration 1) tiles stand on it through the shared depth buffer.
- Each instance of an i3dm is drawn with its own matrix (one draw per instance).
- Points are round sprites `pointSize` CSS pixels across (default 2), unlit unless they have normals.

### Picking features

- `queryFeature` picks the feature under a point: the pick pass draws the selected tiles' parts into an offscreen RGBA8 target (part index in red and green, feature id in blue and alpha: `_BATCHID` or `_FEATURE_ID_0` at attribute 5, an instance's batch id otherwise; ids past 65535 wrap) and reads the pixel after the frame.
- `bench/tiles/synthetic.mjs` writes the pack test's tilesets (b3dm, cmpt with i3dm; pnts with a glTF of points).

## I3S

- I3S (`mbt-map/3d`'s `i3sLayer`, whose work is `npm/src/3d-i3s.ts`, loaded as `3d-i3s.js` with the first, on 3d-tiles.js's engine through its `TileSource`; Phase 20.7a): 3DObject and IntegratedMesh layers of I3S 1.7 and later with node pages, in WGS 84 (`checkSpatialReference`).
- `i3s/scene.ts` reads the layer (a SceneServer `…/layers/0`, or a layer document `….json` with its resources beside it), loads node pages as the traversal asks for nodes' children (`Traversal.expand`), makes each node a `Tile` (its OBB turned by its quaternion as loaders.gl's `createBox`, the OBB's bounding sphere as its `mbs`, `maxScreenThresholdSQ` as a diameter) and decides refinement as loaders.gl's `getLodStatus` / `getProjectedRadius` through the frame state's `view` (the matrix it came from, projected to pixels as deck.gl's `viewport.project`).
- `npm run i3s:golden` compares the selection with loaders.gl.
- `i3s/content.ts` (import-free) reads a node's geometry buffer (the Draco one when offered, as loaders.gl, else the uncompressed layout; offsets in degrees and meters from the node's center taken to ECEF as math.gl does and to f32 east, north, up meters; `_BATCHID` the feature index, `_UV_REGION` kept for the shader, which repeats atlas uvs inside their region) in the 3D worker (op `i3s`, JPEG and PNG textures only), and attribute buffers on the main thread (`readI3sAttribute`, a feature's row found by OBJECTID as loaders.gl).
- `npm run i3s:contents` compares both with @loaders.gl/i3s on public Esri layers and the synthetic one (`bench/i3s/synthetic.mjs` writes the pack test's layer).

### Point cloud layers

- Point cloud layers (PCSL, `layerType` PointCloud, I3S 2.0; Phase 20.7b): nodes from `store.index`'s pages (`resourceId`, `firstChild` / `childCount`), refined while their points' density on screen (`vertexCount` over the area `lodThreshold`, `density-threshold`) is below `POINT_DENSITY`.
- The 3D worker's `pcsl` op decodes LEPCC (`lepcc`, a port of Esri's decoders: xyz absolute in the layer's CRS, rgb, intensity; `npm run lepcc:golden` against Esri's C++, built here) into f32 east, north, up meters around the node, colored as `pointCloudLayer` (`model/cloud.ts`).

### SLPK

- SLPKs (`i3s/slpk.ts`, loaded as `3d-slpk.js` for an `.slpk` URL) are read by range requests (whole when refused, a 416 included): the hash table when its record is in the first read, else the central directory; their entries go to the worker as bytes (`i3s` op's `geometry` / `textureBytes`, `pcsl`'s resources).
- `bench/i3s/pcsl-synthetic.mjs` and `slpk-write.mjs` write the pack test's point cloud layer and SLPK.

## Point clouds (LAS)

- Point clouds (`mbt-map/3d`'s `pointCloudLayer`; Phase 20.6): `npm/src/model/las.ts` (import-free) reads uncompressed LAS 1.0 to 1.4 (point formats 0 to 10, extra bytes skipped, the CRS from GeoTIFF keys or WKT; thinned to `maxPoints` by every k-th point as loaders.gl's `skip`; colors scaled to 8 bits as its `colorDepth: "auto"`; LAZ refused) in the 3D worker (op `las`), which takes the points to longitude and latitude through proj.wasm (`data_worker/js/crs.mjs`'s `transformPairs`, bundled in; `prjwkt.js` for a WKT-only file; both URLs in the init message) and then to f32 east, north, up meters around the bounds' center.
- Heights pass as they are.
- `npm run las:golden` compares the reader with @loaders.gl/las 4.5.4 and PDAL's samples, and the op with proj4js.
- The layer draws one POINTS mesh with the model program, colored by the file's RGB, height, intensity or ASPRS class (`setColor`).
- `bench/las/synthetic.mjs` writes the pack test's cloud (`bench/npm/pages/pointcloud/cloud.las`, EPSG:6677; gitignored, written by `bench/npm/prepare.mjs`).

## Sun, lights and shadows

- Sun and lights (Phase 20.8a; an mbt-map extension with Mapbox's documented names, since Mapbox GL JS v3 cannot be ported): `npm/src/sun.ts` (import-free, exported by the main entry) ports suncalc 2.1.1's `getPosition` (`sunPosition`, degrees, azimuth clockwise from north; `npm run sun:golden`), gives `sunDirection` in east, north, up and `timeOfDayLights` (night, twilight and day stops eased by smoothstep).
- The style's `lights` (`@style.Lights`: an `ambient` and a `directional` light, `color`, `intensity`, `direction` [azimuthal, polar]; other types reported as Unsupported) is set by `setLights` / `getLights`.
- With it, extrusions are lit as `color * (ambient + sun * lambert)` instead of MapLibre's light (`u_ambient.a` set, patterns too), custom layers get the colors times intensities and the direction after their numbers (`Map::custom_numbers`, read by `renderInput` as `lights`), and mbt-map/3d's layers pass them to the model program (`begin` takes the render input), which uses the same formula.
- Without `lights` both keep their old lighting.
- The direction is east, north, up from Mapbox's azimuth (`Map::lights`; MapLibre's `light_direction` runs west and north, as its extrusion normals do).

### Shadows

- Shadows (Phase 20.8b; the directional light's `cast-shadows` and `shadow-intensity`): each frame with the sun above the horizon `Map::draw_shadow_map` draws casters' depth into one 2048 px depth texture (`@core.SHADOW_MAP_SIZE`, texture unit 7, sampled with comparison by every program that receives) through an orthographic view along the light.
  - The view: `@core.Transform::shadow_view` over world pixels around the center, wider as the camera tilts, casters up to 1000 m; `shadow_sphere_view` over the unit sphere past half the globe's transition.
  - Casters: extrusions in pass 3 of their program, custom layers through mbt-map's `renderShadow` (mode 2 of `call_custom`, with `Map::shadow_numbers`: the light's views as their matrices).
- Extrusions and the model program take the sun's term times `sunlit()` (four compared taps, 1 - intensity in shadow); the flat ground is darkened under the first extrusion or custom layer by `groundShadow` over the view's tiles (the sun's share of the ground's light, not on terrain).
- `custom_numbers` has a fixed layout (`CUSTOM_*`: the globe's numbers zeroed off it, then the lights and the shadows), which `renderInput` reads as `lights` and `shadow` (`mode` 1 flat, 2 sphere, 3 viewshed).

## 3D picking and lines of sight

- 3D picking, lines of sight and viewsheds (Phase 20.9a) reuse the shadow map.
- A ray is drawn as casters' depth through `@core.ray_view` (an orthographic box 2 cm either side of the segment) into an 8-texel corner without polygon offset and read back at its center (`Renderer::shadow_depth_at`: 24 bits of depth into RGB), the terrain or sea level met on the CPU (`Transform::ground_hit`, the occlusion ray march).
- `Map::cast_ray` and `Map::pick_position` (`Transform::eye_ray`; the globe's ground only) are the facade's `castRay` and `pickPosition`, and mbt-map/3d's `lineOfSight` and `measure3d` (`npm/src/measure3d.ts`, import-free: WGS 84 straight-line, horizontal and vertical distances, Newell's areas) build on them.
- `mbt-map/ui`'s `createMeasurement` measures in 3D with `measure3d` (clicks through `pickPosition`).

### Viewsheds

- `setViewshed` makes the frame's shadows a perspective from the observer (`@core.spot_view`, `Shadows.spot`, mode 3): receivers keep their light and `tint()` what the view covers seen (green) or hidden (red) by `VIEWSHED_TINT`, the ground pass too; the lights' shadows are off meanwhile.
- `npm run sight:golden` checks all three against analytic answers.

### Clipping

- Clipping (Phase 20.9b; CesiumJS's planes and polygons): `setClipping` keeps where n·p + d > 0 of `planes` in east, north, up meters at `origin` (by any plane, or all with `unionClippingRegions`), cuts inside `polygons` (outside them with `inverse`) and gives a band `edgeWidth` pixels by the planes `edgeColor`.
- `npm/src/clipping.ts` (import-free) packs it for the engine (`set_cut`; extrusions' `cut()` over `v_cut`, the tile's frame from `Transform::enu_matrix`) and for mbt-map/3d's layers, which read `getClipping` (`clipOf`; the model program's `cut()` over Mercator taken to the origin's meters).
- Clipped geometry casts no shadow and stops no ray.
- `npm run clip:cesium` compares the shapes with CesiumJS on PLATEAU.
