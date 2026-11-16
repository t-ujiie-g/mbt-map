# UI controllers (`mbt-map/ui`)

`mbt-map/ui` is a set of headless controllers for the usual map controls: zoom buttons and compass, scale bar, attribution, geolocation, full screen, coordinate readout, feature identification, legend, layer list, basemap switcher, measurement, elevation profile, attribute table and field editor. A controller creates no DOM. It holds a `state` value, offers operations as methods, and tells you when the state changes; you draw the control however you like, in plain DOM, React or anything else. Each controller lives in its own module, so a bundle contains only the controllers it imports. The controllers use only the public API of [`Map`](./map.md).

```js
import { createNavigation, createScale } from "mbt-map/ui";
```

## The controller model

Every controller has the same shape:

```ts
interface Controller<S> {
  readonly state: S;
  subscribe(listener: (state: S) => void): () => void;
  destroy(): void;
}
```

- `state` is replaced by a new object whenever something in it changes, and stays the same object otherwise. Listeners are called only when a value really changed.
- `subscribe(listener)` returns the function that unsubscribes. It does not call the listener at once, so read `state` for the first render.
- `destroy()` removes the controller's map listeners (and anything it added, such as overlay layers) and drops its subscribers.

In React, `useSyncExternalStore(c.subscribe, () => c.state)` reads a controller as it is.

### Wiring one to the DOM

```js
import { createNavigation, createScale } from "mbt-map/ui";

const nav = createNavigation(map);
const scale = createScale(map, { maxWidth: 120 });

const zoomIn = document.querySelector("#zoom-in");
const zoomOut = document.querySelector("#zoom-out");
const needle = document.querySelector("#needle");
const bar = document.querySelector("#scale");

function render() {
  const n = nav.state;
  zoomIn.disabled = !n.canZoomIn;
  zoomOut.disabled = !n.canZoomOut;
  needle.style.transform = `rotateX(${n.pitch}deg) rotateZ(${-n.bearing}deg)`;
  bar.style.width = `${scale.state.width}px`;
  bar.textContent = scale.state.label;
}
render();
nav.subscribe(render);
scale.subscribe(render);

zoomIn.onclick = () => nav.zoomIn();
zoomOut.onclick = () => nav.zoomOut();
document.querySelector("#compass").onclick = () => nav.resetNorth(true);
```

A React component does the same with a hook:

```jsx
import { useSyncExternalStore } from "react";

function ScaleBar({ scale }) {
  const s = useSyncExternalStore(scale.subscribe, () => scale.state);
  return <div className="scale" style={{ width: s.width }}>{s.label}</div>;
}
```

Things drawn on the map at a place (the location dot, a pin) are left to the page: use `map.track(lngLat, callback)` to keep an element on its place (see [Map](./map.md)).

## Navigation: `createNavigation(map, options)`

Zoom buttons, compass and home button.

| Option | Description |
|---|---|
| `home` | Camera options `home()` flies to. Default: the camera when the controller was made. |

| State | Description |
|---|---|
| `zoom`, `bearing`, `pitch` | The current camera. |
| `canZoomIn`, `canZoomOut` | False at the maximum or minimum zoom (disable the buttons). |

Operations: `zoomIn()`, `zoomOut()`, `resetNorth(pitch?)` (north up; with `pitch: true` also looking straight down, as a compass click does), `home()`.

## Scale bar: `createScale(map, options)`

| Option | Description |
|---|---|
| `maxWidth` | The longest the bar may be, in CSS pixels. Default 100. |
| `unit` | `"metric"` (default), `"imperial"` or `"nautical"`. |

| State | Description |
|---|---|
| `width` | The bar's width in CSS pixels. |
| `distance` | A round number of `unit`. |
| `unit` | `"m"`, `"km"`, `"ft"`, `"mi"` or `"nm"`. |
| `label` | `distance` and `unit` joined by a no-break space. |

Operation: `setUnit(unit)`. `measureScale(map, maxWidth?, unit?)` measures once and returns the same state object without a controller.

## Attribution: `createAttribution(map, options)`

The sources' attribution texts, for drawing them yourself. Turn the map's own attribution off with `attributionControl: false` (or `<mbt-map attribution-control="false">`, see [Web component](./web-component.md)).

