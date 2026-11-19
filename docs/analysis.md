# Spatial analysis: `mbt-map/table` and `mbt-map/analysis`

Spatial analysis runs in a Web Worker of its own, on the tables of `mbt-map/table`: what [`read`](./data.md) gives, or GeoJSON taken in with `fromGeoJSON`. A table's rows stay in the worker together with their spatial index, and its methods return only results: typed arrays, new tables, or GeoJSON when you ask for it. `mbt-map/analysis` has what is not a table: elevation grids, coordinate transforms and class breaks. (Until the table surface is settled it also exports the earlier names: `Table` is `Table`, and `load` is `fromGeoJSON`, which also reads a table again.)

```js
import { fromGeoJSON } from "mbt-map/table";

const blocks = await fromGeoJSON(polygonsGeoJSON);      // an object, UTF-8 bytes or an http(s) URL
const shops = await fromGeoJSON("/data/shops.geojson");
const area = await blocks.areas();               // Float64Array, square meters
const counted = await blocks.spatialJoin(shops, { rollup: { count: ["count"], mean: ["mean", "sales"] } });
blocks.dispose();
shops.dispose();
```

All methods are asynchronous and return Promises, except the classification functions and `distance`.

A table's attribute operations (`filter`, `derive`, `groupby`, `rollup`, `join`), its spatial joins and how it is read, written and drawn are in [data.md](./data.md). Coming from 0.1's `load` and `Dataset`: [migrating.md](./migrating.md).

## Contents

