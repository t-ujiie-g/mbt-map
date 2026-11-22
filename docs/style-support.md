# Style support

mbt-map draws styles that follow the MapLibre style specification (version 8), and draws them as MapLibre GL JS 6.16 does: the repository compares the two pixel by pixel on a set of scenes. This page lists which sources, layers, properties and expressions are drawn, mbt-map's own extensions, and how the parts that are not drawn are reported. For the methods that change a style at runtime, see [The map](./map.md#changing-the-style-at-runtime).

- [What happens to what is not drawn](#what-happens-to-what-is-not-drawn)
- [Sources](#sources)
- [Layers](#layers)
- [Expressions](#expressions)
- [Images and patterns](#images-and-patterns)
- [Terrain, sky, globe and lights](#terrain-sky-globe-and-lights)
- [mbt-map extensions](#mbt-map-extensions)
- [Not supported](#not-supported)

## What happens to what is not drawn

When a style uses a property, expression, layer or source that mbt-map does not draw yet:

- By default the map leaves it out and draws the rest: a property falls back to its default, and a layer (or source) that still cannot be drawn is dropped. Each item is logged with `console.warn` and reported by a `warning` event, whose `warnings` list `{ path, layer, message }`, with the JSON path in the style (`layers[3].paint.line-blur`) and the reason.
- With the map option `strict: true`, such a style is refused: a style object makes the constructor (or `setStyle`) throw, a style URL fires `error`.
- Invalid values (a misspelled enum value, a value of the wrong type, `minzoom` above `maxzoom`) are always refused that way, with or without `strict`.

```ts
map.on("warning", (e) => {
  for (const w of e.warnings ?? []) console.log(w.path, w.layer, w.message);
});
```

The repository's `npm --prefix bench run style:compat` lists what is left out of a set of public styles (OpenMapTiles-based ones, OpenFreeMap, Protomaps basemaps and others).

Layers with `visibility: "none"` are dropped when the style is parsed: hiding a layer is a removal, and showing it parses it again.

## Sources

| Type | Supported |
|---|---|
| `vector` | `tiles` (`{z}/{x}/{y}` templates, http(s) or relative), `minzoom`, `maxzoom`, `bounds` (tiles outside are not requested), `scheme: "tms"`, `promoteId` (a string or an object per source layer), `attribution`. |
| `raster` | As `vector`, plus `tileSize` 128, 256 or 512 (default 512). |
| `raster-dem` | `tiles`, `tileSize`, `encoding`: `"mapbox"` (default), `"terrarium"`, `"custom"` (with `redFactor`, `greenFactor`, `blueFactor`, `baseShift`), and the extension `"gsi"` (below). |
| `geojson` | `data` (an object or an http(s) URL), `maxzoom`, `buffer`, `tolerance`, `lineMetrics`, `promoteId`, `cluster`, `clusterRadius`, `clusterMaxZoom`, `clusterMinPoints`, `clusterProperties`. The tiles are the same as geojson-vt cuts. |
| `image` | `url`, `coordinates`. |
| `video` | `urls`, `coordinates`. Played muted and looping. |
| `canvas` | `canvas` (an element id, or the element itself through `addSource`), `animate`, `coordinates`. |

- **TileJSON**: a `vector`, `raster` or `raster-dem` source may give `url` instead of `tiles`. The document's `tiles`, `minzoom`, `maxzoom`, `bounds`, `attribution` and the like are read, and values written in the source take precedence.
- **PMTiles**: `url: "pmtiles://https://example.com/tiles.pmtiles"`, with no plugin. The worker reads the directories and tiles by range requests, so the server must answer `Range`. Compression `none` and `gzip`.
- Tile templates take MapLibre's placeholders: `{z}`, `{x}`, `{y}`, `{prefix}`, `{ratio}`, `{quadkey}` and `{bbox-epsg-3857}` (for WMS and ArcGIS `export`).
- Image and canvas pictures that are not rectangles are warped as MapLibre warps them.

## Layers

### background

`background-color`, `background-opacity`, `background-pattern`. A background is drawn where it sits in the layer order: a translucent one above other layers tints them, and extrusion layers above it stay clear. On terrain a `background-pattern` is not drawn.

### fill

`fill-color`, `fill-opacity`, `fill-antialias` and `fill-outline-color` (outlines drawn as MapLibre draws them), `fill-pattern`, `fill-translate`, `fill-translate-anchor`, `fill-sort-key`.

### line

`line-color`, `line-opacity`, `line-width`, `line-gap-width`, `line-offset` (also by feature), `line-blur` (constant or by zoom), `line-dasharray` (constant, by zoom or by feature), `line-gradient` (over `["line-progress"]`; needs a GeoJSON source with `lineMetrics: true`), `line-pattern`, `line-translate`, `line-translate-anchor`, `line-cap`, `line-join`, `line-miter-limit`, `line-round-limit`, `line-sort-key`.

### circle

`circle-color`, `circle-opacity`, `circle-radius`, `circle-blur` (constant or by zoom), `circle-stroke-color`, `circle-stroke-opacity`, `circle-stroke-width`, `circle-pitch-scale`, `circle-pitch-alignment`, `circle-translate`, `circle-translate-anchor`, `circle-sort-key` (drawn in key order across tiles).

### heatmap

`heatmap-radius`, `heatmap-weight`, `heatmap-intensity`, `heatmap-color` (over `["heatmap-density"]`), `heatmap-opacity`. Density is added up in a texture a quarter of the viewport, then colored.

### fill-extrusion

`fill-extrusion-color`, `fill-extrusion-opacity`, `fill-extrusion-height`, `fill-extrusion-base`, `fill-extrusion-vertical-gradient`, `fill-extrusion-pattern`, `fill-extrusion-translate`.

- Lit by the style's `light` (`anchor`, `color`, `intensity`, `position`), or by `lights` when the style has them ([below](#lights)).
- Heights and bases are evaluated per feature; a zoom-and-feature expression is taken at the tile's zoom and one deeper and interpolated between them. Heights range from 0 to 6553.5 m in 0.1 m steps.
- Translucent extrusions show only the nearest surface at each pixel.
- On terrain each building stands on the ground under its centroid.

### raster

`raster-opacity`, `raster-hue-rotate`, `raster-brightness-min`, `raster-brightness-max`, `raster-saturation`, `raster-contrast`, `raster-resampling`. At rest tiles are aligned to the pixel grid. Tiles appear without a fade.

### hillshade

`hillshade-method` (`standard`, `basic`, `combined`, `igor`, `multidirectional`), `hillshade-illumination-direction`, `hillshade-illumination-altitude`, `hillshade-illumination-anchor`, `hillshade-exaggeration`, `hillshade-shadow-color`, `hillshade-highlight-color`, `hillshade-accent-color`. Several light directions (up to 8) for `multidirectional`.

### color-relief

`color-relief-color` (an `interpolate` over `["elevation"]`), `color-relief-opacity`.

### symbol

Text and icons at points and along lines (`symbol-placement`: `point`, `line`, `line-center`).

- Text: `text-field` (the `{key}` form and expressions, `format` included), `text-font`, `text-size`, `text-anchor`, `text-offset`, `text-radial-offset`, `text-variable-anchor`, `text-variable-anchor-offset`, `text-justify`, `text-max-width`, `text-line-height`, `text-letter-spacing`, `text-transform`, `text-rotate`, `text-max-angle`, `text-keep-upright`, `text-padding`, `text-optional`, `text-allow-overlap` and `text-overlap`, `text-ignore-placement`, `text-writing-mode` (its first value; in vertical text CJK characters stand upright, Latin text is turned sideways, brackets and punctuation take their vertical forms), `text-color`, `text-opacity`, `text-halo-color`, `text-halo-width`, `text-halo-blur`, `text-translate`, `text-translate-anchor`.
- Icons: `icon-image`, `icon-size`, `icon-rotate`, `icon-anchor`, `icon-offset`, `icon-padding`, `icon-text-fit`, `icon-text-fit-padding`, `icon-optional`, `icon-allow-overlap` and `icon-overlap`, `icon-ignore-placement`, `icon-rotation-alignment`, `icon-pitch-alignment`, `icon-keep-upright`, `icon-color` and `icon-halo-color`, `icon-halo-width`, `icon-halo-blur` (SDF images), `icon-opacity`, `icon-translate`, `icon-translate-anchor`.
- Placement: `symbol-spacing`, `symbol-sort-key`, `symbol-z-order`, collision as MapLibre's placement.
- **Fonts come from the browser**; glyph PBFs are not used, so a style's `glyphs` URL is not fetched. A `text-font` stack becomes a CSS font family list (its names, then the map's `fontFamily`), with the weight and style taken from the first name (`Bold`, `Light`, `Italic`, …). Without `text-font`, labels use the map's `fontFamily` option (default `sans-serif`).
- When the map is pitched, distant labels are drawn smaller (MapLibre's perspective ratio), and labels beyond five camera distances are not placed. On terrain labels stand on the ground and fade out behind it.

### custom

Custom layers (`type: "custom"`, MapLibre's `CustomLayerInterface`) are added with `addLayer`; see [The map](./map.md#custom-layers).

### All layers

`minzoom`, `maxzoom`, `filter`, `layout.visibility`, `metadata` and `source-layer` are read as the specification says. `*-translate` takes constants and zoom expressions, and feature queries follow it.

## Expressions

Expressions are evaluated as MapLibre 6.16 evaluates them, type annotations included; the repository checks them against `@maplibre/maplibre-gl-style-spec` 26.5.0. Supported operators include:

| Group | Operators |
|---|---|
| Types | `literal`, `array`, `boolean`, `number`, `string`, `to-boolean`, `to-color`, `to-number`, `to-string`, `typeof`, `collator`, `format`, `image`, `number-format` |
| Feature data | `get`, `has`, `in`, `id`, `geometry-type`, `feature-state` (paint only), `line-progress` (only in `line-gradient`), `heatmap-density` (only in `heatmap-color`), `elevation` (only in `color-relief-color`), `accumulated` (in `clusterProperties`) |
| Lookup | `at`, `index-of`, `length`, `slice`, `split`, `join` |
| Decision | `!`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `all`, `any`, `case`, `coalesce`, `match`, `within`, `distance` |
| Ramps | `interpolate` (`linear`, `exponential`, `cubic-bezier`), `interpolate-hcl`, `interpolate-lab`, `step` |
| Variables | `let`, `var`, `global-state` |
| String | `concat`, `downcase`, `upcase`, `is-supported-script`, `resolved-locale` |
| Color | `rgb`, `rgba`, `to-rgba` |
| Math | `+`, `-`, `*`, `/`, `%`, `^`, `abs`, `acos`, `asin`, `atan`, `ceil`, `cos`, `e`, `floor`, `ln`, `ln2`, `log10`, `log2`, `max`, `min`, `pi`, `round`, `sin`, `sqrt`, `tan` |
| Camera | `zoom` |

Notes:

- `number-format` and collators use the browser's `Intl`.
- `format` supports `font-scale`, `vertical-align`, and a section's `text-font` and `text-color`.
- `is-supported-script` is always true, as in MapLibre 6.16.
- `within` and `distance` work in filters, layout, and per-feature paint of fill, line, circle and heatmap layers. They are not supported in the paint of symbol and fill-extrusion layers, or of layers whose paint reads feature state.
- `global-state` reads the style's `state` defaults and the values set by `setGlobalStateProperty`.
- Legacy filters (`["==", "class", "street"]`) and property functions (`{ "stops": [...] }`) are converted to expressions, as MapLibre converts them.
- Expressions are capped at 32 levels of nesting and 4096 nodes once `let` / `var` are expanded.

## Images and patterns

`fill-pattern`, `line-pattern`, `fill-extrusion-pattern`, `background-pattern` and `icon-image` use the style's `sprite` (one URL, or a list of `{ id, url }`; `@2x` on a screen with a device pixel ratio of 2) and images added with `addImage`. A pattern is taken at the integer zoom: there is no cross-fade between zoom levels. A missing image fires `styleimagemissing` once per name.

## Terrain, sky, globe and lights

### Terrain

`terrain` (`source`: a `raster-dem` source, `exaggeration`) drapes the map over the ground. The camera center rises to the ground height, labels are placed at their ground height and hidden behind terrain, and extrusions stand on the ground. Symbols, extrusions and custom layers are drawn on top of the terrain; every other layer is draped over it.

### Sky and fog

The pitch goes up to 85°. Past about 70° the horizon comes on screen; with a `sky` in the style, the sky is drawn above it and terrain fades into fog with distance. `sky-color`, `horizon-color`, `fog-color`, `fog-ground-blend`, `horizon-fog-blend`, `sky-horizon-blend` and `atmosphere-blend` (the glow around the globe) are read, as constants or zoom expressions. Without a `sky`, neither sky, fog nor atmosphere is drawn.

### Projection

`projection.type`: `"mercator"` (default; the world repeats across the antimeridian unless the map's `renderWorldCopies` is false), `"globe"` (a globe up to zoom 11, Mercator from zoom 12, crossing over in between) and `"vertical-perspective"` (always a globe). Layers, terrain and labels are drawn onto the globe. Symbol `*-translate` is not applied on the globe, and extrusions are not hit by queries there.

### Light

`light` (`anchor`, `color`, `intensity`, `position`) lights extrusions. `position` cannot be an expression.

### Lights

`lights` is an mbt-map extension with Mapbox's names (see below).

## mbt-map extensions

### `"encoding": "gsi"` for `raster-dem`

Reads the elevation PNG tiles of 国土地理院 (Geospatial Information Authority of Japan): 0.01 m steps of the 24-bit RGB value, negative past 2^23, no data at 2^23.

```json
{
  "type": "raster-dem",
  "tiles": ["https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png"],
  "tileSize": 256,
  "maxzoom": 14,
  "encoding": "gsi",
  "attribution": "国土地理院 標高タイル"
}
```

### `geotiff` source

A GeoTIFF or Cloud Optimized GeoTIFF, drawn by a `raster` layer, or used as elevation (`hillshade`, `color-relief`, `terrain`) with `dem: true`.

```json
{ "type": "geotiff", "url": "https://example.com/dem-cog.tif", "dem": true }
```

- Files in any CRS with an EPSG code are drawn: EPSG:3857 and EPSG:4326 (and JGD2011 / JGD2000 longitude and latitude) as they are, others (plane rectangular zones, UTM and the other systems [mbt-map/analysis](./analysis.md) knows) by taking each pixel's center to the file's CRS.
- For each tile drawn, only the blocks of the fitting overview are read, by range requests. `bounds` and `maxzoom` come from the file unless the source gives them.
- Colors: 8-bit 3- and 4-band images are RGB and RGBA. A single band (or the first of `bands`) is drawn from black to white over `range` (`[min, max]`; by default the range of the coarsest image), or along `colors` (`[value, color]` pairs, CSS colors) when given. No-data and out-of-range values are transparent. `resampling`: `"nearest"` (default) or `"bilinear"`. `tileSize`: 256 (default) or 512.
- Elevations go through Terrarium PNG, so they are drawn in 1/256 m steps.
- The tiles are made by the worker of [mbt-map/data](./data.md), whose files must be served next to the main entry. `rasterInfo` and `rasterTile` of mbt-map/data give the same information and tiles directly.

### `reprojected` source

WMTS and WMS layers in a CRS other than Web Mercator, drawn by a `raster` layer. These sources are made by `wmtsSource` and `wmsSource` of [mbt-map/services](./services.md) rather than by hand:

```js
{ type: "reprojected", crs: 6677, grid: { template, matrices } } // a WMTS tile matrix set
{ type: "reprojected", crs: 4326, image: { template, northFirst } } // one GetMap per tile
```

`grid.template` has `{TileMatrix}`, `{TileRow}` and `{TileCol}`; each matrix has `id`, `resolution` (CRS units per pixel), the top-left `x` and `y`, the tile `width` and `height`, `cols` and `rows`. `image.template` has `{bbox}`, `{width}` and `{height}`. `tileSize` is 256 (default) or 512; `minzoom`, `maxzoom`, `bounds` and `attribution` as other sources. Each Web Mercator pixel's center is taken to the CRS and sampled nearest from the WMTS tiles of the coarsest matrix still finer than the tile, or from the GetMap image. `transformRequest` is called once with the template, and its headers and credentials go with every request.

### `lights`

An array with an `ambient` and a `directional` light, using Mapbox's property names:

```json
"lights": [
  { "id": "ambient", "type": "ambient", "properties": { "color": "#ffffff", "intensity": 0.5 } },
  { "id": "sun", "type": "directional", "properties": {
      "color": "#fff4e6", "intensity": 0.5, "direction": [210, 30],
      "cast-shadows": true, "shadow-intensity": 0.6 } }
]
```

- `color`, `intensity` (default 0.8); `direction` is `[azimuthal, polar]` in degrees (default `[210, 30]`); `cast-shadows` (boolean) and `shadow-intensity` (a number from 0 to 1, default 1).
- With `lights`, extrusions and the layers of [mbt-map/3d](./3d.md) are lit as ambient plus sun times Lambert instead of by `light`, and custom layers get the colors and the direction. With `cast-shadows`, extrusions and 3D layers cast shadows on each other and on the flat ground while the sun is above the horizon.
- Other light types are reported as unsupported. `timeOfDayLights` in the main entry builds `lights` for a date and place; see [The map](./map.md#lights-the-sun-and-shadows).

### Others

- `metadata["mbt-map:title"]` and `metadata["mbt-map:overlay"]` on layers are read by [mbt-map/ui](./ui.md) (legend titles, overlays kept across basemaps).

## Not supported

These are reported as warnings (or refused with `strict`):

- `object` and `properties` as expressions, and an object argument of `get` or `has` other than `["properties"]`.
- `image` inside `format`.
- Expressions for `symbol-placement`, `text-anchor`, `text-offset`, `icon-offset`, `fill-antialias`, `light.position` and `projection.type`.
- Along lines, `text-pitch-alignment` and `text-rotation-alignment` other than `map` or `auto`, and `text-offset`, `text-radial-offset`, `text-variable-anchor`, `text-variable-anchor-offset`.
- `line-blur` and `circle-blur` that depend on feature data or state.
- A data-driven `line-dasharray` in layers whose paint reads feature state.
- `within` and `distance` in the paint of symbol and fill-extrusion layers, or of layers whose paint reads feature state.
- `symbol-avoid-edges` (not drawn yet).
- Sources without `tiles` or `url` (other than `geojson`, `image`, `video`, `canvas`, `geotiff` and `reprojected`), tile URLs that are not http(s), and `tileSize` values other than 128, 256 and 512 (256 and 512 for `geotiff` and `reprojected`).
- `lights` entries other than `ambient` and `directional`, and a `direction` that is not two numbers.
- Layer types outside the ones listed above.

Other differences in behavior: text at points always faces the viewer (`text-pitch-alignment` and `text-rotation-alignment` are not read for point labels), patterns are not cross-faded between zooms, raster tiles do not fade in, and tiles beyond a source's `maxzoom` are drawn and queried as the source serves them (MapLibre cuts them further).
