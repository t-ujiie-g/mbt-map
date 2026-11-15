# Web component: `<mbt-map>`

`mbt-map/element` defines `<mbt-map>`, a custom element that holds a [`Map`](./map.md) in its shadow root. Attributes and properties set the style and camera, the element dispatches DOM events as the map moves, and its `map` property gives the full `Map` API for everything else. It works in plain HTML and in frameworks that render custom elements, React 19 included. The element imports the main entry (`mbt-map`) rather than bundling a second copy of it.

## Use in HTML

```html
<script type="module">
  import "mbt-map/element";

  const el = document.querySelector("mbt-map");
  el.addEventListener("mbt-map-load", (e) => {
    const map = e.detail.map; // the Map
    map.addLayer({ id: "dot", type: "circle", source: "places" });
  });
  el.addEventListener("mbt-map-click", (e) => console.log(e.detail.lngLat));
</script>

<mbt-map
  style-url="/style.json"
  center="139.7671,35.6812"
  zoom="14"
  style="display: block; height: 400px"
></mbt-map>
```

Importing the module registers the element (once; a second import does nothing). The element is `display: block; position: relative`; give it a height. The map is created when the element is in the document and has a style (`style-url` or `mapStyle`).

If you use GSI tiles, credit 国土地理院 (Geospatial Information Authority of Japan) in the sources' `attribution`, which the map shows unless `attribution-control="false"`.

## Attributes