- [Loading data](#loading-data)
- [Measures and spatial index](#measures-and-spatial-index)
- [Spatial relations (DE-9IM)](#spatial-relations-de-9im)
- [Geometry operations](#geometry-operations)
- [Shapes](#shapes)
- [Surfaces and clusters](#surfaces-and-clusters)
- [Routing](#routing)
- [Coordinate systems](#coordinate-systems)
- [Terrain](#terrain)
- [Classification and statistics](#classification-and-statistics)
- [Files, workers and lifetime](#files-workers-and-lifetime)

## Loading data

```ts
fromGeoJSON(data: unknown, options?: LoadOptions): Promise<Table>
```

`data` can be:

| Input | Notes |
|---|---|
| A GeoJSON object | A Feature, FeatureCollection or geometry. It is serialized and copied to the worker. |
| `ArrayBuffer` or typed array | GeoJSON as UTF-8 bytes. The bytes are copied, so your buffer stays usable. |
| A string | An http(s) URL, resolved against the page and fetched in the worker without credentials. |

`options.crs` gives the CRS of the input's coordinates (default EPSG:4326). Coordinates are converted to longitude and latitude as they load, so a table is always held in EPSG:4326. See [Coordinate systems](#coordinate-systems).

`Table.length` is the number of features and `Table.columns` the property keys. A GeometryCollection counts once per member.

```js
import { read } from "mbt-map/table";

const wards = await read("/data/wards.zip");     // a zipped Shapefile, reprojected from its .prj
const areas = await wards.areas();               // the same table: its rows move into the worker here
```

## Measures and spatial index

| Method | Result |
|---|---|
| `areas()` | `Float64Array`: each feature's area in m² (0 for points and lines). |
| `lengths()` | `Float64Array`: each feature's length in meters, rings included (0 for points). |
| `centroids()` | `Float64Array` of x, y pairs: the mean of each feature's points, as Turf's `centroid`. |
| `bboxes()` | `Float64Array`: min x, min y, max x, max y per feature. |
| `search(bbox)` | `Int32Array`: indices of the features whose boxes meet `bbox` (`[minX, minY, maxX, maxY]` in degrees). |
| `nearest(x, y, { k, maxDistance })` | `Int32Array`: up to `k` (default 1) features nearest to (x, y), nearest first. The distance is the distance to the feature's box, in degrees. |
| `pointsWithin(polygons)` | `Int32Array`: this table's point features that lie inside some polygon of `polygons`. A point on a boundary counts as inside. |
| `grid(bbox, cols, rows)` | `Int32Array`: point counts in a `cols` × `rows` grid over `bbox`, row by row from the south edge. |

Measures and point-in-polygon tests give the same values as Turf.js 7.4.0. Index searches return features in the same order as flatbush 4.6.2.

The module-level function `distance(from, to)` returns the great-circle distance in meters between two `[lng, lat]` points on Turf's sphere. It runs synchronously on the main thread and starts no worker.

## Spatial relations (DE-9IM)

These are a port of JSTS 2.12.1's `RelateOp`, so matrices and predicates come out the same as in JTS. The module (`relate.wasm`) is fetched on the first call. Longitude and latitude are treated as a plane.

```ts
relate(other: Table, relation: Relation | { pattern: string }): Promise<Int32Array>
relateMatrix(other: Table, i: number, j: number): Promise<string>
```

- `spatialJoin` and `nearestJoin` ([data.md](./data.md#spatial-joins)) give a table of the related rows with both tables' columns, or aggregates of them per row; `relate` is the pairs themselves.
- `relate` returns the pairs of feature `i` in this table and feature `j` in `other` that satisfy `relation`, as a flat `Int32Array` `[i0, j0, i1, j1, ...]` sorted by `i`, then `j`.
- `relation` is one of `"intersects"`, `"contains"`, `"within"`, `"covers"`, `"coveredBy"`, `"touches"`, `"crosses"`, `"overlaps"` or `"equals"` (JTS's `equalsTopo`). It can also be a DE-9IM pattern such as `{ pattern: "T*F**FFF*" }`.
- Only pairs whose bounding boxes meet are tested. So `disjoint` isn't offered, and a pattern that disjoint pairs would match (all four interior/boundary cells `F` or `*`) is refused.
- `relateMatrix` returns the DE-9IM matrix of one pair in JTS's notation, for example `"FF2F11212"`.

```js
const parks = await fromGeoJSON(parksGeoJSON);
const stations = await fromGeoJSON(stationsGeoJSON);
const pairs = await parks.relate(stations, "contains");   // [park, station, park, station, ...]
const m = await parks.relateMatrix(stations, pairs[0], pairs[1]);
```

## Geometry operations

These are a port of Clipper2 2.0.1, with results identical to the C++ library. The module (`geometry.wasm`) is fetched on the first call. Each operation returns a new `Table`.

| Method | What it does |
|---|---|
| `buffer(meters, { mode, join, cap, arcTolerance, crs })` | Grows each feature by `meters` into polygons. A negative distance shrinks polygons and leaves points and lines without geometry (as Turf's `buffer`, which gives nothing for them). Properties are kept. A feature that vanishes keeps its row without geometry. |
| `dissolve({ by })` | Merges all polygons into one feature without properties. With `by` (a column's name or names), one feature per group of rows with equal values there, holding those columns; a group without polygons has no geometry. Lines and points are left out. |
| `clip(other)` | Cuts this table's features to the area of `other`'s polygons. Lines stay lines, points are kept or dropped. Properties are kept. |
| `erase(other)` | Removes the area of `other`'s polygons from this table's features. Properties are kept. |
| `intersect(other)` | One feature per overlap of a feature here with a polygon of `other`, carrying the properties of both. Keys of `other` that also exist here get the suffix `_2`. |
| `split(lines)` | Splits each feature by the lines of `lines`. A polygon splits where a line crosses it from edge to edge, a line where they cross. The pieces keep the original properties. |
| `merge()` | Makes all features one feature with the first one's properties: polygons are united, lines are joined end to end, points become a MultiPoint. Rejects when the geometry kinds differ. |
| `toGeoJSON({ crs })` | The table as a GeoJSON FeatureCollection, built in the worker. Pass `crs` to get coordinates in that CRS. Feature ids are not kept. |

`buffer` options:

| Option | Values | Default |
|---|---|---|
| `mode` | `"geodesic"`: distance on the ground (a per-feature azimuthal equidistant plane fitted to the ellipsoid's two radii of curvature). `"planar"`: distance in a projected CRS's plane. | `"geodesic"` |
| `join` | `"round"`, `"miter"`, `"square"`, `"bevel"` | `"round"` |
| `cap` | Line ends: `"round"`, `"butt"`, `"square"` | `"round"` |
| `arcTolerance` | How far round edges may stray from a true arc, in meters | distance / 500 |
| `crs` | The CRS a planar buffer is measured in | EPSG:3857 |

Distances: `meters` must be a finite number. A geodesic buffer takes at most 10,000 km (`10_000_000`, a quarter of a meridian); a larger one rejects with `a geodesic buffer takes at most 10,000 km`. A point's circle is within millimeters of the distance at 1 km, 2 m at 50 km, 0.1% at 1,000 km and 0.6% at 10,000 km (measured with GeographicLib). A geodesic buffer's longitudes stay within ±180: one that crosses the antimeridian is cut there into the parts of a MultiPolygon (RFC 7946 §3.1.9), and one that holds a pole runs along ±180 up to the pole's latitude and across it, so planar tools fill the cap. The cut parts are on a 1e-7° grid (about 1 cm); buffers that are not cut are unchanged. A planar buffer takes up to 1e9 of the CRS's units.

```js
const roads = await fromGeoJSON(roadsGeoJSON);
const corridor = await roads.buffer(50, { cap: "butt" });
const zone = await corridor.dissolve();
const inside = await (await fromGeoJSON(buildingsGeoJSON)).clip(zone);
map.getSource("result").setData(await inside.toGeoJSON());
```

For [mbt-map/draw](./draw.md) there are two helpers that work directly on GeoJSON features. They load the features, run the operation and dispose of everything:

- `splitFeatures(features, line, options?)`: the features split by `line` (a LineString geometry), as `Table.split`.
- `mergeFeatures(features, options?)`: the features merged into one, as `Table.merge`.

## Shapes

These are ports of Turf.js 7.4.0, concaveman 2.0.0 and d3-delaunay 6.0.6, producing the same coordinates. The module (`shapes.wasm`) is fetched on the first call. Longitude and latitude are treated as a plane, except `nearestPointOnLine` and `lineSlice`, which are spherical as in Turf.

| Method | Result |
|---|---|
| `simplify({ tolerance, highQuality })` | A `Table` with each feature simplified as Turf's `simplify` does: radial distance, then Douglas-Peucker. `tolerance` is in degrees (default 1). `highQuality` skips the radial pass. Properties are kept. |
| `convexHull()` | A `Table` with one polygon around every vertex (Turf's `convex`), or no feature when there are fewer than three points. |
| `concaveHull({ concavity, lengthThreshold })` | concaveman's concave hull as one polygon. `concavity` defaults to 2 (1 gives the tightest hull). Edges shorter than `lengthThreshold` degrees (default 0) stay. |
| `delaunay()` | A `Table` of the Delaunay triangles of the points, as polygons, in d3-delaunay's order. |
| `voronoi(bbox)` | Each point's Voronoi cell cut to `bbox`, with that point's properties. A duplicate point keeps its row without geometry. |
| `nearestPointOnLine(x, y)` | For each feature, the point on its lines nearest to (x, y): `{ point, dist, location, index, multiFeatureIndex }`, or `null` for features without lines. `dist` (distance) and `location` (distance along the line) are in kilometers. |
| `lineSlice(start, stop)` | A `Table` with each line cut between the points nearest to `start` and `stop` (`[lng, lat]`), as Turf's `lineSlice`. |

Use `split(lines)` (in [Geometry operations](#geometry-operations)) to split lines by other lines.

## Surfaces and clusters

These are ports of Turf.js 7.4.0 and d3-contour 4.0.3, producing the same coordinates, values and clusters. The module (`surface.wasm`) is fetched on the first call. Distances are in kilometers, as in Turf.

**Grids** are made by the module-level function `grid`. Don't confuse it with the `Table.grid` method above, which counts points.

```ts
grid(bbox: BBox, cellSide: number, type?: "square" | "point" | "hex" | "triangle", options?: { triangles?: boolean }): Promise<Table>
```

`grid` returns a `Table` of cells covering `bbox`: Turf's `squareGrid` (the default), `pointGrid`, `hexGrid` or `triangleGrid`. With `type: "hex"`, `triangles: true` splits each hexagon into six triangles. Grids are capped at one million cells. To aggregate points per hexagon, call `collect` on the grid:

```js
import { fromGeoJSON, grid } from "mbt-map/table";

const hexes = await grid([139.68, 35.62, 139.83, 35.74], 0.5, "hex");
const points = await fromGeoJSON(pointsGeoJSON);
const counted = await hexes.spatialJoin(points, { rollup: { count: ["count"] } });   // the hexes, with a count column
```

**Table methods:**

| Method | Result |
|---|---|
| `interpolate(cellSize, { gridType, property, weight })` | A grid over the points' box, each cell holding `property` (default `"elevation"`) interpolated by inverse distance weighting, as Turf's `interpolate`. `gridType` is `"square"` (default), `"point"`, `"hex"` or `"triangle"`. `weight` is the distance power (default 1). Turf's `mask` isn't supported. |
| `isolines(breaks, { zProperty })` | Lines where a grid of points (from `grid(..., "point")` or `interpolate`) crosses each value in `breaks` (Turf's `isolines`). `zProperty` defaults to `"elevation"`. |
| `isobands(breaks, { zProperty })` | Polygons between consecutive `breaks` (Turf's `isobands`). Lines or bands that meet no cell become rows without geometry. |
| `density({ bbox, width, height, cellSize, bandwidth, thresholds, weight })` | Contours of kernel density as d3-contour's `contourDensity` draws them, computed on a `width` × `height` pixel grid over `bbox` (default: the points' box). Each contour is a MultiPolygon with its density in `value`. `weight` names a property. The defaults are d3's: 960 × 500, `cellSize` 4, `bandwidth` √420, 20 `thresholds`. |
| `dbscan(maxDistance, { minPoints })` | Turf's `clustersDbscan`: the table with the columns `cluster` (a point's cluster; missing for noise) and `dbscan` (`"core"`, `"edge"` or `"noise"`). Rows that aren't points get neither. `minPoints` defaults to 3. |
| `kmeans(k?)` | Turf's `clustersKmeans`: the table with the columns `cluster` and its centroid's `centroid_x` and `centroid_y`. `k` defaults to round(√(n/2)). Rows that aren't points get none. |

```js
const samples = await fromGeoJSON(samplePointsGeoJSON);
const surface = await samples.interpolate(0.2, { gridType: "point", property: "pm25" });
const bands = await surface.isobands([0, 10, 20, 35, 55], { zProperty: "pm25" });
```

## Routing

This is a port of geojson-path-finder 2.1.0, producing the same paths and weights. The module (`route.wasm`) is fetched on the first call.

```ts
Table.network({ tolerance?: number, snap?: number }): Promise<Network>
Network.route(from: [number, number], to: [number, number]): Promise<{ path: [number, number][]; weight: number } | null>
Network.dispose(): void
```

- `network` builds a routable graph from the table's lines (LineString, plus each line of a MultiLineString) and keeps it in the worker.
- `tolerance` (degrees, default `1e-5`): vertices closer than this are treated as the same vertex.
- `snap` (meters, default 0, off): first nodes the lines so that nearly-touching data still connects. A line end within `snap` of another line's segment is joined to that segment at its nearest point, and ends within `snap` of each other become one vertex. This joins T-junctions and lines cut at tile edges that are slightly off.
- `route` returns the shortest path between two vertices of the network (matched within `tolerance`): `path` holds the coordinates and `weight` the length in kilometers. It returns `null` when the points aren't connected or aren't vertices. You can call it as many times as you like.
- `dispose()` frees the network in the worker.

```js
const roads = await fromGeoJSON(roadsGeoJSON);
const net = await roads.network({ snap: 2 });
const r = await net.route([139.7671, 35.6812], [139.7454, 35.6586]);
if (r) console.log(`${r.weight.toFixed(2)} km`, r.path);
net.dispose();
```

Roads from vector tiles arrive cut at tile edges. `map.querySourceFeatures` gives each feature the tile it came from, which helps to assemble them (see [map.md](./map.md)), and `snap` joins the cut ends.

## Coordinate systems

Every CRS argument in `mbt-map/analysis` and `mbt-map/data` (`crs` options, `transform`) takes a `Crs`:

- An EPSG code: `6677`, `"EPSG:6677"` or `"urn:ogc:def:crs:EPSG::6677"`.
- `"CRS84"`, which is the same as EPSG:4326.
- A PROJ string such as `"+proj=lcc +lat_0=46.5 ..."`, in the form epsg.io publishes.
- In `mbt-map/analysis`, a name registered with `defineCrs(name, projString)`, which works like `proj4.defs`. A registered name overrides a known EPSG code of the same name.

```js
import { defineCrs, transform } from "mbt-map/analysis";

defineCrs("EPSG:2154", "+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +units=m +no_defs");
const xy = await transform([139.7671, 35.6812], 4326, 6677);  // Float64Array [x, y]
```

`transform(coords, from, to)` converts a flat array `[x, y, x, y, ...]` and returns a `Float64Array`. Points a projection can't reach become NaN. The coordinate system module (`proj.wasm`) is fetched the first time a CRS other than EPSG:4326 is used, and the PROJ string parser (`projstring.js`) the first time a PROJ string is given.

**EPSG codes known without a PROJ string:**

| Kind | Codes |
|---|---|
| Geographic | 4326 (WGS 84), 4612 (JGD2000), 6668 (JGD2011), 4301 (Tokyo datum) |
| Web Mercator | 3857 (also 3785, 900913) |
| Japan Plane Rectangular CS I–XIX | 6669–6687 (JGD2011), 2443–2461 (JGD2000), 30161–30179 (Tokyo datum) |
| UTM | 32601–32660, 32701–32760 (WGS 84); 6688–6692 (JGD2011, zones 51–55); 3097–3101 (JGD2000); 3092–3096 (Tokyo datum) |

**Projections** usable in PROJ strings: `longlat`, `merc`, `tmerc` (`etmerc`), `utm`, `lcc`, `aea`, `aeqd`, `stere`, `sterea`, `cass`, `laea`, `eqc`, `eqdc`, `sinu`, `eck6`, `moll`, `robin`, `cea`, `mill`, `poly`, `omerc`, `somerc`, `krovak`, `ortho`, `gnom`, `eqearth`, `bonne`.

**Datum shifts** go through WGS 84, using `+towgs84` (3 or 7 parameters) or `+datum` (`WGS84`, `NAD83`, `potsdam`, `OSGB36`, `ch1903` and the other names proj4js knows). The Tokyo datum uses EPSG's 3-parameter shift (-146.414, 507.337, 680.507). Grid shifts (`+nadgrids`, TKY2JGD) are not supported. JGD2000, JGD2011 and WGS 84 are treated as the same datum.

Results agree with proj4js 2.22.0 to within 1 mm. Where proj4js is plainly wrong (the `+R_A` radius, false origins of some projections), the port follows PROJ.

## Terrain

### DEM tiles

```ts
loadDem(tiles: string, { zoom, bounds, encoding }): Promise<DemGrid>
sampleDem(tiles: string, positions: [number, number][], { encoding, maxZoom, tileSize }?): Promise<Float64Array>
```

- `loadDem` mosaics the elevation tiles of `tiles`, an http(s) `{z}/{x}/{y}` template, that cover `bounds` at `zoom` into a single `DemGrid`. The grid snaps outward to whole tiles. A tile the server doesn't have (404) counts as 0 m.
- `encoding` is `"mapbox"` (default), `"terrarium"`, `"gsi"` (GSI's elevation PNG tiles) or custom factors `{ redFactor, greenFactor, blueFactor, baseShift }`.
- `sampleDem` reads the tiles around `positions` at the deepest zoom (up to `maxZoom`, default 14, at most 24) whose tiles fit one grid, and returns the elevation at each position, sampled like `DemGrid.sample`. It refuses areas needing more than 16 tiles a side (at 256 px) before fetching anything. `tileSize` is 256 to 4096.

```js
import { loadDem, sampleDem } from "mbt-map/analysis";

// GSI elevation tiles. Source: Geospatial Information Authority of Japan (国土地理院).
const DEM = "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png";

const grid = await loadDem(DEM, { zoom: 14, bounds: [138.70, 35.33, 138.76, 35.39], encoding: "gsi" });
const slope = await grid.slope();
const heights = await sampleDem(DEM, [[138.7274, 35.3606], [138.75, 35.37]], { encoding: "gsi" });
```

### `DemGrid`

A grid of elevations in the worker, stored row by row from the north.

| Member | Result |
|---|---|
| `width`, `height` | Cells. |
| `bounds` | `[west, south, east, north]` of the whole tiles it covers. |
| `elevations()` | `Float64Array` in meters; NaN where the DEM has no data. |
| `slope()` | `Float64Array`: slope in degrees (gdaldem's Horn method). |
| `aspect()` | `Float64Array`: degrees clockwise from north, facing downhill; NaN where flat. |
| `hillshade({ azimuth, altitude, zFactor })` | `Uint8Array` of shades from 1 to 255, as gdaldem's hillshade. Defaults: `azimuth` 315, `altitude` 45, `zFactor` 1. |
| `sample(positions)` | `Float64Array`: the elevation at each `[lng, lat]`, interpolated bilinearly between cell centers as GDAL's `-r bilinear`. NaN off the grid or next to a cell without data. |
| `viewshed(observer, options)` | What can be seen from `observer`, see below. |
| `lineOfSight(from, to, options)` | Whether `to` is visible from `from`, see below. |
| `dispose()` | Frees the grid. |

Slope, aspect and hillshade follow the same formulas as GDAL's `gdaldem`. DEM grids are measured in ground meters at the grid's middle latitude.

### GeoTIFF grids

```ts
loadGrid(raster: GridRaster, { band, scale }?): Promise<DemGrid>
```

`loadGrid` turns a band (default 0) of a raster read by `mbt-map/data`'s `readRaster` into a `DemGrid`. Cells equal to `noData` hold no value. The cell size is the resolution divided by `scale` (gdaldem's `-s`). For a raster in degrees with elevations in meters, pass `scale: 111120`. A raster whose GeoKeys say PixelIsPoint is placed with pixel centers on the tie points, as GDAL does. `sample` still takes longitude and latitude, converted to the raster's CRS through `proj.wasm`. Grids are capped at 4096 cells a side.

```js
import { readRaster } from "mbt-map/data";
import { loadGrid } from "mbt-map/analysis";

const dem = await readRaster("https://example.com/dem-cog.tif", { bbox: [138.7, 35.3, 138.8, 35.4] });
const grid = await loadGrid(dem, { scale: 111120 });
const shade = await grid.hillshade({ azimuth: 315, altitude: 45 });
```

### Viewshed

```ts
DemGrid.viewshed(observer: [number, number], options?: ViewshedOptions): Promise<ViewshedResult>
```

This is a port of GDAL 3.13's `gdal_viewshed`. The module (`viewshed.wasm`) is fetched on the first call. The options mirror gdal_viewshed's flags:

| Option | gdal_viewshed | Default |
|---|---|---|
| `observerHeight` | `-oz` | 2 m above the ground |
| `targetHeight` | `-tz` | 0 m |
| `maxDistance` | `-md` | 0 (no limit) |
| `curvatureCoeff` | `-cc` | 0.85714 |
| `mode` | `-om` | `"normal"` |
| `visibleValue`, `invisibleValue`, `outOfRangeValue` | `-vv`, `-iv`, `-ov` | 255, 0, 0 |

With `mode: "normal"`, each cell holds one of the three values. With `"dem"` or `"ground"`, each cell holds the height a target there must reach to be seen, above sea level or above the ground. The result is `{ width, height, bounds, values }`, where `values` is a `Float64Array` row by row from the north, cut to `maxDistance`. A GeoTIFF grid must be in a projected CRS.

### Line of sight on a DEM

```ts
DemGrid.lineOfSight(from, to, { observerHeight, targetHeight, curvatureCoeff, samples }?): Promise<{ visible: boolean; blockedAt: [number, number] | null }>
```

The grid is sampled bilinearly along the line (by default one sample per cell, `samples` up to 100 000). Each sample is lowered for the earth's curvature as gdal_viewshed does. `blockedAt` is the first sample that hides the target. For line of sight over buildings and 3D layers on the map, see `lineOfSight` in [3d.md](./3d.md).

```js
const seen = await grid.viewshed([138.7274, 35.3606], { maxDistance: 5000 });
const los = await grid.lineOfSight([138.7274, 35.3606], [138.75, 35.37], { observerHeight: 1.6 });
```

## Classification and statistics

These run on the main thread and start no worker. They are ports of simple-statistics 8.0.0 and geostats 2.1.0, producing the same values.

```ts
classBreaks(values: ArrayLike<unknown>, classes: number, method?: ClassMethod, { matchBounds }?): number[] | null
classStep(input: unknown, breaks: number[], outputs: unknown[]): unknown[]
statistics(values: ArrayLike<unknown>): Statistics | null
```

- `classBreaks` returns `classes + 1` ascending break values. Values that aren't finite numbers are ignored. It returns `null` when there are no values or more classes than values (for jenks, more classes than distinct values).
- `method`:

  | Method | Classes |
  |---|---|
  | `"jenks"` (default) | Natural breaks (Fisher-Jenks). |
  | `"ckmeans"` | Optimal 1-D k-means. |
  | `"quantile"` | Equal counts. |
  | `"equalInterval"` | Equal widths. |
  | `"standardDeviation"` | One standard deviation per class around the mean, in geostats' layout. `matchBounds: true` sets the outer breaks to the minimum and maximum. |

- Limits: at most `MAX_CLASS_VALUES` (1 000 000) values and `MAX_CLASSES` (256) classes. `jenks` and `ckmeans` also refuse inputs whose work exceeds `MAX_JENKS_WORK` and `MAX_CKMEANS_CELLS`.
- `statistics` returns `{ count, min, max, sum, mean, median, variance, standardDeviation }` of the finite values: a compensated sum, and the population variance and standard deviation. It returns `null` when there are none.
- `classStep` builds a style expression `["step", input, outputs[0], breaks[1], outputs[1], ...]`, one output per class. The legend in [mbt-map/ui](./ui.md) lists such an expression as one entry per class.

```js
import { classBreaks, classStep, statistics } from "mbt-map/analysis";

const values = features.map((f) => f.properties.population);
const breaks = classBreaks(values, 5, "jenks");
map.setPaintProperty("blocks", "fill-color",
  classStep(["get", "population"], breaks, ["#f1eef6", "#bdc9e1", "#74a9cf", "#2b8cbe", "#045a8d"]));
console.log(statistics(values));
```

## Files, workers and lifetime

The first call that needs the worker starts `analysis-worker.js` and `analysis.wasm`. The other modules are fetched on first use:

| File | Fetched on the first |
|---|---|
| `geometry.wasm` | `buffer`, `dissolve`, `clip`, `erase`, `intersect`, `split`, `merge` |
| `relate.wasm` | `relate`, `relateMatrix` |
| `shapes.wasm` | `simplify`, hulls, `delaunay`, `voronoi`, `nearestPointOnLine`, `lineSlice` |
| `surface.wasm` | `grid`, `interpolate`, `isolines`, `isobands`, `density`, `dbscan`, `kmeans` |
| `route.wasm` | `network` |
| `viewshed.wasm`, `analysis-viewshed.js` | `viewshed` |
| `proj.wasm` | CRS other than EPSG:4326 |
| `projstring.js` | PROJ string (always loaded from next to `analysis.js`) |

By default every file is loaded from next to `analysis.js`. The options of the first call can point elsewhere: `workerUrl`, `wasmUrl`, `geometryWasmUrl`, `relateWasmUrl`, `shapesWasmUrl`, `surfaceWasmUrl`, `viewshedWasmUrl`, `routeWasmUrl` and `projWasmUrl`. See [getting-started.md](./getting-started.md) for serving the files with a bundler.

- `Table.dispose()`, `DemGrid.dispose()` and `Network.dispose()` free their data in the worker. Later calls on them reject.
- `terminate()` stops the worker. Every table, grid and network is lost and pending calls reject. The next call starts a fresh worker.
