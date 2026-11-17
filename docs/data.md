# Reading and writing data: `mbt-map/table` and `mbt-map/data`

`mbt-map/table` reads vector GIS files in a Web Worker of its own. It handles CSV, WKT/EWKT, WKB/EWKB, Shapefile (loose files or a zip), TopoJSON, KML/KMZ, GPX, FlatGeobuf and GeoJSON. Each read returns a `Table` in longitude and latitude, which gives a GeoJSON source its data and has the analysis of [analysis.md](./analysis.md) as methods. The entry point also writes GeoJSON, CSV and KML. `mbt-map/data` reads GeoTIFF and Cloud Optimized GeoTIFF (COG) pixels in the same worker. The worker starts on the first call. Coordinate conversion, KML/GPX and GeoTIFF each ship as a separate module, fetched only the first time they're needed.

```js
import { read, parse, write } from "mbt-map/table";

const stations = await read("/data/stations.csv");    // points from the latitude and longitude columns
map.addSource("stations", { type: "geojson", data: await stations.toGeoJSON() });
const nearest = await stations.nearest(139.767, 35.681); // the table has the analysis as methods

const area = await parse("SRID=4326;POLYGON ((139.76 35.67, 139.775 35.67, 139.775 35.688, 139.76 35.688, 139.76 35.67))", { format: "wkt" });
const wards = await read("/data/wards.zip");           // a zipped Shapefile, reprojected from its .prj
const picked = await read(input.files);                // .shp, .dbf, .prj, .cpg picked with <input type="file" multiple>
const world = await read("/data/world.json", { format: "topojson", layer: "countries" });
const drawing = await read(file);                      // a KML, KMZ or GPX File
const near = await read("https://example.com/buildings.fgb", { bbox: [139.76, 35.67, 139.78, 35.69] });

const csv = await write(stations, { format: "csv" });
```

## Contents

