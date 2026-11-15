# Drawing (`mbt-map/draw`) and geodesics (`mbt-map/geodesic`)

`mbt-map/draw` is a headless drawing and editing controller: points, lines, polygons, rectangles, geodesic circles and freehand shapes, editing of vertices, snapping, splitting and merging, properties, and undo and redo. Like the [`mbt-map/ui`](./ui.md) controllers it has a `state`, operations and `subscribe`, and draws nothing of its own but the shapes on the map; toolbars and key bindings are the page's. `mbt-map/geodesic` computes distances, azimuths, areas and circles on the WGS 84 ellipsoid in a worker of its own, started on the first call; the draw controller uses it for circles, and [`createMeasurement`](./ui.md#measurement-createmeasurementmap-options) and [`createProfile`](./ui.md#elevation-profile-createprofileoptions) take its `measure`.

```js
import { createDraw } from "mbt-map/draw";
import * as geodesic from "mbt-map/geodesic";

const draw = createDraw(map, { geodesic });   // geodesic is needed only for circles
draw.setMode("polygon");
draw.subscribe((s) => render(s.mode, s.features, s.canUndo, s.canRedo));
```

## `createDraw(map, options)`

| Option | Description |
|---|---|
| `geodesic` | The `mbt-map/geodesic` module (its `circle` and `inverse`). Required for `"circle"` mode. |
| `geometry` | `{ split, merge }`: `mbt-map/analysis`'s `splitFeatures` and `mergeFeatures`. Required for `"split"` mode and `merge()`. |
| `snapping` | `true`, or `{ vertices, lines, pixels }`. Default off. |
| `id` | The GeoJSON source id and layer prefix. Default `"mbt-map-draw"`. |
| `color` | The shapes' color. Default `"#3b6ed6"` (selected shapes are drawn in `#e4572e`). |
| `steps` | Points per circle. Default 64. |
| `precision` | Decimals kept in coordinates (0 to 15). Default 9 (about 0.1 mm). |

`setMode("circle")` throws without `geodesic`, and `setMode("split")` throws without `geometry`. Neither module is imported by `mbt-map/draw` itself.

```js
import { mergeFeatures, splitFeatures } from "mbt-map/analysis";
import { createDraw } from "mbt-map/draw";
import * as geodesic from "mbt-map/geodesic";

const draw = createDraw(map, { geodesic, snapping: true, geometry: { split: splitFeatures, merge: mergeFeatures } });
```

## Modes

`setMode(mode)` takes one of the drawing modes, `"select"`, `"split"`, or null to stop. While a mode is on, double-click zoom and box zoom are off (Shift+click selects) and the cursor is a crosshair in drawing modes; `setMode(null)` restores them.

| Mode | How to draw |
|---|---|
| `"point"` | Click. |
| `"linestring"` | Click to place vertices; click the last vertex again (within 40 px) to finish. |
| `"polygon"` | Click to place vertices; click the first or last vertex to close. |
| `"rectangle"` | Two clicks at opposite corners. |
| `"circle"` | Click the center, then a point on the edge. The circle is geodesic, with `steps` points. |
| `"freehand"` | Click to start; moving adds a vertex every 20 px; click to close. |

The clicks and thresholds follow terra-draw's defaults. `finish()` ends the shape under way if it has enough vertices (two distinct for a line, three for a polygon), and `cancel()` drops it. While drawing, `undo()` removes the last vertex.

Coordinates are rounded to `precision` decimals, and polygons are written with outer rings counter-clockwise and holes clockwise (RFC 7946).

## Editing (`"select"` mode)

- Click a shape to select it; Shift+click adds it to the selection or removes it.
- On the selected shape: drag a vertex to move it, drag a midpoint to add a vertex, right-click a vertex to delete it (a line keeps at least 2 vertices, a polygon ring at least 3), and drag the shape's body (near it, for points and lines) to move the whole shape.
- Map panning is off during a drag, and one drag is one undo step.
- Shapes with Multi geometries (made by `merge()`) can be selected and moved as a whole but their vertices are not editable.

`deleteSelected()` removes the selection. `select(id, add?)` selects from code (null for none).

## Snapping

With `snapping: true` (or an object), new vertices and dragged vertices snap to other shapes: to their nearest vertex within `pixels` (default 40) if `vertices` is on, else to the nearest point of an edge if `lines` is on. Both are on by default. Freehand drawing does not snap.

## Split and merge

These need the `geometry` option (`mbt-map/analysis`, see [Analysis](./analysis.md)):

- `setMode("split")`, then draw a line (finished as in `"linestring"` mode): it cuts the selected shapes, or, with none selected, every shape it crosses. A polygon is cut where the line crosses it from edge to edge; a line is cut where they cross. Each piece keeps the original's properties.
- `merge()` joins the selected shapes (two or more) into one: polygons by union, lines joined at their ends, points into a MultiPoint. The result has the first shape's properties.

The geometry module computes on a 1e-7° grid (about 1 cm). Each split or merge is one undo step. When the analysis module or the geodesic module refuses an operation, the reason is in `state.error`.

