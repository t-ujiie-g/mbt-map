# Migrating from 0.1 to 0.2

0.2 makes reading, analysis and display one surface: a table. `mbt-map/data`'s `DataTable` and `mbt-map/analysis`'s `Dataset` are one type, `Table`, in the new entry `mbt-map/table`. What `read` gives is analysed and drawn as it is, and operations return tables.

```js
// 0.1
import { read } from "mbt-map/data";
import { load } from "mbt-map/analysis";

const data = await read("/data/wards.zip");
const wards = await load(data);
const { count } = await wards.collect(await load(stations), "riders");
map.addSource("wards", { type: "geojson", data: data.toGeoJSON() });

// 0.2
import { fromGeoJSON, read } from "mbt-map/table";

const wards = await read("/data/wards.zip");
const counted = await wards.spatialJoin(await fromGeoJSON(stations), { rollup: { count: ["count"], riders: ["sum", "riders"] } });
map.addSource("wards", { type: "geojson", data: counted });
```

## What moved

| 0.1 | 0.2 |
|---|---|
| `read`, `parse`, `write`, `formatOf` from `mbt-map/data` | The same names from `mbt-map/table`. |
| `DataTable` (`mbt-map/data`), `Dataset` (`mbt-map/analysis`) | `Table` (`mbt-map/table`). |
| `load(geojson, options)` | `fromGeoJSON(geojson, options)`. |
| `load(dataTable)` | Not needed: what `read` gives is the table. Its rows move into the analysis worker on its first operation. |
| `grid`, `defineCrs`, `Network` from `mbt-map/analysis` | Also from `mbt-map/table` (`mbt-map/analysis` still exports them). |
| `readRaster`, `rasterInfo`, `rasterTile`, `reprojectTile` | Unchanged, in `mbt-map/data`. |
| `loadDem`, `loadGrid`, `sampleDem`, `DemGrid`, `transform`, `distance`, `classBreaks`, `classStep`, `statistics`, `splitFeatures`, `mergeFeatures` | Unchanged, in `mbt-map/analysis`. |

`mbt-map/data` is now only rasters, and `mbt-map/analysis` only what is not a table.

## What changed

| 0.1 | 0.2 |
|---|---|
| `dataTable.toGeoJSON()` returns the object | `table.toGeoJSON()` returns a Promise of it. Or pass the table itself as a GeoJSON source's `data`. |
| `dataTable.tableBytes()` | Gone: pass the table to what took the bytes. `table.toArrowIPC()` gives bytes other tools read. |
| `dataset.collect(points, property)` gives `{ count, numbers, sum, mean }` arrays | `table.spatialJoin(points, { rollup: { count: ["count"], sum: ["sum", property], mean: ["mean", property] } })` gives the table with those columns. The predicate is `"intersects"` (a point on a boundary counts, as before). |
| `dataset.dbscan(...)` gives `{ clusters, kinds }` | `table.dbscan(...)` gives the table with the columns `cluster` and `dbscan`. |
| `dataset.kmeans(k)` gives `{ clusters, centroids }` | `table.kmeans(k)` gives the table with the columns `cluster`, `centroid_x` and `centroid_y`. |
| `dataset.dissolve()` | Unchanged; `dissolve({ by })` merges per group. |
| A source's `data` is GeoJSON or a URL | It may also be a `Table` (`getStyle()` and `getData()` then give the table back; `updateData` needs GeoJSON). |

Methods that return numbers or row numbers (`areas`, `lengths`, `centroids`, `bboxes`, `search`, `nearest`, `pointsWithin`, `relate`, `grid`) are unchanged. Their results now fit the new methods: `table.filter(await table.search(bbox))` keeps those rows, and `table.derive({ area: await table.areas() })` makes a column.

## What is new

- Attribute operations, named as Arquero's: `select`, `filter`, `derive`, `orderby`, `slice`, `groupby(...).rollup(...)`, `join`, `array`, `columnTypes`. Conditions and computed values are style expressions.
- Spatial joins: `spatialJoin` and `nearestJoin`.
- Arrow IPC (`fromArrow`, `toArrowIPC`, Feather files) and GeoParquet (`read`, with `bbox` and `columns` by range requests), LZ4 and ZSTD included.

[data.md](./data.md) has each of them.

## Files

Pages that serve the library's files themselves have new ones beside `data.js` and `analysis.js`: `table.js`, `clients.js`, `table.wasm`, `arrow.wasm`, `parquet.wasm`, `zstd.wasm` and `data-arrow.js`, each fetched only when first needed. A bundler or a CDN needs no change.