- [Reading](#reading)
- [`Table`](#table)
- [Coordinate systems](#coordinate-systems)
- [Formats](#formats): [CSV](#csv), [WKT and EWKT](#wkt-and-ewkt), [WKB and EWKB](#wkb-and-ewkb), [Shapefile](#shapefile), [TopoJSON](#topojson), [KML and KMZ](#kml-and-kmz), [GPX](#gpx), [FlatGeobuf](#flatgeobuf), [GeoJSON](#geojson)
- [Writing](#writing)
- [GeoTIFF and COG](#geotiff-and-cog)
- [The `geotiff` style source](#the-geotiff-style-source)
- [Limits](#limits)
- [Files, workers and lifetime](#files-workers-and-lifetime)

## Reading

```ts
read(input, options?: ReadOptions): Promise<Table>
parse(text: string, options: ReadOptions & { format: DataFormat }): Promise<Table>
```

`read` accepts:

| Input | Notes |
|---|---|
| A string or `URL` | Always treated as an http(s) URL. It is resolved against the page and fetched without credentials. |
| `Blob` or `File` | Read in the worker. |
| `ArrayBuffer` or typed array | Copied before it goes to the worker. |
| A `FileList` or array of `File`s | A Shapefile's parts picked together, told apart by extension (one `.shp` plus its `.dbf`, `.prj`, `.cpg`). A single file is read as itself. |
| `{ shp, dbf, prj, cpg }` | A Shapefile's parts, each a URL, a Blob or bytes. Only `shp` is required. |

To read data you already hold as text, pass it to `parse` with an explicit `format`. That works for CSV, WKT, hexadecimal WKB, TopoJSON, KML, GPX and GeoJSON.

**Options** (`ReadOptions`):

| Option | Meaning |
|---|---|
| `format` | `"csv"`, `"wkt"`, `"wkb"`, `"shapefile"`, `"topojson"`, `"kml"` (KMZ too), `"gpx"`, `"flatgeobuf"`, `"geojson"`. When omitted, the format is taken from the URL's or File's extension (see below). If it can't be determined, the read fails. |
| `transformRequest(url)` | Returns `{ url, headers, credentials }` to change the request for a URL, the same shape as the map's `transformRequest`. |
| `crs` | The CRS of coordinates the data doesn't tag. See [Coordinate systems](#coordinate-systems). |
| `layer` | The Shapefile inside a zip (its name without `.shp`, with or without folders) or the TopoJSON object to read. Default: the first. |
| `encoding` | A `.dbf`'s text encoding (`"shift_jis"` or another label, or a code page). Overrides `.cpg` and the language driver. |
| `bbox` | `[minX, minY, maxX, maxY]` in a FlatGeobuf's coordinates: read only the features its index finds there. FlatGeobuf only. |
| `delimiter`, `header`, `dynamicTyping`, `latitude`, `longitude`, `geometry` | CSV options. See [CSV](#csv). |

`formatOf(name)` returns the format for a file name or path, or `null`:

| Extension | Format |
|---|---|
| `.csv`, `.tsv`, `.txt` | `csv` |
| `.wkt` | `wkt` |
| `.wkb`, `.ewkb` | `wkb` |
| `.shp`, `.zip` | `shapefile` |
| `.topojson` | `topojson` |
| `.kml`, `.kmz` | `kml` |
| `.gpx` | `gpx` |
| `.fgb` | `flatgeobuf` |
| `.geojson` | `geojson` |

TopoJSON in a `.json` file needs `format: "topojson"`.

## `Table`

| Member | Meaning |
|---|---|
| `format` | The format it was read as (`null` for a table an operation made). |
| `length` | The number of rows. A GeometryCollection makes one row per member. |
| `columns` | The property names. |
| `layer` | The Shapefile or TopoJSON object read, or `null` for formats without layers. |
| `layers` | Every layer in the input: the Shapefiles of a zip or the TopoJSON objects. Empty for formats without layers. |
| `toGeoJSON()` | A Promise of a new FeatureCollection on every call. You can pass it as a GeoJSON source's `data`. Rows without geometry have `geometry: null`. TopoJSON ids, KML `Placemark` ids and FlatGeobuf feature indices (0-based order in the file) become the features' `id`. |
| `dispose()` | Frees the rows. |

The rows stay on the page until the table's first operation (a method of [analysis.md](./analysis.md), or `toGeoJSON` with a `crs`), which moves them into the analysis worker without copying and starts that worker (`ReadOptions.analysis` says where it is served). Reading a file and drawing it never loads the analysis worker.

```js
const zip = await read("/data/city.zip");
console.log(zip.layers);                           // e.g. ["roads", "buildings"]
const buildings = await read("/data/city.zip", { layer: "buildings" });
map.addSource("buildings", { type: "geojson", data: await buildings.toGeoJSON() });
```

## Coordinate systems

Rows are always returned in longitude and latitude (EPSG:4326).

- **SRIDs in EWKT, EWKB and CSV geometry columns** are read per row. Rows in another SRID are converted, and one input may mix SRIDs. An SRID that isn't a known EPSG code fails, and so do different SRIDs inside one geometry (nested EWKB).
- **Shapefiles** use the `.prj` (Esri or OGC WKT1). A root `AUTHORITY["EPSG", ...]` is used when the code is known. WKT2 fails. Axis order is not read: Shapefile x is always easting.
- **FlatGeobuf** uses the header's `crs`: an EPSG `code` (with `org` EPSG or empty), otherwise its `wkt`, read as a `.prj`.
- **`crs` option**: the CRS of coordinates the data doesn't tag. It applies to rows without an SRID, replaces a Shapefile's `.prj` (which is then not read) and overrides FlatGeobuf's header. Default EPSG:4326. KML, GPX and GeoJSON are always EPSG:4326, so passing `crs` for them fails.

`crs` takes the same values as in `mbt-map/analysis`: an EPSG code (`6677`, `"EPSG:6677"`, `"urn:ogc:def:crs:EPSG::6677"`), `"CRS84"` or a PROJ string. The EPSG codes known without a PROJ string, and the supported projections, are listed in [analysis.md](./analysis.md#coordinate-systems).

```js
// Plane Rectangular CS IX (JGD2011) x, y columns, converted to longitude and latitude.
const survey = await read("/data/survey.csv", { longitude: "x", latitude: "y", crs: 6677 });
```

## Formats

The values each reader produces were checked against papaparse 5.7.0, betterknown 1.2.0, wkx 0.5.0, shpjs 6.2.0, topojson-client 3.1.0, @tmcw/togeojson 7.1.3 on @xmldom/xmldom 0.9.12, and flatgeobuf 4.6.1. The differences are listed in each section below. Some input that those libraries accept loosely is refused here: trailing text after WKT, numbers such as `1a`, Multi members of the wrong type, byte orders other than 0 and 1, truncated `.shp` files, and TopoJSON that isn't a Topology.

### CSV

RFC 4180: quoted fields (`""` for a quote, line breaks inside quotes), CRLF, LF or CR line ends, a leading BOM, and empty lines skipped.

| Option | Meaning | Default |
|---|---|---|
| `delimiter` | One character. When omitted it is guessed, as papaparse does, from `,`, tab, `\|` and `;`. | guessed |
| `header` | The first row names the columns. Repeated names get `_1`, `_2`, as in papaparse. If false, the columns are named `"0"`, `"1"`, ... | `true` |
| `dynamicTyping` | As papaparse's `dynamicTyping`: numbers (`007` is 7, `1e3` is 1000; values beyond ±2^53, `NaN`, `+1` and `0x10` stay strings), `true`/`TRUE`/`false`/`FALSE`, and empty fields as `null`. ISO dates stay strings. If false, every value is a string. | `true` |
| `latitude`, `longitude` | The coordinate columns (always given together). | found by name |
| `geometry` | A column of WKT, EWKT or hexadecimal WKB. | found by name |

When no geometry column is given, it is found by name. First `wkt`, `geometry`, `the_geom` or `geom`, if the first value parses as a geometry. Otherwise a latitude column (`lat`, `latitude`, `y`, `緯度`) and a longitude column (`lon`, `lng`, `long`, `longitude`, `x`, `経度`), case-insensitive. A row whose coordinates aren't numbers keeps its properties without geometry. A WKT/WKB geometry column is not repeated as a property, while latitude and longitude columns are kept. Extra fields beyond the header are dropped, and missing fields are left out of the row's properties.

### WKT and EWKT

Every geometry type is supported. A GEOMETRYCOLLECTION is split into one row per member, nested collections included. `EMPTY` gives a row without geometry. Z, M and ZM coordinates (and untagged 3- and 4-number coordinates) are read and reduced to 2D. Both `MULTIPOINT (1 2, 3 4)` and `MULTIPOINT ((1 2), (3 4))` work. Several geometries separated by whitespace, for example one per line, are read in turn.

### WKB and EWKB

Input can be bytes or a hexadecimal string (PostGIS output; whitespace is ignored). Byte order is read per geometry, nested ones included. ISO Z/M/ZM type codes (+1000/2000/3000) and the EWKB flags are supported. A NaN point is empty. Several geometries placed one after another are all read.

### Shapefile

- Geometry: `.shp` points, multipoints, polylines and polygons, with Z and M dropped to 2D. A Null shape is a row without geometry. A multipoint with one point becomes a Point, and a polyline with one part a LineString. MultiPatch fails. `.shx` isn't used, because the `.shp` is read from the start.
- Polygons: rings are split by orientation (clockwise = outer ring). Each hole goes to the smallest outer ring that contains it. Rings are returned counter-clockwise for outer rings and clockwise for holes (RFC 7946). If some hole fits in no outer ring, the file is read again with orientations swapped, as shpjs does. Holes that still don't fit become outer rings.
- `.dbf` field types:

  | Type | Read as |
  |---|---|
  | C | String, trimmed |
  | N, F | Number, or `null` if empty or unreadable |
  | L | `true` for `TtYy`, `false` for `FfNn`, otherwise `null` |
  | D | `"YYYY-MM-DD"` string (not a `Date`) |

  M (memo) and other field types are not read. Records marked deleted are skipped together with their shape. Shapes without a `.dbf` record have no properties.
- Text encoding is decided in this order: the `encoding` option, the `.cpg` (`UTF-8`, `SJIS`, `Shift_JIS`, `CP932`, `ANSI 932`, `932`, ...), then the `.dbf` language driver (0x13 and 0x7B are Shift_JIS, and so on). The fallback is UTF-8. Decoding uses the browser's `TextDecoder`.
- Zip files are read from the central directory, with stored and deflate entries. ZIP64, split, encrypted and other compression methods fail. Every `.shp` outside `__MACOSX` is a layer, and `layer` picks one. Entry names are read as UTF-8 when flagged or valid UTF-8, otherwise as Shift_JIS.
- When you read a `.shp` by URL, the `.dbf`, `.prj` and `.cpg` next to it are fetched too. A 404 means the file is absent.

```js
// Files picked together in <input type="file" multiple>.
input.addEventListener("change", async () => {
  const table = await read(input.files, { encoding: "shift_jis" });
  map.getSource("upload").setData(await table.toGeoJSON());
});
```

### TopoJSON

Features match topojson-client's `feature`. Quantized arcs (with a `transform`) are delta-decoded, `~i` reverses an arc, arcs are stitched where they meet, and short lines and rings are padded. Point and MultiPoint coordinates use the `transform` without delta decoding. A GeometryCollection object gives one feature per member, and a GeometryCollection inside a member gives one row per element. `id` and `properties` are kept, and nested values become JSON strings. `layer` selects the object (default: the first).

### KML and KMZ

Features and properties match @tmcw/togeojson 7.1.3's `kml()`. XML is parsed as leniently as @xmldom/xmldom 0.9.12, and broken documents fail at the same point.

- Read in this order: `Placemark` (Point, LineString, LinearRing, Polygon, MultiGeometry, `gx:Track`, `gx:MultiTrack`), then `GroundOverlay` (the `LatLonBox` with its rotation, or `gx:LatLonQuad`, as a polygon with `@geometry-type` `"groundoverlay"`). A MultiGeometry is split into one row per member, where togeojson makes a GeometryCollection. `NetworkLink` is not followed.
- Properties: `name`, `description` (CDATA as togeojson's `{"@type":"html","value":...}`), `visibility` (boolean), `address`, `phoneNumber`, `open` and `styleUrl`. The `Style`/`StyleMap` it points to, or an inline `Style`, becomes simplestyle-like values: `stroke`, `stroke-opacity`, `stroke-width`, `fill`, `fill-opacity`, `icon`, `icon-scale`, `icon-color`, `icon-offset`, `label-scale`, ... KML's `aabbggrr` colors become `#rrggbb` plus an opacity. `ExtendedData` (`Data/value`, and `SimpleData` typed by its `Schema`), `timestamp`, `timespan` and track times (`coordinateProperties.times`) are read too.
- Nested values (objects and arrays such as `timespan`, `coordinateProperties`, `icon-offset`) are JSON strings. Heights are dropped. Elements with non-finite coordinates are skipped.
- A KMZ is a zip. It reads the top-level `doc.kml`, or else the first `.kml`.
- Declared entities (`<!ENTITY>`) are not expanded, as in xmldom.

GSI Maps (地理院地図) drawings exported as KML or GPX read like any other file.

### GPX

Output matches togeojson's `gpx()`. Read in order: `trk` (a MultiLineString when it has two or more segments), `rte`, `wpt`. Properties: `_gpxType`, `name`, `cmt`, `desc`, `type`, `time`, `keywords`, `sym`, `links`, namespaced elements (`gpxx_...` and others), line color, opacity and width from `extensions`, and per-point times and extension values (heart rate `heart`, `cads`, ...) in `coordinateProperties`. Elevations are dropped.

### FlatGeobuf

Features match flatgeobuf 4.6.1's `deserialize`. Every geometry type is supported, with per-feature types when the header says Unknown. A GeometryCollection gives one row per member, and Z and M are dropped. All 15 column types are read:

| Column type | Value |
|---|---|
| Integer and floating-point types | Number (Long and ULong rounded to a JavaScript number) |
| Bool | Boolean |
| String, DateTime | String |
| Json | The JSON text, not parsed |
| Binary | A base64 string |

Curve types (CircularString and others) fail. A feature without geometry is a row without geometry.

**`bbox`**: `[minX, minY, maxX, maxY]` in the file's CRS. Only the features whose boxes meet it are read, found through the packed R-tree index. From a URL this uses HTTP range requests, as flatgeobuf's HttpReader does. The header and the top index levels come first, then each index level. Features closer than 256 KB apart are fetched together, with at most 6 requests at once. If the server ignores ranges and returns the whole file, that is read instead. Passing `bbox` for a file without an index fails.

```js
const shown = map.getBounds();
const table = await read("https://example.com/buildings.fgb", {
  bbox: [shown.getWest(), shown.getSouth(), shown.getEast(), shown.getNorth()],
});
```

### GeoJSON

Read by the same reader as GeoJSON map sources. A GeometryCollection gives one row per member, and feature `id`s are kept.

## Writing

```ts
write(input: Table | object, options: WriteOptions): Promise<string>
```

`input` is a `Table`, or a GeoJSON Feature or FeatureCollection object (read as GeoJSON first). `format` is `"geojson"`, `"csv"` or `"kml"`. The result is a string. To save it, wrap it in `new Blob([text])`.

| Format | Output |
|---|---|
| `geojson` | `JSON.stringify(await table.toGeoJSON())`, or `JSON.stringify` of the object you passed. |
| `csv` | As papaparse 5.7.0's `unparse`: CRLF line ends. Values containing quotes, the delimiter, line breaks or a BOM, and values with leading or trailing spaces, are quoted. Property columns come first, then the geometry column(s). Numbers are written as JavaScript's `String(x)`. |
| `kml` | As @placemarkio/tokml 0.4.0's `toKML`: one Placemark per feature with its `id`. The `name`, `description` and `visibility` properties become elements, the rest goes in `ExtendedData`, and Multi geometries become `MultiGeometry`. |

The output matches those libraries byte for byte. CSV options (`CsvWriteOptions`):

| Option | Meaning | Default |
|---|---|---|
| `delimiter` | One character. | `,` |
| `header` | Write a header row. | `true` |
| `geometryFormat` | `"lonlat"`: longitude and latitude columns for points. `"wkt"`: a WKT column (as betterknown 1.2.0's `geoJSONToWkt`). `"none"`: no geometry. | `"none"` without geometry, `"lonlat"` when every row is a point, otherwise `"wkt"` |
| `geometry` | The WKT column's name. | `wkt` |
| `longitude`, `latitude` | The coordinate columns' names. | `longitude`, `latitude` |

If a property column has the same name as a geometry column, the geometry is written in its place. `"lonlat"` fails for rows that aren't points.

```js
import { write } from "mbt-map/table";

const kml = await write(drawnFeatures, { format: "kml" });   // e.g. shapes from mbt-map/draw
const url = URL.createObjectURL(new Blob([kml], { type: "application/vnd.google-earth.kml+xml" }));
```

## GeoTIFF and COG

```ts
readRaster(input, options?: RasterOptions): Promise<Raster>
rasterInfo(input, options?): Promise<RasterInfo>
rasterTile(input, z, x, y, options?: RasterTileOptions): Promise<ArrayBuffer | null>
```

`readRaster` returns the same values as geotiff 3.0.5's `readRasters`. `input` is:

- An http(s) URL. Only the blocks that meet the window are fetched, by range requests, and nearby blocks are merged into one request.
- A `Blob`. Only the needed slices are read.
- Bytes.

**Options:**

| Option | Meaning |
|---|---|
| `window` | `[x0, y0, x1, y1]` image pixels, end exclusive. Pixels outside the image get `fillValue` (default 0). |
| `bbox` | The area in the file's CRS, in place of `window`. |
| `width`, `height`, `resX`, `resY` | The output size or resolution. The coarsest overview that is still fine enough is chosen and resampled with `resampleMethod` (`"nearest"` or `"bilinear"`). |
| `image` | Pick an image (overview) by index. |
| `samples` | The band indices to read. |
| `transformRequest` | As in `read`. |

**Result** (`Raster`):

| Field | Meaning |
|---|---|
| `width`, `height` | Pixels. |
| `bands` | One typed array per band: `Uint8Array`, `Int8Array`, `Uint16Array`, `Int16Array`, `Uint32Array`, `Int32Array`, `Float32Array` or `Float64Array`. |
| `bbox`, `resolution` | The window's box and pixel size in `crs` (y negative for north-up), or `null` without geo tags. |
| `crs` | The GeoKeys EPSG code, or `null`. |
| `noData` | GDAL_NODATA, or `null`. |
| `window`, `image`, `images` | The window read, the image index, and the number of images. |
| `pixelIsPoint` | Whether the GeoKeys say PixelIsPoint. |

Supported files: TIFF and BigTIFF in either byte order, strips and tiles, planar configuration 1 and 2. Compression can be none, LZW, Deflate, PackBits, JPEG or WebP (JPEG and WebP are decoded by the browser), with predictors 2 and 3. Samples can be unsigned 1–16 and 32 bit, signed 8, 16 and 32 bit, or float 16, 32 and 64 bit. Zero-byte blocks read as no data or 0. LERC and ZSTD fail. Where this reader differs from geotiff:

- A big-endian file with a predictor is read as the specification says.
- Passing only `width` resamples the width and keeps the window's height.
- A truncated file fails.

```js
import { readRaster } from "mbt-map/data";
import { loadGrid } from "mbt-map/analysis";

const dem = await readRaster("https://example.com/dem-cog.tif", { bbox: [138.7, 35.3, 138.8, 35.4] });
const grid = await loadGrid(dem, { scale: 111120 });   // slope, hillshade, viewshed: see analysis.md
```

`rasterInfo(input)` returns what drawing a GeoTIFF on the map needs: `{ crs, bounds, maxzoom, samples, noData, range }`. `bounds` are in longitude and latitude, `maxzoom` is for 256 px tiles, and `range` is band 0's values in the coarsest image. The file must carry an EPSG code that `proj.wasm` knows. `rasterTile(input, z, x, y, options)` draws one XYZ tile as PNG bytes, or `null` where the file has no pixels. It takes the same `tileSize`, `bands`, `range`, `colors`, `dem` and `resampling` as the style source below. `reprojectTile(source, z, x, y, options)` does the same for a `reprojected` source made by [mbt-map/services](./services.md).

## The `geotiff` style source

A style can show a GeoTIFF or COG directly with mbt-map's own source type `geotiff`, drawn by a `raster` layer. With `dem: true` it becomes an elevation source for `hillshade`, `color-relief` and `terrain`. The map loads `mbt-map/data`'s worker for its tiles, so the data files must be served next to the main bundle (see [Files](#files-workers-and-lifetime)).

```js
map.addSource("ortho", { type: "geotiff", url: "https://example.com/ortho-cog.tif" });
map.addLayer({ id: "ortho", type: "raster", source: "ortho" });

map.addSource("dem", { type: "geotiff", url: "https://example.com/dem-cog.tif", dem: true });
map.addLayer({ id: "shade", type: "hillshade", source: "dem" });
map.setTerrain({ source: "dem", exaggeration: 1.5 });

map.addSource("temp", {
  type: "geotiff", url: "https://example.com/temperature.tif",
  colors: [[-10, "#2c7bb6"], [10, "#ffffbf"], [30, "#d7191c"]],
});
```

| Key | Meaning |
|---|---|
| `url` | The file. Only the blocks of a suitable overview are fetched for each tile shown, by range requests. Headers and blocks are cached in the worker. |
| `dem` | An elevation source. Heights are packed as Terrarium PNG, so they are in 1/256 m steps. |
| `bands` | The bands to draw. |
| `range` | `[min, max]` for one band, drawn black to white. Default: the coarsest image's value range. |
| `colors` | `[value, color]` stops (CSS colors) for one band, linearly interpolated. |
| `resampling` | `"nearest"` (default) or `"bilinear"`. |
| `tileSize` | 256 (default) or 512. |
| `bounds`, `maxzoom` | Taken from the file unless given in the source. |

8-bit files with 3 or 4 bands are drawn as RGB or RGBA. No-data pixels and values outside the range are transparent. Files in EPSG:3857 and EPSG:4326 (and the JGD2011 and JGD2000 geographic CRSs) are sampled directly. Other CRSs that `proj.wasm` knows, such as Japan Plane Rectangular CS or UTM, are sampled by taking each pixel center to the file's CRS. See [style-support.md](./style-support.md) for the other source types.

## Limits

| What | Limit |
|---|---|
| Input size | 256 MB |
| Points | 20 million |
| CSV | 4096 fields per row, 16 MB per field |
| Property cells (rows × columns: CSV, `.dbf`, TopoJSON, FlatGeobuf, KML, GPX) | 32 million |
| Zip | 10 000 entries, 256 MB inflated in total |
| XML (KML, GPX) | 256 levels deep, 1024 attributes per element, 4 million nodes. KML/GPX feature properties and GPX extension names per track: 4096. |
| FlatGeobuf | 10 MB header, 4096 columns, 256 MB read with `bbox`. Files that point at the same data repeatedly are refused. |
| `.prj` WKT | 65 536 characters, 1024 items per node |
| GeoTIFF | 64 bits per sample, 256 MB per block, 64 million tag values per file, tiles up to 4096 px beyond the image, 2 GB of blocks inflated per read |
| Fetches | 5 minutes per request |

## Files, workers and lifetime

The first call starts `data-worker.js` with `data.wasm`. These are fetched on first use:

| File | Fetched when first |
|---|---|
| `proj.wasm`, `data-crs.js` | converting a CRS other than EPSG:4326 |
| `prjwkt.js` | reading a `.prj` |
| `data-zip.js` | reading a zip (Shapefile zip, KMZ) |
| `xml.wasm` | reading KML or GPX, or writing KML |
| `data-fgb.js` | reading FlatGeobuf |
| `geotiff.wasm`, `data-geotiff.js` | calling `readRaster` and the other raster functions |
| `projstring.js` | a PROJ string is given |
| `data-reproject.js` | drawing a `reprojected` source's tiles |

By default every file loads from next to `data.js`. The options of the first call can point elsewhere: `workerUrl` (`data-worker.js`), `wasmUrl` (`data.wasm`), `projWasmUrl`, `xmlUrl` (`xml.wasm`) and `geotiffUrl` (`geotiff.wasm`). The `.js` parts load from next to `data.js` (where a bundler put them), or from next to the `data-worker.js` given as `workerUrl`. See [getting-started.md](./getting-started.md).

`terminate()` stops the worker and rejects pending calls. The next call starts a new one.