## Properties

`setProperties(id, properties)` merges properties into a feature; a null value removes that key. The `mode` property is kept as it is. It is one undo step.

## Undo and redo

Every change to the features (a shape drawn, a drag, a deletion, a split, `add`, `remove`, `clear`) is one step. `undo()` and `redo()` move through them; `canUndo` and `canRedo` say whether they can.

## State

| Field | Description |
|---|---|
| `mode` | The current mode, or null. |
| `features` | The shapes drawn: GeoJSON features with a controller-given `id` and `properties.mode` (the mode that drew them). |
| `drawing` | The geometry of the shape under way (following the pointer), or null. |
| `vertices` | The vertices placed for it. |
| `selection` | Selected ids. |
| `selected` | The last of them, or null. |
| `canUndo`, `canRedo` | Whether `undo()` / `redo()` do anything. |
| `error` | Why the last split or circle failed, or null; cleared when the features change. |

There are no events besides `subscribe`: compare `features` between states to see what changed.

## Operations

| Method | Description |
|---|---|
| `setMode(mode)` | See [Modes](#modes). |
| `select(id, add?)` | Select a feature (null for none); with `add`, toggle it in the selection. |
| `setProperties(id, properties)` | Merge properties. |
| `deleteSelected()` | Remove the selected features. |
| `merge()` | Merge the selection. Returns a Promise. |
| `finish()`, `cancel()` | End or drop the shape under way. |
| `undo()`, `redo()` | |
| `add(features)` | Add GeoJSON features (`{ geometry, properties? }`); `properties.mode` defaults from the geometry type. |
| `remove(id)`, `clear()` | Remove one feature, or all. |
| `destroy()` | Stop, and remove the source and layers. |

Key bindings (Enter to finish, Escape to cancel, Delete, Ctrl+Z) are the page's. Do not pass on keys while an IME composition is under way (`e.isComposing`, or `keyCode` 229 in Safari):

```js
document.addEventListener("keydown", (e) => {
  if (e.isComposing || e.keyCode === 229 || e.target instanceof HTMLInputElement) return;
  if (e.key === "Enter") draw.finish();
  else if (e.key === "Escape") draw.cancel();
  else if (e.key === "Delete" || e.key === "Backspace") draw.deleteSelected();
  else if ((e.ctrlKey || e.metaKey) && e.key === "z") e.shiftKey ? draw.redo() : draw.undo();
});
```

## Drawing on the map

The shapes are drawn through two GeoJSON sources of the controller's own, `<id>` (the features) and `<id>-sketch` (the shape under way, its vertices and the selected shape's handles), with layers prefixed by `id`. The features' source is updated only when the features or the selection change, the sketch on each pointer move. The layers are marked as overlays (`metadata["mbt-map:overlay"]`), so they survive a basemap change with [`createBasemaps`](./ui.md#basemaps-createbasemapsmap-options).

To save the drawing, read `draw.state.features`; to load one, pass features to `add()`.

```js
localStorage.setItem("drawing", JSON.stringify({ type: "FeatureCollection", features: draw.state.features }));
draw.add(JSON.parse(localStorage.getItem("drawing") ?? '{"features":[]}').features);
```

## Geodesic measurement (`mbt-map/geodesic`)

```js
import { circle, direct, inverse, measure } from "mbt-map/geodesic";

const { distance, azimuth1 } = await inverse([139.7671, 35.6812], [135.4959, 34.7025]); // meters, degrees from north
const { position } = await direct([139.7671, 35.6812], 90, 10_000);                     // 10 km east
const { length, area, path } = await measure(ring, { closed: true, step: 1000 });       // perimeter, area, densified path
const ring64 = await circle([139.7671, 35.6812], 500);                                  // 500 m around a point
```

Every function computes on the WGS 84 ellipsoid with a port of GeographicLib's geodesic routines (geographiclib-geodesic 2.2.0) and returns a Promise. Positions are `[longitude, latitude]` in degrees.

| Function | Result |
|---|---|
| `inverse(from, to)` | `distance` (m); `azimuth1`, `azimuth2` (degrees clockwise from north, at each end in the direction of travel); `arc` (degrees on the auxiliary sphere); `area` (m² between the geodesic and the equator). |
| `direct(from, azimuth, distance)` | `position` reached, `azimuth` there, `arc`. |
| `circle(center, radius, { steps })` | A closed ring of `steps` points (default 64, up to 4096) `radius` meters around `center`. |
| `measure(positions, { closed, step })` | `length` in meters (a ring's perimeter when `closed`); `area` in m² (counter-clockwise rings positive, NaN for a line, 0 below three positions); `distances` (a `Float64Array` of the distance along the path to each position); and, with `step`, `path`: points at most `step` meters apart along the geodesics, for drawing on a Web Mercator map (longitudes continue past ±180). |
| `terminate()` | Stops the worker; pending calls reject. |

Each function also takes `workerUrl` and `wasmUrl` in its options, for when `geodesic-worker.js` and `geodesic.wasm` are not served next to the module (see [Getting started](./getting-started.md)).