| Option | Description |
|---|---|
| `customAttribution` | A string or strings shown before the sources'. |

| State | Description |
|---|---|
| `items` | The attribution texts as plain text (tags of attributions written as HTML dropped), `customAttribution` first. |
| `text` | `items` joined with `" | "`. |

## Geolocation: `createGeolocation(map, options)`

Finds the user with the Geolocation API and moves the map to the accuracy range.

| Option | Description |
|---|---|
| `positionOptions` | Passed to the Geolocation API. Default `{ enableHighAccuracy: false, maximumAge: 0, timeout: 6000 }`. |
| `fitBoundsOptions` | Used when moving the camera. Default `{ maxZoom: 15 }`. |
| `trackUserLocation` | Keep following the position. Default false (locate once). |
| `zoomToUserAccuracy` | Fit the accuracy circle. Default true; false keeps the zoom. |
| `geolocation` | A replacement for `navigator.geolocation` (for tests). |

| State | Description |
|---|---|
| `status` | `"off"`, `"waiting"` (for a first position), `"active"` (the camera follows), `"background"` (the user moved the map away), `"active-error"`, `"background-error"`, or `"unavailable"` (no Geolocation API, or permission denied). |
| `position` | `{ lngLat, accuracy, heading, timestamp }` of the last fix, or null. |
| `accuracyRadius` | The accuracy as a radius in CSS pixels at the current camera, for drawing the circle. |
| `error` | `{ code, message }` of the last Geolocation error, or null. |
| `outOfMaxBounds` | True when the last position fell outside the map's `maxBounds`. |

Operation: `trigger()` does what a click on a locate button does: locate once, or cycle tracking on, off, or back to `active` from `background`. It returns false when geolocation is unavailable. While tracking, a pan or rotate moves the status to `background`; zooming alone keeps it `active`.

```js
const geo = createGeolocation(map, { trackUserLocation: true });
locate.onclick = () => geo.trigger();
let tracker = null;
geo.subscribe((g) => {
  dot.hidden = !g.position;
  if (!g.position) return;
  dot.style.setProperty("--accuracy", `${g.accuracyRadius}px`);
  if (tracker) tracker.setLngLat(g.position.lngLat);
  else tracker = map.track(g.position.lngLat, ({ x, y }) => (dot.style.transform = `translate(${x}px, ${y}px)`));
});
```

## Full screen: `createFullscreen(map, options)`

| Option | Description |
|---|---|
| `container` | The element that goes full screen. Default the map's container. |

| State | Description |
|---|---|
| `active` | The container fills the screen. |
| `pseudo` | True when the browser has no Fullscreen API: then `toggle()` only flips `active`, and the page makes the element fill the window. |

Operation: `toggle()`.

## Coordinates: `createCoordinates(map, options)`

The pointer's position (or the center when the pointer is off the map) written in one or more coordinate systems.

| Option | Description |
|---|---|
| `systems` | The coordinate systems. Default `[degrees(), degreesMinutesSeconds()]`. |
| `follow` | `"pointer"` (default) or `"center"` only. |

| State | Description |
|---|---|
| `lngLat` | The position shown, or null before the first. |
| `source` | `"pointer"` or `"center"`. |
| `values` | `{ id, title, text }` for each system. |

Coordinate systems:

- `degrees(digits = 5)`: decimal latitude and longitude.
- `degreesMinutesSeconds(digits = 1)`: degrees, minutes and seconds with hemisphere letters.
- `projected({ id, title, transform, crs, digits })`: a projected CRS through a `transform` you pass; `crs` is a code or a function choosing one for a place. The text is `X … m, Y … m` (northing as X, as Japan's plane rectangular systems write it).
- `utm(transform, digits = 0)`: WGS 84 UTM in the zone of the place.
- Any object `{ id, title, format(lngLat) }` whose `format` returns a string or a Promise of one.

The projected systems take `mbt-map/analysis`'s `transform` (see [Analysis](./analysis.md)), so `mbt-map/ui` itself contains no projection code. Conversions run one at a time and only the latest position is converted.

```js
import { transform } from "mbt-map/analysis";
import { createCoordinates, degrees, projected, utm } from "mbt-map/ui";

const coords = createCoordinates(map, {
  systems: [degrees(), projected({ id: "jgd-ix", title: "JGD2011 IX", transform, crs: 6677 }), utm(transform)],
});
coords.subscribe((s) => (readout.textContent = s.values.map((v) => `${v.title}: ${v.text}`).join("\n")));
```

Formatting helpers usable on their own: `formatDegrees(lngLat, digits?)`, `formatDms(lngLat, digits?)`, `utmZone(lngLat)` (returns `{ zone, north, epsg }`), `formatLength(meters)` and `formatArea(squareMeters)`.

## Identify: `createIdentify(map, options)`

The features drawn around a clicked point, one of them selected and highlighted with feature state.

| Option | Description |
|---|---|
| `layers` | Layer ids to identify. Default all. |
| `radius` | CSS pixels around the point. Default 3. |
| `highlight` | Feature-state key set to true on the selected feature. Default `"selected"`; false for none. |
| `click` | Identify on every map click. Default true. |

| State | Description |
|---|---|
| `point`, `lngLat` | Where the last identify was, or null. |
| `features` | The features found, top first. |
| `index` | The selected feature, -1 for none. |
| `loading` | While the query runs. |

Operations: `identify(point)` (a Promise), `select(i)`, `next()`, `previous()`, `clear()`.

To highlight the selection, read the state in paint:

```js
map.setPaintProperty("buildings", "fill-color", ["case", ["boolean", ["feature-state", "selected"], false], "#e4572e", "#ccc"]);
const identify = createIdentify(map, { layers: ["buildings"] });
identify.subscribe((s) => showPopup(s.features[s.index]));
```

## Legend: `createLegend(map, options)`

Swatches for each layer, taken from its style, with colors as the engine evaluates them at the current zoom. A layer whose color depends on a feature property through `match`, `step`, an `interpolate` over a property, or a `case` of `==` tests is split into one item per category.

| Option | Description |
|---|---|
| `layers` | Layer ids to show. Default all but the background. |
| `title(layer)` | An entry's title. Default `metadata["mbt-map:title"]`, else the layer id. |
| `label(layer, category)` | An item's label (return undefined for the default). |

State: `entries`, top layer first. Each entry has:

| Field | Description |
|---|---|
| `id`, `type`, `title` | The layer. |
| `visible` | Whether the layer is shown at this zoom. |
| `kind` | `"single"`, `"match"`, `"step"` or `"interpolate"`. |
| `property` | The feature property the color reads, or null. |
| `items` | `{ label, category, paint }` per swatch. Raster and hillshade layers have none. |

A `category` (`LegendCategory`) has `values` (for `match` and `case`), `range` `[from, to)` (for `step`; null ends are open), `value` (an `interpolate` stop) or `other` (the fallback), plus `properties` of a feature drawn that way. `paint` is what `map.evaluatePaint(layerId, properties)` gives.

## Layer list: `createLayerList(map, options)`

Layers, or groups of layers, to show and hide.

| Option | Description |
|---|---|
| `groups` | Items made of several layers, `{ id, title?, layers }`, in the order given. Without it, each layer but the background is an item, top first. |
| `title(layer)` | An item's title. Default the id. |

State: `items`, each with `id`, `title`, `layers` (the ids the style has), `visible` (all shown), `mixed` (some shown), and `inRange` (the current zoom is within a layer's zoom range).

Operations: `setVisible(id, visible)` and `toggle(id)` (they set the layers' `visibility` layout property).

## Basemaps: `createBasemaps(map, options)`

Switches the basemap with `setStyle` while keeping overlay layers, with their sources and data.

| Option | Description |
|---|---|
| `basemaps` | `{ id, title?, style }[]`. `style` is a style object, a style URL, or a function returning one when chosen. |
| `active` | The id of the basemap drawn at first. Default none (the map's own style). |
| `overlay(layer)` | Which layers to keep. Default those whose `metadata` has `"mbt-map:overlay": true`. |

State: `active` (an id or null) and `basemaps` (`{ id, title }[]`). Operation: `select(id)`.

Kept overlays stay in place where the new style has a layer of the same id, and go on top otherwise. The measurement and draw controllers mark their own layers as overlays, so they survive a basemap change.

```js
const basemaps = createBasemaps(map, {
  basemaps: [
    { id: "std", title: "Standard", style: "https://example.com/std.json" },
    { id: "photo", title: "Photo", style: () => photoStyle() },
  ],
  active: "std",
});
select.onchange = () => basemaps.select(select.value);
```

## Measurement: `createMeasurement(map, options)`

Measures distances and areas by clicking on the map. The lengths and areas are computed on the WGS 84 ellipsoid by the `measure` function you pass, usually `mbt-map/geodesic`'s ([Draw and geodesic](./draw.md#geodesic-measurement-mbt-mapgeodesic)); `mbt-map/ui` contains no geodesic code.

| Option | Description |
|---|---|
| `measure` | `mbt-map/geodesic`'s `measure`. |
| `measure3d` | Instead, `mbt-map/3d`'s `measure3d`: clicks then take the position drawn under the pointer (`map.pickPosition`), and the state gets `horizontal` and `vertical` too. See [3D](./3d.md). |
| `step` | Meters between the points that draw each geodesic. Default 1000. |
| `id` | The GeoJSON source id and layer prefix. Default `"mbt-map-measure"`. |
| `color` | Line, vertex and fill color. Default `"#e4572e"`. |

| State | Description |
|---|---|
| `mode` | `"distance"`, `"area"`, or null when not measuring. |
| `positions` | The vertices placed. |
| `pointer` | The vertex following the pointer until `finish`, or null. |
| `length` | Meters (an area's perimeter), counting the pointer. |
| `area` | Square meters, or null for a distance. |
| `segments` | Each edge's length in meters. |
| `finished` | True once done. |
| `horizontal`, `vertical` | With `measure3d` only. |

Operations: `start(mode)`, `add(position)`, `undo()`, `finish()` (a double click also finishes), `clear()`. Double-click zoom is off while measuring and restored by `clear()`. The line and area are drawn through the controller's own GeoJSON source and layers.

```js
import { measure } from "mbt-map/geodesic";
import { createMeasurement, formatArea, formatLength } from "mbt-map/ui";

const m = createMeasurement(map, { measure });
distanceButton.onclick = () => m.start("distance");
m.subscribe((s) => {
  out.textContent = s.mode ? `${formatLength(s.length)}${s.area !== null ? `, ${formatArea(s.area)}` : ""}` : "";
});
```

## Elevation profile: `createProfile(options)`

The elevation profile of a line. It takes no map: the line comes from the page (a finished measurement, a feature).

| Option | Description |
|---|---|
| `measure` | `mbt-map/geodesic`'s `measure`. |
| `elevation` | `(positions) => Promise<ArrayLike<number>>`: heights in meters (NaN where unknown), for example `mbt-map/analysis`'s `sampleDem`. |
| `samples` | About how many samples along the line. Default 200. |

| State | Description |
|---|---|
| `positions` | The line given. |
| `path` | The samples along its geodesics. |
| `distances`, `elevations` | Distance to and elevation at each sample, in meters. |
| `length`, `min`, `max`, `gain`, `loss` | In meters (`gain` and `loss` are the total ascent and descent). |
| `active` | The sample pointed at, -1 for none. |
| `loading`, `error` | While sampling; the last attempt's error message, or null. |

Operations: `setLine(positions)` (a Promise), `highlight(distance)` (the sample nearest a distance, for a pointer over the chart; null to remove it), `clear()`. Draw the chart and the marker yourself.

```js
import { sampleDem } from "mbt-map/analysis";
import { measure } from "mbt-map/geodesic";
import { createProfile } from "mbt-map/ui";

const dem = "https://example.com/dem/{z}/{x}/{y}.png";
const profile = createProfile({ measure, elevation: (p) => sampleDem(dem, p, { encoding: "terrarium" }) });
measurement.subscribe((s) => {
  if (s.mode === "distance" && s.finished) void profile.setLine(s.positions);
});
```

## Attribute table: `createAttributeTable(map, options)`

One source's features as rows to sort, filter, page through and select. The selection is mirrored to the map with feature state.

Rows come from a GeoJSON source's whole data (`getSource(id).getData()`), or from a vector source's features in the tiles drawn now (`querySourceFeatures`; `sourceLayer` is required, and pieces with the same id from several tiles become one row whose geometry is a GeometryCollection). The table reads the source again on its `sourcedata` event (and on `idle` for vector sources); changes within one task are read once.

| Option | Description |
|---|---|
| `source` | The source id. |
| `sourceLayer` | The layer of a vector source. |
| `columns` | Columns to show. Default every property key, in the order first seen. |
| `searchColumns` | Columns the query looks in. Default the columns. |
| `filter` | A predicate `(row) => boolean` rows must pass. |
| `pageSize` | Rows per page. Default 50. |
| `locale` | Locale of the sort's `Intl.Collator` (numeric). |
| `highlight` | Feature-state key set on selected features. Default `"selected"`; false for none. |
| `fitBoundsOptions` | For `zoomTo`. Default `{ padding: 40, maxZoom: 17 }`. |

| State | Description |
|---|---|
| `columns` | The columns shown. |
| `rows` | The current page's rows, each `{ id, properties, geometry }`. |
| `total` | All rows. |
| `filtered` | Rows passing the query and filter. |
| `page`, `pages`, `pageSize` | Paging (`page` from 0). |
| `sort` | `{ column, direction }` or null (the source's order). |
| `query` | The search text. |
| `selected` | Selected ids, as strings. |
| `loading`, `error` | While reading the source; the error if that failed. |

Operations:

- `setSort(column, direction?)`: without a direction, ascending, or the other way on the same column; null for the source's order. Numbers sort first, then text, then missing values (always last); equal values keep their order.
- `setQuery(text)`: keeps rows whose search columns contain the text, ignoring full and half width, case, and katakana versus hiragana (as `mbt-map/search` does).
- `setFilter(predicate)`, `setPageSize(n)`, `goTo(page)`, `next()`, `previous()`.
- `select(id, { add })`: select alone, or with `add` toggle in the selection; `clear()` empties it.
- `reveal(id)`: goes to the page with the feature's row (to scroll to it after a pick on the map); false when the query or filter leaves it out.
- `zoomTo(id, options?)`: fits the map to the feature; false when it has no geometry. A feature split at the antimeridian (Russia, Fiji) is fitted across it.
- `refresh()`, `setColumns(columns)` (null for every key), `passing(rows)` (those rows that pass the query and filter).

`cellText(value)` writes a cell: empty for null and undefined, JSON for objects and arrays.

```js
import { cellText, createAttributeTable } from "mbt-map/ui";

const table = createAttributeTable(map, { source: "parks", pageSize: 20 });
table.subscribe((s) => {
  tbody.replaceChildren(...s.rows.map((r) => {
    const tr = document.createElement("tr");
    tr.onclick = () => { table.select(r.id); table.zoomTo(r.id); };
    for (const c of s.columns) tr.insertCell().textContent = cellText(r.properties[c]);
    return tr;
  }));
});
search.oninput = () => table.setQuery(search.value);
```

## Field editor: `createFieldEditor(map, options)`

Edits the columns of a GeoJSON source (field calculation). It reads the data with `getData()` and writes only the changed features back with `updateData` (or `setData` when the features lack unique ids).

| Option | Description |
|---|---|
| `source` | The GeoJSON source to edit. |
| `table` | An attribute table of it: its columns follow the edits, and `only` picks from its rows. |

Operations (all return Promises):

- `calculate(column, value, { only })`: sets `column` (added if new) to `value`, which is a style expression evaluated per feature (`map.evaluateExpression`; `["id"]` is the row's id, promoted ids included) or a function of the row. `only` is `"filtered"` (rows passing the table's query and filter) or `"selected"`; it needs `table`.
- `addColumn(column, value = null, { only })`: as `calculate`, refused if any feature already has the column.
- `removeColumn(column)`.
- `renameColumn(from, to)`: the key keeps its place among each feature's keys; throws if a feature already has `to`.

A column name must be a non-empty string other than `__proto__`. Values computed from geometry (areas, lengths) come from [`mbt-map/analysis`](./analysis.md) and are passed as a function.

```js
const editor = createFieldEditor(map, { source: "parks", table });
await editor.calculate("label", ["concat", ["get", "name"], " (", ["get", "ward"], ")"]);
await editor.addColumn("checked", false, { only: "selected" });
```
