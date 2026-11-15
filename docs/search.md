# Search (`mbt-map/search`)

`mbt-map/search` is a headless search box controller (geosearch). It keeps the query, gathers results from one or more providers after a pause in typing, aborts searches the query has moved on from, tracks the active result for keyboard navigation and ARIA, and moves the map to the result chosen. It has the same shape as the [`mbt-map/ui`](./ui.md) controllers (`state`, `subscribe`, operations, `destroy`) and creates no DOM. The providers bundled with it ask no server; an external geocoding API becomes a provider of the same shape.

```js
import { transform } from "mbt-map/analysis";
import { coordinates, createSearch, datasetSearch } from "mbt-map/search";

const search = createSearch(map, {
  providers: [coordinates({ transform }), datasetSearch(shops, { fields: ["name"] })],
});
search.subscribe((s) => render(s.query, s.results, s.active));
input.oninput = (e) => search.setQuery(e.target.value);       // debounced; stale searches are aborted
list.onclick = (e) => search.select(Number(e.target.dataset.i)); // moves the map to the result
```

## The controller: `createSearch(map, options)`

| Option | Description |
|---|---|
| `providers` | The providers, in the order their results are shown. |
| `debounce` | Milliseconds of quiet typing before searching. Default 250. |
| `limit` | Results per provider. Default 8. |
| `zoom` | Zoom for a chosen point. Default 16. |
| `maxZoom` | Maximum zoom when fitting a chosen area. Default 17. |

| State | Description |
|---|---|
| `query` | The text as typed. |
| `results` | The results of every provider, in provider order. |
| `active` | The result the arrow keys reached, -1 for none (use it for `aria-activedescendant`). |
| `open` | While there are results to choose from. |
| `loading` | While searching. |
| `errors` | `{ provider, message }` for providers that failed this time; the others' results still show. |
| `selected` | The last result chosen, or null. |

Operations:

- `setQuery(query)`: sets the query and searches after `debounce` ms; an empty query clears the results.
- `submit()`: searches now (on Enter, for example). Returns a Promise.
- `move(delta)`: moves the active result by `delta`, wrapping around.
- `select(index?)`: chooses result `index` (default the active one, else the first) and moves the map: `flyTo` for a point, `fitBounds` (padding 40) for a result with a `bbox`.
- `close()`, `clear()`.
- `reverse(lngLat)`: asks the providers that have `reverse` what is at a place. Returns a Promise of results.

Queries longer than `MAX_QUERY_LENGTH` (256 characters) are cut before reaching the providers.

A result (`SearchResult`) has `provider`, `label`, optional `detail`, `lngLat`, optional `bbox` (`[west, south, east, north]`) and optional `properties`.

### Keys and input methods

Key handling is the page's. Leave keys of an IME composition alone: a Japanese user's Enter that confirms a conversion must not choose a result. Check `isComposing`, and also `keyCode` 229, which Safari sends for the confirming Enter after `compositionend`.

```js
input.addEventListener("keydown", (e) => {
  if (e.isComposing || e.keyCode === 229) return;
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    search.move(e.key === "ArrowDown" ? 1 : -1);
  } else if (e.key === "Enter") {
    if (search.state.results.length) search.select();
    else void search.submit().then(() => search.select());
  } else if (e.key === "Escape") search.close();
});
```

To keep a pin on the chosen place, use `map.track(result.lngLat, callback)` (see [Map](./map.md)).

## Bundled providers

### `coordinates({ transform, name })`

Reads coordinates typed into the box:

- decimal degrees, latitude and longitude in either order;
- degrees, minutes and seconds (`35°40′52″N`, `35度40分52秒`, `'` and `"`);
- full-width digits.

With `transform` (for example `mbt-map/analysis`'s `transform`, see [Analysis](./analysis.md)) it also reads Japan's plane rectangular coordinate systems on JGD2011 (`第IX系 X -35367.2 Y -5995.2`, or `9系`) and WGS 84 UTM (`54N 388708 3949480`). Without `transform` these are not read, and `mbt-map/search` loads no projection code. Its `reverse` writes a place in degrees. `name` defaults to `"coordinates"`.

The parsers are exported on their own: `parseLngLat(text)` (every reading of two angles as a place), `parsePlaneRectangular(text)` and `parseUtm(text)` (each `{ epsg, x, y, title }` or null).

### `datasetSearch(data, { fields, label, name })`

Searches the properties of GeoJSON features. `data` is a FeatureCollection, or a function returning the current one (it is indexed again when the object changes).

- `fields`: the property names to search.
- `label(feature)`: a result's label. Default the first field's value.
- `name`: default `"dataset"`.

Text is compared after folding full and half width, case, and katakana to hiragana (`normalize(text)` is the folding). Exact matches come first, then prefix matches, then the rest. A feature's result points at the center of its bounding box and carries the box when the feature is not a single point.

## Writing a provider for an external API

A provider is an object:

```ts
interface SearchProvider {
  name: string;
  search(query: string, request: SearchRequest): SearchResult[] | Promise<SearchResult[]>;
  reverse?(lngLat: LngLat, request: SearchRequest): SearchResult[] | Promise<SearchResult[]>;
}

interface SearchRequest {
  signal: AbortSignal;                              // aborted when the query moves on
  bbox: [number, number, number, number] | null;    // the current view
  limit: number;
}
```

Pass `signal` to `fetch` so stale requests are cancelled, honour `limit`, and throw on failure (the error lands in `state.errors`). For example:

```js
const geocoder = {
  name: "Example geocoder",
  async search(query, { signal, bbox, limit }) {
    const url = new URL("https://geocoder.example.com/search");
    url.searchParams.set("q", query);
    url.searchParams.set("limit", String(limit));
    if (bbox) url.searchParams.set("viewbox", bbox.join(","));
    const res = await fetch(url, { signal, credentials: "omit" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const found = await res.json();
    return found.features.map((f) => ({
      provider: this.name,
      label: f.properties.name,
      lngLat: { lng: f.geometry.coordinates[0], lat: f.geometry.coordinates[1] },
    }));
  },
};

const search = createSearch(map, { providers: [coordinates(), geocoder] });
```

An external API's terms of use, rate limits and the attribution it requires are the page's responsibility. The showcase in `examples/shared/search.js` has `gsiPlaceSearch`, a provider for the Geospatial Information Authority of Japan's place search, as an example of the shape; that API has no published terms of use and is meant mainly for GSI's own map site, so it is off unless the page is opened with `?gsi-search=1`.