| Attribute | Value |
|---|---|
| `style-url` | The style's URL. Ignored while `mapStyle` is set. |
| `center` | `lng,lat` in decimal degrees, e.g. `139.7671,35.6812`. |
| `zoom` | 0 to 22. |
| `bearing` | Degrees clockwise from north. |
| `pitch` | 0 to 85. |
| `worker-count` | One digit, 0 to 4 (0 picks automatically). |
| `worker-url`, `wasm-url` | Where `worker.js` and `mbt-map.wasm` are served; see [The map](./map.md#where-the-workers-and-wasm-come-from). |
| `attribution-control` | `true` (default) or `false`. Use `false` to show attributions yourself, for instance with `createAttribution` of [mbt-map/ui](./ui.md). |

Attributes are parsed strictly: numbers must be plain decimals (`14`, `-3.5`; no exponents, units or `NaN`), booleans exactly `true` or `false`. An invalid value is rejected, the previous value stays, and the element dispatches `mbt-map-error`. `worker-count`, `worker-url`, `wasm-url` and `attribution-control` are read when the map is created.

## Properties

| Property | |
|---|---|
| `map` | The `Map`, or `null` before it is created and after the element is removed. Read-only. |
| `mapStyle` | A style object. It takes precedence over `style-url`. Setting a new one swaps it in with `setStyle`, so sources and layers that stay alike keep their tiles; setting `null` falls back to `style-url` (or removes the map if there is none). |
| `center` | `{ lng, lat }`, or the attribute's string form. |
| `zoom`, `bearing`, `pitch` | A number, or the attribute's string form. |

The camera properties read the map's current camera, and setting them jumps the camera there (`jumpTo`). They accept the attribute strings too, because React 19 sets props as properties when the element has a property of that name. Invalid values are rejected with `mbt-map-error`, as for attributes.

```js
const el = document.querySelector("mbt-map");
el.mapStyle = { version: 8, sources: {}, layers: [{ id: "bg", type: "background", paint: { "background-color": "#eef" } }] };
el.zoom = 12;
el.center = { lng: 135.4959, lat: 34.7025 };
el.map?.flyTo({ zoom: 15 });
```

## Events

| Event | When |
|---|---|
| `mbt-map-load` | The first view has been drawn. |
| `mbt-map-idle` | The map has settled. |
| `mbt-map-movestart`, `mbt-map-move`, `mbt-map-moveend` | The camera moves. |
| `mbt-map-click` | A click on the map. |
| `mbt-map-error` | An invalid attribute or property, a failed map creation, or the map's `error`. |

Events are `CustomEvent`s that bubble and cross the shadow root (`composed`). Their `detail` is:

| Field | |
|---|---|
| `map` | The `Map`; `null` only for an `mbt-map-error` before the map exists. |
| `center`, `zoom`, `bearing`, `pitch` | The camera when the event fired. |
| `error` | For `mbt-map-error`. The error is also logged. |
| `point`, `lngLat` | For `mbt-map-click`: the screen point (CSS pixels from the map's top-left corner) and the place under it. |

For other events (layer clicks, `render`, `styledata`, …) listen on `el.map` with [`on`](./map.md#events) after `mbt-map-load`.

## Lifecycle

- Removing the element from the document frees the map (workers, GPU memory). Putting it back creates a new map with the camera the old one had.
- Moving the element within the document in one task (remove and re-insert) keeps the map.
- The map's own elements (canvas, attribution) live in the shadow root, so page styles do not reach them and frameworks see a single element with no children to manage.

## TypeScript

The module declares `"mbt-map"` in `HTMLElementTagNameMap`, so `document.querySelector("mbt-map")` is typed as `MbtMapElement`. The module also exports `MbtMapEventDetail`, the attribute parsers (`parseCenter`, `parseZoom`, `parseBearing`, `parsePitch`), the limits `MAX_ZOOM`, `MAX_PITCH` and `MAX_WORKERS`, and `mbtMapElement(id)`, which returns the `<mbt-map>` with that id or `null` (for bindings that hold an id, such as [mbt-map/moonbit](./moonbit.md)).

```ts
import { type MbtMapEventDetail } from "mbt-map/element";

const el = document.querySelector("mbt-map")!;
el.addEventListener("mbt-map-moveend", (e) => {
  const { center, zoom } = (e as CustomEvent<MbtMapEventDetail>).detail;
});
```

## React 19

React 19 renders custom elements directly: string props become attributes (or properties, when the element has one of that name), and `on<event>` props listen for the element's events. The showcase in `examples/react` uses `<mbt-map>` this way:

```jsx
import { useEffect, useRef, useState } from "react";
import "mbt-map/element";

export function MapView({ style }) {
  const ref = useRef(null);
  const [camera, setCamera] = useState(null);

  // A new style object goes to the map's setStyle: tiles of what stays alike are kept.
  useEffect(() => {
    ref.current.mapStyle = style;
  }, [style]);

  return (
    <>
      <mbt-map
        ref={ref}
        center="139.7671,35.6812"
        zoom="15"
        style={{ display: "block", height: "100vh" }}
        onmbt-map-load={(e) => console.log("loaded", e.detail.map)}
        onmbt-map-move={(e) => setCamera(e.detail)}
        onmbt-map-click={(e) => console.log(e.detail.lngLat)}
      />
      {camera && <p>zoom {camera.zoom.toFixed(2)}</p>}
    </>
  );
}
```

- Keep the map's own state in the map: the element moves its camera itself, and React re-renders from the events. Setting `center` or `zoom` props again jumps the camera.
- Set `mapStyle` through a ref (as above) or as a prop; memoize the style object so that each render does not hand the map a new style.
- To use controllers from [mbt-map/ui](./ui.md) or [mbt-map/search](./search.md), take the map from `e.detail.map` in `onmbt-map-load`, keep it in state, and read a controller with `useSyncExternalStore(c.subscribe, () => c.state)`.
- With TypeScript, React's JSX types do not know `<mbt-map>`; declare it in `JSX.IntrinsicElements` (or React's `react` module augmentation) in your project.

Bundling: esbuild keeps the package's `new URL("./worker.js", import.meta.url)` references, so copying the package's workers and wasm next to the bundle is enough; `examples/react/build.mjs` does that. See [Getting started](./getting-started.md).
