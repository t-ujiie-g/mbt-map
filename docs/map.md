# The map: `mbt-map`

The main entry, `mbt-map`, exports the `Map` class: a WebGL2 map that draws a style following the MapLibre style specification, with tiles decoded and tessellated in WebAssembly workers. Its methods, options and events have the names and shapes of MapLibre GL JS's, so code written against that API mostly carries over. This page is a guide to `Map` and a reference for each group of methods. What a style may contain is in [Style support](./style-support.md); the `<mbt-map>` element is in [Web component](./web-component.md).

- [Creating a map](#creating-a-map)
- [Camera](#camera)
- [Events](#events)
- [Changing the style at runtime](#changing-the-style-at-runtime)
- [GeoJSON sources](#geojson-sources)
- [Image, video and canvas sources](#image-video-and-canvas-sources)
- [Images and sprites](#images-and-sprites)
- [Feature queries](#feature-queries)
- [Feature state](#feature-state)
- [Global state](#global-state)
- [Terrain, sky and projection](#terrain-sky-and-projection)
- [Lights, the sun and shadows](#lights-the-sun-and-shadows)
- [3D picking, lines of sight, viewsheds and clipping](#3d-picking-lines-of-sight-viewsheds-and-clipping)
- [Following a place on screen](#following-a-place-on-screen)
- [Exporting an image](#exporting-an-image)
- [Custom layers](#custom-layers)
- [Requests: `transformRequest`](#requests-transformrequest)
- [Evaluating paint and expressions](#evaluating-paint-and-expressions)
- [Where the workers and wasm come from](#where-the-workers-and-wasm-come-from)
- [Other methods](#other-methods)

## Creating a map

```ts
import { Map } from "mbt-map";

const map = new Map({
  container: "map", // an element or its id; give it a size
  style: {
    version: 8,
    sources: {
      gsi: {
        type: "raster",
        tiles: ["https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png"],
        tileSize: 256,
        attribution: "国土地理院 (Geospatial Information Authority of Japan)",
      },
    },
    layers: [{ id: "gsi", type: "raster", source: "gsi" }],
  },
  center: [139.7671, 35.6812],
  zoom: 14,
});

map.on("load", () => console.log(map.getCenter(), map.getZoom()));
```

`style` is a style object or a URL. A URL is fetched without credentials (see [`transformRequest`](#requests-transformrequest)), and relative tile URLs in it resolve against it.

### Options

| Option | Default | Meaning |
|---|---|---|
| `container` | required | The element to draw in, or its id. A `static` container is made `relative`. |
| `style` | required | A style object, or the URL of one. |
| `center` | `[0, 0]` | `[lng, lat]` or `{ lng, lat }`. |
| `zoom` | `0` | |
| `bearing` | `0` | Degrees clockwise from north. |
| `pitch` | `0` | Degrees of tilt, 0 to 85. |
| `bounds`, `fitBoundsOptions` | | Show these bounds at start instead of `center` and `zoom`. |
| `minZoom`, `maxZoom` | `0`, `22` | Zoom limits (0 to 24). |
| `minPitch`, `maxPitch` | `0`, `85` | Pitch limits (0 to 85). |
| `maxBounds` | | Keep the view inside these bounds. |
| `renderWorldCopies` | `true` | Repeat the world east and west of the antimeridian, as MapLibre (up to three copies either side). With `false` the view stays within ±180° and the zoom is raised until the world fills the view's width. |
| `interactive` | `true` | `false` turns off every handler. |
| `dragPan`, `scrollZoom`, `boxZoom`, `dragRotate`, `keyboard`, `doubleClickZoom`, `touchZoomRotate`, `touchPitch` | `true` | Each input handler. |
| `attributionControl` | `true` | Shows the `attribution` of the sources of visible layers and the terrain in the bottom right corner. Attributions written as HTML keep their http(s) links; other tags are dropped and nothing is parsed as HTML. Set it to `false` to show them yourself (`getAttributions()`, or `createAttribution` in [mbt-map/ui](./ui.md)). |
| `fontFamily` | `"sans-serif"` | CSS font family for labels; see [labels](./style-support.md#symbol). |
| `strict` | `false` | Refuse styles with anything that cannot be drawn yet, instead of leaving it out with a `warning`. |
| `globalState` | | Initial values for [global state](#global-state), over the style's `state` defaults. |
| `transformRequest` | | See [Requests](#requests-transformrequest). |
| `workerCount` | `0` | Tile workers, 1 to 4; 0 picks half the hardware threads, at most 4. |
| `workerUrl`, `wasmUrl`, `geojsonWorkerUrl`, `geojsonWasmUrl`, `geojsonPropertiesWasmUrl` | next to the module | See [Where the workers and wasm come from](#where-the-workers-and-wasm-come-from). |

When the style contains properties, expressions or layers that mbt-map does not draw yet, the map leaves them out by default (a property falls back to its default, a layer or source that still cannot be drawn is dropped), logs them and fires a `warning` event. With `strict: true`, and for values that are invalid, a style object makes the constructor throw and a style URL fires `error`.

### Requirements

WebGL2, module workers and WebAssembly GC: Chrome and Edge 119 or later, Firefox 120 or later, Safari 18.2 or later. Pages with a Content Security Policy need `script-src 'wasm-unsafe-eval'` to compile the wasm and `worker-src 'self'` (or `script-src 'self'`) for the workers. mbt-map never uses `eval` or `new Function`.

### Default interaction

Drag to pan, wheel or pinch to zoom. Drag with the right button (or Ctrl and drag) to rotate (sideways) and pitch (up and down); twist two fingers to rotate and move two fingers up and down to pitch. Shift and drag zooms to a box. The keyboard moves by 100 px with the arrow keys, rotates and pitches with Shift and the arrows, and zooms with `+` and `-`. A double click zooms in (out with Shift). Released drags carry on with inertia.

Each handler is an object with `enable()`, `disable()` and `isEnabled()`:

```ts
map.scrollZoom.disable();
map.dragRotate.isEnabled(); // true
```

### Touch, the wheel and the page

On a touch screen the map takes the gestures of its enabled handlers and leaves the others to the browser. It sets the canvas's CSS `touch-action` for that, as MapLibre GL JS does on its canvas container, and updates it when a handler is enabled or disabled:

| Enabled | `touch-action` | The browser still does |
|---|---|---|
| `dragPan` and a two-finger handler (`touchZoomRotate` or `touchPitch`) | `none` | Nothing: drags and pinches on the map never scroll or zoom the page. |
| `dragPan` only | `pinch-zoom` | Page zoom by pinching. |
| A two-finger handler only | `pan-x pan-y` | Scrolling by one-finger drags. |
| Neither (`interactive: false` too) | `auto` | Everything. |

A map that fills a scrolling page therefore traps one-finger scrolling; turn `dragPan` off (`map.dragPan.disable()`) to let drags scroll the page and keep pinch zoom on the map. The map also cancels the `touchmove` events of the gestures it takes, for browsers that ignore `touch-action`, and the `wheel` events over it while `scrollZoom` is on (the page does not scroll; with `scrollZoom` off it does). There are no cooperative gestures (MapLibre's `cooperativeGestures`).

### Accessibility

The canvas is focusable (`tabindex="0"`, for the keyboard handler; `-1` with `interactive: false`) and is a `role="region"` named `Map`, as MapLibre's. To name it yourself, give the container an `aria-label` before creating the map, or set it on the canvas: `map.getCanvas().setAttribute("aria-label", "Route to the venue")`. `<mbt-map>` passes its own `aria-label` on.

## Camera

```ts
map.getCenter();  // { lng, lat }
map.getZoom();
map.getBearing();
map.getPitch();

map.jumpTo({ center: [139.7454, 35.6586], zoom: 16, bearing: 30, pitch: 45 });
map.setCenter([139.7, 35.68]).setZoom(12).setBearing(0).setPitch(0);
```

The bearing wraps to -180 to 180 and the pitch is clamped to the pitch range. A jump that changes nothing fires no `move`. Non-finite values (NaN, Infinity) throw a `TypeError`.

### Animated moves

```ts
map.easeTo({ center: [139.7671, 35.6812], zoom: 15, duration: 800 });
map.flyTo({ center: [135.4959, 34.7025], zoom: 13, speed: 1.2, curve: 1.42 });
map.fitBounds([[139.73, 35.66], [139.79, 35.70]], { padding: 40, maxZoom: 16 });
```

| Method | Notes |
|---|---|
| `easeTo(options)` | Eases to the camera given (500 ms by default). |
| `flyTo(options)` | Zooms out and back in on the way. Also takes `curve` (1.42), `speed` (1.2 screenfuls a second), `screenSpeed`, `maxDuration` (longer flights jump) and `minZoom` (lowest zoom on the way). |
| `panBy(offset, options?)`, `panTo(center, options?)` | |
| `zoomTo(zoom, options?)`, `zoomIn(options?)`, `zoomOut(options?)` | One zoom level in or out. |
| `rotateTo(bearing, options?)`, `resetNorth(options?)`, `resetNorthPitch(options?)`, `snapToNorth(options?)` | `resetNorth*` take 1000 ms by default; `snapToNorth` resets only within 7° of north. |
| `fitBounds(bounds, options?)` | A flight, or an ease with `linear: true`. |
| `fitScreenCoordinates(p0, p1, bearing, options?)` | Shows the box between two screen points, turned to `bearing`. |
| `cameraForBounds(bounds, options?)` | Returns `{ center, zoom, bearing }`, or `undefined` when the padding leaves no room or the map has not started. |
| `stop()` | Stops an animation. |
| `isMoving()`, `isEasing()`, `isZooming()`, `isRotating()` | |

Every move takes the camera fields `center`, `zoom`, `bearing`, `pitch` and `around` (a place that stays still on screen), and the animation fields `duration` (ms), `easing` (a function from 0..1 to 0..1; the default is the CSS `ease` curve), `offset` (where the center ends up, in pixels from the screen center), `animate` (`false` jumps) and `essential` (animate even when the user prefers reduced motion; otherwise moves jump then). `fitBounds` and `cameraForBounds` also take `padding` (a number or `{ top, right, bottom, left }`), `maxZoom`, `bearing` and `linear`.

Bounds are given as `[[west, south], [east, north]]`, `[west, south, east, north]` or an `LngLatBounds`, which the package exports:

```ts
import { LngLatBounds } from "mbt-map";

const b = new LngLatBounds(139.73, 35.66, 139.79, 35.70);
b.getCenter(); // { lng: 139.76, lat: 35.68 }
b.toArray();   // [[139.73, 35.66], [139.79, 35.70]]
```

Camera moves follow MapLibre's camera math: the default constraint (the zoom is raised until the view stays within ±85.051129° latitude and `maxBounds`), `easeTo`, `flyTo` and `cameraForBounds`.

### Screen and map coordinates

```ts
const p = map.project([139.7671, 35.6812]); // { x, y } in CSS pixels from the top-left corner
const ll = map.unproject([200, 150]);        // { lng, lat }
const box = map.getBounds();                 // LngLatBounds; up to the horizon when tilted
```

With terrain, `project` and `unproject` use the ground height. Before the map has started they return NaN. As in MapLibre, longitudes are not wrapped: `unproject` over the world copy east of the antimeridian gives longitudes past 180°, and `project` puts `lng + 360` one world to the east.

### Limits

`setRenderWorldCopies(bool)` turns the world copies on or off (undefined means true and null false, as MapLibre's) and `getRenderWorldCopies()` reads it. Tiles shown in several copies are loaded once and drawn in each; a tile's labels are placed in the copy nearest the center only, so when the world is narrower than the view (zoom below about 1) the other copies of a tile show no labels. Queries hit features in every copy (each feature once per tile, as MapLibre); `queryRenderedFeatures` gives their coordinates in the main world.

`setMinZoom`, `setMaxZoom`, `setMinPitch`, `setMaxPitch` and `setMaxBounds` change the limits (null or nothing restores the default; `setMaxBounds(null)` lifts the bounds), and `getMinZoom()`, `getMaxZoom()`, `getMinPitch()`, `getMaxPitch()` and `getMaxBounds()` read them. `getMinZoom(true)` gives the zoom the camera can actually go down to at this place, as the latitude limits and `maxBounds` raise it. Limits outside 0-24 (zoom) or 0-85 (pitch), or a minimum above its maximum, throw.

Map padding (`setPadding`) is not supported.

## Events

```ts
map.on("moveend", (e) => console.log(e.target.getCenter()));
map.once("load", () => { /* … */ });
await map.once("idle");                 // without a listener, once returns a Promise
map.off("moveend", listener);

map.on("click", "buildings", (e) => console.log(e.features?.[0]?.properties));
map.on("mouseenter", "buildings", () => (map.getCanvas().style.cursor = "pointer"));
map.on("mouseleave", "buildings", () => (map.getCanvas().style.cursor = ""));
```

`idle` follows MapLibre's: any change that draws ends with one, a single frame included (`triggerRepaint`, `setViewshed`, `setClipping`, a paint change), so `await map.once("idle")` after a change waits until it is on screen. A map at rest draws no frames and fires none. While frames keep coming without anything loading (a playing video, a custom layer that calls `triggerRepaint` in `render`), `idle` fires once when the map first settles and again when the repainting stops. Do not change the map in an `idle` listener without a condition: the change draws a frame, which fires `idle` again.

`on`, `off` and `once` take an event type and a listener, or for mouse events a type, a layer id (or an array of ids) and a listener. A listener given layers is called only when features of those layers are under the pointer, with them in `e.features`. Since the geometry lives in the workers, layer events come after a feature query, a little after the DOM event.

| Event | When | Fields |
|---|---|---|
| `load` | The first view has been drawn. | |
| `render` | After each frame. | |
| `idle` | After each frame that leaves the map settled: nothing loading, no gesture or animation, no further frame asked for. | |
| `styledata` | The style was loaded or changed. | |
| `sourcedata` | After `styledata`, for each source added or changed (new data, a new style). Not fired on tile loads. | `sourceId`, `dataType: "source"` |
| `styleimagemissing` | A tile uses an image the map lacks (once per name). Add it with `addImage` in the listener. | `id` |
| `warning` | After drawing a style, when what is left out of it changes. | `warnings`: `{ path, layer?, message }[]` |
| `error` | A style, source, request or edit failed. Without a listener the error is logged. | `error` |
| `movestart`, `move`, `moveend` | Camera changes, from any cause. | `originalEvent` for gestures |
| `zoomstart`, `zoom`, `zoomend`, `rotatestart`, `rotate`, `rotateend`, `pitchstart`, `pitch`, `pitchend` | As MapLibre orders them around `move`. | `originalEvent` for gestures |
| `mousedown`, `mouseup`, `mouseover`, `mouseout`, `mousemove`, `click`, `dblclick`, `contextmenu` | Pointer events on the canvas. A `click` needs the pointer to move less than 3 px between press and release. | `point` (CSS pixels), `lngLat`, `features` (with layers), `originalEvent` |
| `mouseenter`, `mouseleave` | Only with a layer: the pointer entered or left its features. | as above |

Every event also has `type` and `target` (the map).

## Changing the style at runtime

The style methods have MapLibre's names and arguments. They throw if the style has not loaded yet. An edit that would make the style undrawable fires `error`, and the map keeps drawing the style it had.

```ts
map.addSource("walk", { type: "geojson", data: walkGeoJSON });
map.addLayer({
  id: "walk",
  type: "line",
  source: "walk",
  paint: { "line-color": "#d33", "line-width": 4 },
}, "labels"); // below the layer "labels"; omit to put it on top

map.setPaintProperty("walk", "line-dasharray", [2, 1]);
map.setLayoutProperty("walk", "visibility", "none");
map.setFilter("buildings", [">=", ["get", "height"], 30]);
map.moveLayer("walk");          // to the top
map.removeLayer("walk");
map.removeSource("walk");
```

| Method | Notes |
|---|---|
| `setStyle(style, { transformStyle }?)` | A style object or URL. `transformStyle(previous, next)` returns the style to draw from the one asked for and the one drawn before (`undefined` the first time), for instance to keep overlay layers across basemaps. Sources and layers that stay alike keep their tiles; the others load again while the old tiles are drawn. Custom layers missing from the new style are removed. |
| `getStyle()` | A copy of the style drawn, GeoJSON data included, custom layers left out; `null` until loaded. |
| `addLayer(layer, beforeId?)`, `removeLayer(id)`, `moveLayer(id, beforeId?)` | `addLayer` also takes [custom layers](#custom-layers). |
| `getLayer(id)`, `getLayersOrder()` | Layer ids bottom first. |
| `setPaintProperty(id, name, value)`, `getPaintProperty(id, name)` | |
| `setLayoutProperty(id, name, value)`, `getLayoutProperty(id, name)` | Includes `visibility`. |
| `setFilter(id, filter?)`, `getFilter(id)` | null or nothing removes the filter. |
| `setLayerZoomRange(id, minzoom, maxzoom)` | |
| `addSource(id, source)`, `removeSource(id)`, `getSource(id)` | `removeSource` fires `error` while a layer or the terrain uses the source. A source given by `url` (TileJSON, PMTiles) draws once its document has arrived. |
| `setTerrain`, `getTerrain`, `setSky`, `getSky`, `setProjection`, `getProjection`, `setLight`, `getLight`, `setLights`, `getLights` | See [Terrain, sky and projection](#terrain-sky-and-projection) and [Lights](#lights-the-sun-and-shadows). |

Legacy filters (`["==", "class", "street"]`) and property functions (`{ stops: [...] }`) are converted to expressions; the converter is loaded only when a style uses them.

`getSource(id)` returns `undefined` for an unknown source, otherwise an object with `id`, `type`, `promoteId` (when the source has one), and the members of its type described below.

## GeoJSON sources

```ts
map.addSource("places", { type: "geojson", data: places, promoteId: "code" });
map.addLayer({ id: "places", type: "circle", source: "places", paint: { "circle-radius": 6 } });

const source = map.getSource("places")!;
source.setData?.(newPlaces);                     // an object, or a URL
const data = await source.getData?.();           // a copy; a URL source's data is fetched
await source.updateData?.({                      // MapLibre's GeoJSONSourceDiff
  add: [{ type: "Feature", id: 99, properties: { name: "new" }, geometry: { type: "Point", coordinates: [139.77, 35.68] } }],
  update: [{ id: 3, addOrUpdateProperties: [{ key: "visited", value: true }] }],
  remove: [7],
});
```

GeoJSON is read and cut into tiles in a worker of its own (`geojson-worker.js` and `geojson.wasm`), which starts with the first style that has a GeoJSON source. `data` is an object or an http(s) URL (fetched without credentials, through `transformRequest` as `"Source"`). The source options are `maxzoom`, `buffer`, `tolerance`, `lineMetrics`, `promoteId`, `cluster`, `clusterRadius`, `clusterMaxZoom`, `clusterMinPoints` and `clusterProperties`.

- `setData(data)` replaces the data.
- `updateData(diff)` applies a diff (`removeAll` or `remove`, then `add`, then `update`; each update applies `newGeometry`, `removeAllProperties`, `removeProperties`, `addOrUpdateProperties` in that order) and reloads only the tiles it touches. Every feature needs an id of its own (or the `promoteId` property), and ids must not repeat; otherwise the update fails with MapLibre's error ("GeoJSON data is not compatible with updateData"). The `GeoJSONSourceDiff` and `GeoJSONFeatureDiff` types are exported.
- `getData()` resolves with a copy of the data. For a URL source it fetches the URL again (up to 256 MB).

### Clusters

With `cluster: true` points are clustered. The cluster methods answer from the GeoJSON worker and resolve with null on a source without clustering:

```ts
map.on("click", "clusters", async (e) => {
  const id = e.features![0].properties.cluster_id as number;
  const source = map.getSource("stations")!;
  const zoom = await source.getClusterExpansionZoom!(id);
  if (zoom !== null) map.easeTo({ center: e.lngLat!, zoom });
  const leaves = await source.getClusterLeaves!(id, 10, 0); // limit 10 by default; Infinity for all
});
```

| Method | Resolves with |
|---|---|
| `getClusterExpansionZoom(clusterId)` | The zoom at which the cluster splits. |
| `getClusterChildren(clusterId)` | The clusters and points one zoom deeper. |
| `getClusterLeaves(clusterId, limit?, offset?)` | The points inside the cluster. |

`clusterProperties` (aggregates per cluster) are evaluated by a second wasm module, `geojson-properties.wasm`, loaded only for sources that have them.

## Image, video and canvas sources

`image` (`url`, `coordinates`), `video` (`urls`, `coordinates`; muted and looping) and `canvas` (`canvas` as an element id or, through `addSource`, the element itself; `animate`; `coordinates`) sources place a picture by its four corners, clockwise from the top left. `getSource(id)` gives them:

| Member | |
|---|---|
| `setCoordinates(corners)` | New corners. |
| `updateImage({ url, image, coordinates })` | A new picture (a URL or an already decoded image) and maybe new corners. |
| `play()`, `pause()` | For videos and canvases. |
| `getVideo()`, `getCanvas()` | The element. |

A playing video and an animating canvas are uploaded every frame. The map still fires `idle` meanwhile, once it has settled.

## Images and sprites

The style's `sprite` (one URL, or a list of `{ id, url }`) is loaded on its own, at `@2x` on a screen with a device pixel ratio of 2. More images for patterns and icons can be added:

```ts
const { data } = await map.loadImage("/icons/station.png");
map.addImage("station", data, { pixelRatio: 2 });
map.addImage("dot", { width: 2, height: 2, data: new Uint8Array(16).fill(255) });

map.on("styleimagemissing", (e) => {
  if (e.id === "hatch") map.addImage("hatch", makeHatch());
});
```

| Method | |
|---|---|
| `addImage(id, image, { pixelRatio, sdf }?)` | `image` is `ImageData`, `{ width, height, data }` of straight RGBA, or an image, `ImageBitmap` or canvas. `sdf: true` marks a signed-distance image colored by `icon-color`. An id already in use fires `error`. |
| `updateImage(id, image)` | Replaces the pixels. An unknown id fires `error`. |
| `removeImage(id)`, `hasImage(id)`, `listImages()` | `listImages` includes the sprite's images. |
| `loadImage(url)` | Fetches through `transformRequest` and resolves with `{ data: ImageBitmap }`. |

## Feature queries

Both query methods return Promises, because the workers hold the geometry. Results are in MapLibre's order and shape.

```ts
const hits = await map.queryRenderedFeatures([x, y], { layers: ["buildings"] });
const inBox = await map.queryRenderedFeatures([[0, 0], [200, 200]]);
const all = await map.queryRenderedFeatures();          // the whole view

const roads = await map.querySourceFeatures("gsi", { sourceLayer: "road", filter: ["==", ["get", "rdCtg"], 0] });
```

- `queryRenderedFeatures(geometry?, { layers, filter }?)` gives the features drawn at a point `[x, y]` or in a box `[[x0, y0], [x1, y1]]` (CSS pixels), topmost first. Each feature has `layer` (the style layer that drew it), `source`, `sourceLayer` and `state`. An unknown layer id in `layers` fires `error` and resolves with `[]`.
- `querySourceFeatures(sourceId, { sourceLayer, filter }?)` gives the source's features in the tiles drawn now (`sourceLayer` is required for vector sources). Each feature has `tile: { z, x, y }`, the source tile it came from; a feature crossing tiles comes once per tile.

Hits follow `*-translate`. A filter the engine cannot evaluate rejects the Promise. Tiles are queried as the source serves them; beyond a source's `maxzoom` they are not cut further.

## Feature state

```ts
map.setPaintProperty("buildings", "fill-color",
  ["case", ["boolean", ["feature-state", "hover"], false], "#f80", "#ccc"]);

map.setFeatureState({ source: "gsi", sourceLayer: "building", id: 12345 }, { hover: true });
map.getFeatureState({ source: "gsi", sourceLayer: "building", id: 12345 }); // { hover: true }
map.removeFeatureState({ source: "gsi", sourceLayer: "building", id: 12345 }, "hover");
map.removeFeatureState({ source: "gsi", sourceLayer: "building" });        // every feature's state
```

Paint that reads `["feature-state", key]` (wrapped in `boolean`, `number` or `string`) draws each feature with its state: colors and opacities of fill, line, circle, heatmap and fill-extrusion layers, line widths and circle radii. A feature's id is the tile's feature id, the GeoJSON feature's `id`, or the property the source's `promoteId` names; features sharing an id share a state. `sourceLayer` is required for vector sources. Feature state cannot be used in filters or layout. A change reaches the screen one worker round trip later.

## Global state

```ts
const map = new Map({ container: "map", style, globalState: { lang: "ja" } });
map.setGlobalStateProperty("lang", "en");
map.getGlobalState();                    // { lang: "en" }
map.setGlobalStateProperty("lang", null); // back to the style's state default
```

Expressions read it with `["global-state", name]`. The style's `state` gives defaults, `globalState` overrides them. Layers that read a changed key are drawn again; those that read it in filters or layout load their tiles again.

## Terrain, sky and projection

```ts
map.addSource("dem", {
  type: "raster-dem",
  tiles: ["https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png"],
  tileSize: 256,
  maxzoom: 14,
  encoding: "gsi",
  attribution: "国土地理院 標高タイル (Geospatial Information Authority of Japan)",
});
map.setTerrain({ source: "dem", exaggeration: 1.5 });
map.setSky({ "sky-color": "#88C6FC", "horizon-color": "#ffffff", "fog-color": "#ffffff" });
map.easeTo({ pitch: 70 });

map.setProjection({ type: "globe" });
```

| Method | |
|---|---|
| `setTerrain({ source, exaggeration })`, `getTerrain()` | Draws the map raised by a `raster-dem` source; `null` flattens it. |
| `setSky(sky)`, `getSky()` | The style's `sky`; `null` removes it. Without a sky, neither sky nor fog is drawn. |
| `setProjection({ type })`, `getProjection()` | `"globe"` draws a globe up to zoom 11 and Mercator from zoom 12, `"vertical-perspective"` keeps the globe, `"mercator"` or `null` flattens it. On the globe the atmosphere is drawn around it when the style has a `sky`. |
| `setLight(light)`, `getLight()` | The style's `light`, which lights extrusions; `null` removes it. |

With terrain the camera center rises to the ground under it, labels stand on the ground and are hidden behind it, and extrusions stand on the ground under their centroid. The DEM encodings and what else the style may set are in [Style support](./style-support.md#terrain-sky-globe-and-lights).

## Lights, the sun and shadows

A style may have a `lights` array (an mbt-map extension using Mapbox's property names): one `ambient` and one `directional` light. With it, extrusions and the layers of [mbt-map/3d](./3d.md) are lit as ambient plus sun instead of by the style's `light`.

```ts
import { Map, sunPosition, sunDirection, timeOfDayLights } from "mbt-map";

const when = new Date("2026-06-21T09:00:00+09:00");
sunPosition(when, 139.7671, 35.6812);   // { azimuth, altitude } in degrees, azimuth clockwise from north
sunDirection(when, 139.7671, 35.6812);  // [east, north, up] unit vector toward the sun

// Lights for that moment, with shadows from the sun
const lights = timeOfDayLights(when, 139.7671, 35.6812).map((l) =>
  l.type === "directional"
    ? { ...l, properties: { ...l.properties, "cast-shadows": true, "shadow-intensity": 0.6 } }
    : l,
);
map.setLights(lights);
map.getLights();
map.setLights(null); // back to `light`
```

| Function | |
|---|---|
| `sunPosition(date, lng, lat)` | The sun's azimuth and apparent altitude, as suncalc's `getPosition` computes them (note the argument order: longitude first). |
| `sunDirection(date, lng, lat)` | The unit vector toward the sun in east, north, up. |
| `timeOfDayLights(date, lng, lat)` | `[ambient, sun]` lights for that moment (the `Light` type is exported), eased between night, twilight and day. Throws a `RangeError` for an invalid date. |

Each light is `{ id, type: "ambient" | "directional", properties: { color, intensity, direction?, "cast-shadows"?, "shadow-intensity"? } }`. `direction` is `[azimuthal, polar]` in degrees. With `"cast-shadows": true` on the directional light, extrusions and custom layers that implement `renderShadow` (the layers of [mbt-map/3d](./3d.md)) cast shadows onto each other and onto the flat ground while the sun is above the horizon; `shadow-intensity` (0 to 1, default 1) sets how dark they are. Shadows fall on the flat ground, not on terrain.

## 3D picking, lines of sight, viewsheds and clipping

These methods are mbt-map's own. They read what the last frame drew: extrusions, the layers of [mbt-map/3d](./3d.md), terrain, and otherwise sea level.

```ts
const hit = map.pickPosition([x, y]);   // [lng, lat, meters] or null

const blocked = map.castRay(
  [139.7671, 35.6812, 50],              // from [lng, lat, m]
  [139.7700, 35.6830, 10],              // to
);                                      // the first hit, or null when the line is clear

map.setViewshed({ position: [139.7671, 35.6812, 40], heading: 90, pitch: -10, horizontalFov: 90, verticalFov: 60, distance: 500 });
map.setViewshed(null);

map.setClipping({
  origin: [139.7671, 35.6812, 0],
  planes: [[1, 0, 0, 0]],               // keep x > 0 (east of the origin)
  edgeWidth: 2,
  edgeColor: [1, 0.5, 0],
});
map.getClipping();
map.setClipping(null);
```

| Method | |
|---|---|
| `pickPosition(point)` | Longitude, latitude and height in meters of what is drawn under a screen point: extrusions, 3D layers, terrain, else sea level (on the globe, the globe's ground). `null` if nothing. |
| `castRay(from, to, margin = 0.1)` | Where the segment between two `[lng, lat, m]` points first meets what is drawn, stopping `margin` meters short of `to`; `null` if nothing is in the way. Throws unless both points are three finite numbers. |
| `setViewshed(v)` | Tints what is seen (green) and hidden (red) from `position` toward `heading` (degrees clockwise from north, default 0) and `pitch` (degrees up from level, negative looks down; default 0), within `horizontalFov` by `verticalFov` (90 and 60) and `distance` meters (500). The lights' shadows are off meanwhile. `null` removes it. Fields of view must lie between 0 and 180 degrees and the distance must exceed 1 m. |
| `setClipping(c)`, `getClipping()` | Clips extrusions and mbt-map/3d's layers, with planes and polygons in the manner of CesiumJS. |

A `Clipping` (the type is exported) is:

| Field | |
|---|---|
| `origin` | `[lng, lat, m?]`, the frame the planes are given in (east, north, up meters). |
| `planes` | Up to 16 `[nx, ny, nz, d]`; keeps where n·p + d > 0, by any plane, or by all with `unionClippingRegions: true`. |
| `edgeWidth`, `edgeColor` | A band of `edgeWidth` pixels along the planes in `edgeColor` (`[r, g, b]`, 0 to 1). |
| `polygons` | Up to 8 rings of `[lng, lat]` (64 points in all); cuts inside them, or outside with `inverse: true`. |

Clipped geometry casts no shadow and stops no ray. mbt-map/3d builds `lineOfSight` and 3D measurement on these methods; see [3D](./3d.md).

## Following a place on screen

To draw a marker or popup in the DOM over the map, track its place:

```ts
const marker = document.getElementById("marker")!;
const tracker = map.track([139.7671, 35.6812], ({ x, y, covered }) => {
  marker.style.transform = `translate(${x}px, ${y}px)`;
  marker.style.opacity = covered ? "0.2" : "1";
});
tracker.setLngLat([139.77, 35.68]);
tracker.getLngLat();
tracker.remove();
```

The callback runs after each frame, in the same frame the map draws (and at once if the map has started). `x` and `y` are CSS pixels from the canvas's top-left corner, on the terrain if there is one, and `covered` says whether the terrain hides the place, as MapLibre's `Marker` decides it. All tracked places are computed in one call per frame.

## Exporting an image

```ts
const blob = await map.toBlob({ pixelRatio: 2, type: "image/png" });
const url = URL.createObjectURL(blob);
```

`toBlob({ pixelRatio, type, quality, maxSize })` waits until the tiles, sprite and TileJSON documents have loaded, draws the current view offscreen (the canvas on screen does not change) and encodes it. `pixelRatio` defaults to the screen's; `type` and `quality` are as `HTMLCanvasElement.toBlob` takes them (PNG by default). Images larger than the GPU draws at once (or than `maxSize`) are drawn in parts and joined. DOM elements over the map, such as the attribution, are not in the image. The Promise rejects if the map is removed first.

## Custom layers

Custom layers follow MapLibre's `CustomLayerInterface`:

```ts
import type { CustomLayerInterface } from "mbt-map";

const layer: CustomLayerInterface = {
  id: "my-gl",
  type: "custom",
  renderingMode: "3d",
  onAdd(map, gl) { /* compile shaders, make buffers */ },
  render(gl, options) {
    // options.defaultProjectionData.mainMatrix maps Mercator 0..1 to clip space
    // options.modelViewProjectionMatrix takes world pixels, as MapLibre's
  },
  onRemove(map, gl) { /* free them */ },
};
map.addLayer(layer, "labels");
map.triggerRepaint(); // ask for a frame, e.g. from an animation
```

- `render(gl, options)` and `prerender(gl, options)` get MapLibre 6.16's options: `modelViewProjectionMatrix`, `projectionMatrix`, `defaultProjectionData`, `getProjectionData({ tileID })`, `shaderData` (the shader prelude for Mercator, or for the globe), `fov`, `nearZ`, `farZ`. With [lights](#lights-the-sun-and-shadows) they also carry `lights`, and with shadows or a viewshed `shadow`.
- `renderingMode: "3d"` shares the depth buffer with extrusions and terrain; `"2d"` draws without depth.
- `renderShadow(gl, options)` (mbt-map's) draws the layer's shadow casters into the shadow map, with the light's matrices in `options`.
- The GL state is saved before the layer's code and restored after it.
- Custom layers are drawn over terrain, never into its textures. `getStyle()` leaves them out and `setStyle` removes them, as in MapLibre. `getLayer(id)` returns the layer object itself.

## Requests: `transformRequest`

```ts
const map = new Map({
  container: "map",
  style: "https://tiles.example.com/style.json",
  transformRequest: (url, resourceType) =>
    url.startsWith("https://tiles.example.com/")
      ? { url, headers: { Authorization: `Bearer ${token}` } }
      : undefined,
});
map.setTransformRequest(null); // later: none
```

`transformRequest(url, resourceType)` may change the URL, add `headers` or send `credentials`; returning `undefined` leaves the request as it is. Without it no credentials are sent. `resourceType` is `"Style"`, `"Source"` (TileJSON and GeoJSON `data`), `"Tile"`, `"SpriteJSON"`, `"SpriteImage"` or `"Image"` (image sources, `loadImage`). PMTiles range requests (header and tiles) do not go through it. `setTransformRequest(transform)` replaces it for requests made from then on.

Styles, TileJSON documents and sprites are read up to 64 MB, GeoJSON fetched by `getData()` up to 256 MB; larger ones fail with `error`. Tile templates may use only MapLibre's placeholders (`{z}`, `{x}`, `{y}`, `{prefix}`, `{ratio}`, `{quadkey}`, `{bbox-epsg-3857}`) and must be http(s) URLs (or `pmtiles://`).

## Evaluating paint and expressions

```ts
import { evaluateExpression } from "mbt-map";

map.evaluatePaint("buildings", { ftCode: 3103 });
// { color: [r, g, b, a], width, radius, stroke, strokeWidth, halo, haloWidth }

evaluateExpression(["*", ["get", "area"], 2], [{ properties: { area: 3 } }]); // [6]
map.evaluateExpression(["interpolate", ["linear"], ["zoom"], 10, 1, 16, 8], [{}]); // at the map's zoom
```

- `evaluatePaint(layerId, properties?)` gives a layer's paint for a feature with those properties at the current zoom: colors as straight RGBA in 0 to 1 with the layer's opacity applied, sizes in CSS pixels; `null` for an unknown layer or before the map has started. Legends in [mbt-map/ui](./ui.md) use it.
- `evaluateExpression(expression, features, { zoom })` evaluates a style expression for each feature (`{ id?, properties?, geometry? }`; a GeoJSON Feature will do) as style-spec's `evaluate` does: colors as their `to-string` text, `format` as its text, evaluation errors and NaN as `null`, object and array properties read as `null`. An expression that does not compile throws. The function exported by the package defaults to zoom 0; the `Map` method to the map's zoom.

## Where the workers and wasm come from

By default every file is loaded from next to the module that loads it, such as `new URL("./worker.js", import.meta.url)`. Serving the package's `dist/` directory as is (for instance with an import map) works without options. Vite and webpack find and emit the files by themselves; what the other bundlers need is in [Getting started](./getting-started.md#bundlers). To serve the files yourself, pass their URLs:

| Option | File |
|---|---|
| `workerUrl` | `worker.js`, the tile worker. Its parts `worker-labels.js`, `worker-pmtiles.js` and `worker-query.js` must sit next to it. |
| `wasmUrl` | `mbt-map.wasm` |
| `geojsonWorkerUrl`, `geojsonWasmUrl` | `geojson-worker.js`, `geojson.wasm` |
| `geojsonPropertiesWasmUrl` | `geojson-properties.wasm`, for sources with `clusterProperties` |

These modules are imported dynamically from next to `index.js` and cannot be moved: `geojson.js` (GeoJSON sources), `legacy.js` (legacy filters and functions), `sprite.js`, `tilejson-merge.js` (sources given by `url`), `pmtiles.js`, `geotiff-source.js` (`geotiff` and `reprojected` sources, which also need mbt-map/data's worker and wasm files next to it; see [Data](./data.md)), `media.js` (image, video and canvas sources), `custom.js` (custom layers) and `export.js` (`toBlob`).

Workers must be same-origin http(s) URLs and wasm must be http(s); `data:` and `blob:` URLs are refused.

## Other methods

| Method | |
|---|---|
| `loaded()` | Whether the first view has been drawn. |
| `getContainer()`, `getCanvas()` | |
| `getAttributions()` | The attributions shown now: of the sources the visible layers and the terrain use. |
| `triggerRepaint()` | Draws a frame soon. |
| `remove()` | Stops the workers, frees GPU memory and removes the map's elements. |

The other entries of the package build on `Map`: headless controls in [mbt-map/ui](./ui.md), search in [mbt-map/search](./search.md), drawing in [mbt-map/draw](./draw.md), web services in [mbt-map/services](./services.md), analysis in [mbt-map/analysis](./analysis.md), data files in [mbt-map/data](./data.md), 3D content in [mbt-map/3d](./3d.md) and MoonBit bindings in [mbt-map/moonbit](./moonbit.md). Installation is in [Getting started](./getting-started.md).
