# GIS web services (`mbt-map/services`)

`mbt-map/services` reads OGC and ArcGIS web services and turns them into style sources and GeoJSON: WMS 1.1.1 and 1.3.0, WMTS 1.0.0, WFS 1.0.0, 1.1.0 and 2.0, OGC API - Features and OGC API - Tiles, and ArcGIS REST MapServer, ImageServer, FeatureServer and VectorTileServer. It runs on the main thread (capabilities are parsed with the browser's `DOMParser`), except for Esri's JSON and PBF feature formats, which a worker of its own reads. It sends requests without credentials; add tokens or headers with `transformRequest`. Each service's terms of use, access limits and attribution are the page's responsibility.

```js
import { arcgisService, arcgisSource, arcgisStyle, getCapabilities, ogcCollections, ogcTiles, wmsSource, wmtsSource } from "mbt-map/services";

const wms = await getCapabilities("https://example.com/wms", "WMS");
map.addSource("wms", wmsSource(wms, { layers: ["roads", "rivers"] }));
map.addLayer({ id: "wms", type: "raster", source: "wms" });

const wmts = await getCapabilities("https://example.com/wmts/1.0.0/WMTSCapabilities.xml", "WMTS");
map.addSource("wmts", wmtsSource(wmts, { layer: "basemap" }));

const url = "https://example.com/arcgis/rest/services/Topo/MapServer";
map.addSource("topo", arcgisSource(await arcgisService(url), url));

map.setStyle(await arcgisStyle("https://example.com/arcgis/rest/services/Basemap/VectorTileServer"));

const [lakes] = await ogcCollections("https://example.com/ogcapi");
map.addSource("lakes", await ogcTiles(lakes, "vector"));
```

## Requests and `transformRequest`

Every function that fetches takes `ServiceOptions`:

| Option | Description |
|---|---|
| `transformRequest(url, "Source")` | Returns `{ url, headers?, credentials? }` or undefined, as the map's `transformRequest` does. Use it for API keys, tokens and headers. |
| `signal` | An `AbortSignal` that aborts the requests. |

URLs are resolved against the page and must be http(s). Without a `credentials` value from `transformRequest`, requests go with `credentials: "omit"`.

```js
const transformRequest = (url) => ({ url: `${url}${url.includes("?") ? "&" : "?"}token=${token}` });
const service = await arcgisService(layerUrl, { transformRequest });
```

## Capabilities

`getCapabilities(url, "WMS" | "WMTS" | "WFS", options)` fetches and reads a capabilities document. `url` is the service endpoint (`SERVICE` and `REQUEST=GetCapabilities` are added) or a document URL ending in `.xml`. Relative URLs in the document are resolved against the document's URL. The readers `readWMSCapabilities(xml, base?)`, `readWMTSCapabilities(xml, base?)` and `readWFSCapabilities(xml, base?)` take a string or a `Document`.

- **WMS** (`WMSCapabilities`): `version`, `title`, `getMapUrl`, `getFeatureInfoUrl`, `mapFormats`, `infoFormats` and the `layers` tree. A `WMSLayer` has `name`, `title`, `abstract`, `crs`, `bounds`, `boundingBoxes`, `styles` (`{ name, title, legendUrl }`), `queryable`, `opaque`, `minScale`, `maxScale`, `attribution` and sublayers in `layers`. Layers inherit from their parents as WMS 1.3.0 §7.2.4.8 says (CRSs and styles are added; bounds, scales and attribution are taken from the parent when missing). `allLayers(layers)` lists every layer depth first.
- **WMTS** (`WMTSCapabilities`): `version`, `title`, `getTileUrl` (the KVP endpoint), `layers` (`id`, `title`, `bounds`, `styles`, `formats`, `infoFormats`, `tileMatrixSets`, `resources`, `dimensions`) and `tileMatrixSets`. `mercatorZooms(set)` gives `[first, last]` when a set is the Web Mercator quadtree, else null.
- **WFS** (`WFSCapabilities`): `version`, `title`, `getFeatureUrl`, `outputFormats` and `featureTypes` (`name`, `title`, `abstract`, `defaultCrs`, `otherCrs`, `bounds`, `outputFormats`).

A service's exception report (ServiceExceptionReport, ows:ExceptionReport, or an ArcGIS `error`) makes the call fail with its message.

## WMS

`wmsSource(capabilities, options)` makes a `raster` source that sends one GetMap per tile in EPSG:3857 (`BBOX={bbox-epsg-3857}`), with the layers' geographic bounds and attribution.

| Option | Description |
|---|---|
| `layers` | Layer name or names to draw, bottom first. |
| `styles` | Their styles. Default the server's. |
| `format` | Default `image/png`. |
| `transparent` | Default true. |
| `tileSize` | Default 256. |
| `crs` | The CRS a reprojected source asks in (below). |
| `params` | More GetMap parameters, such as a dimension's `TIME`. |

Layers without EPSG:3857 make a `reprojected` source instead: one GetMap per tile in `crs` (default EPSG:4326 when every layer offers it, else the first layer's first EPSG CRS that all offer), taken onto Web Mercator tiles by `mbt-map/data`'s worker (see [Data](./data.md)). Passing `crs: "EPSG:3857"` forces an ordinary raster source. In WMS 1.3.0, boxes in EPSG:4326 and Japan's plane rectangular systems are written northing first.

## WMTS

`wmtsSource(capabilities, options)` makes a `raster` source for a layer in a Web Mercator quadtree tile matrix set whose matrix identifiers are zoom numbers. It uses the layer's ResourceURL (REST) for the format when there is one, else KVP, with the layer's bounds and the set's zooms.

| Option | Description |
|---|---|
| `layer` | The layer identifier. |
| `style` | Default the layer's default style. |
| `format` | Default the layer's first format. |
| `tileMatrixSet` | Default the first Web Mercator set. |
| `dimensions` | Values for dimensions such as `Time`. Default each dimension's default. |

When the layer has no Web Mercator set, a set in another EPSG CRS (EPSG:4326, JGD2011, plane rectangular systems and others) makes a `reprojected` source, drawn as WMS ones are.

## Reprojected sources

`wmsSource` and `wmtsSource` return a source of mbt-map's own type `reprojected` for services without Web Mercator. Add it with `addSource` and draw it with a `raster` layer, as any other. Its tiles are made in `mbt-map/data`'s worker, which takes each pixel's center into the service's CRS and samples the service's tiles or images (nearest neighbour). Its fields: `crs` (an EPSG code), and either `grid: { template, matrices }` (a WMTS tile matrix set: `template` with `{TileMatrix}`, `{TileRow}` and `{TileCol}`; each matrix with `id`, `resolution` in CRS units per pixel, top-left `x` and `y`, tile `width` and `height`, and `cols` and `rows`) or `image: { template, northFirst }` (one GetMap per tile, with `{bbox}`, `{width}` and `{height}`); plus `tileSize` (256 or 512), `minzoom`, `maxzoom`, `bounds` and `attribution`. See also [Style support](./style-support.md).

## ArcGIS REST

`arcgisService(url, options)` fetches a service's or layer's `?f=json` (`ArcGISService`); an `error` in the answer throws.

`arcgisSource(service, url, options)` makes a source for a MapServer, ImageServer or VectorTileServer:

- **VectorTileServer**: a `vector` source; zooms from the service's `minzoom` / `maxzoom` (else `minLOD` / `maxLOD`).
- **MapServer, ImageServer**: the Web Mercator cache's `tile/{z}/{y}/{x}` when the service has one (a MapServer needs `singleFusedMapCache`), else one `export` (ImageServer: `exportImage`) per tile in EPSG:3857.

The attribution is the service's `copyrightText`, the bounds its `fullExtent` when in Web Mercator or WGS 84 (`arcgisBounds(service)`; `arcgisZooms(service)` gives a cache's zoom range).

| Option | Description |
|---|---|
| `layers` | Sublayer ids to draw (`show:`), which forces `export`. |
| `dynamic` | Use `export` even when the service is cached. |
| `format` | For `export`. Default `png32`. |
| `transparent` | Default true. |
| `dpi` | Default 96. |
| `tileSize` | For `export`. Default 256. |
| `params` | More `export` parameters. |

`arcgisStyle(url, { style, ...options })` fetches a VectorTileServer's style (default the `root.json` of its `defaultStyles`; `style` names another) and makes its URLs absolute with `arcgisVectorStyle(style, styleUrl, service, serviceUrl)`: the source naming the service gets its tile URL and zooms written out, and the sprite and glyphs are resolved against the style.

FeatureServer and MapServer layers' features are read by `arcgisFeatures` (below).

## OGC API

- `ogcCollections(url, options)`: the collections of the OGC API whose landing page is `url` (its `data` link is followed).
- `ogcCollection(url, options)`: one collection (`/collections/{id}`).
- `ogcTiles(collection, "vector" | "map", options)`: a source for the collection's vector or map tiles on WebMercatorQuad (OGC API - Tiles), zooms from its `tileMatrixSetLimits`. Throws when the collection has no such tiles.

An `OGCCollection` has `id`, `title`, `description`, `bounds`, `crs`, `itemType`, `itemsUrl` (OGC API - Features), `vectorTilesUrl` and `mapTilesUrl` (tileset lists) and `mapUrl`, all absolute. The lower-level readers `readOGCCollections`, `readOGCCollection`, `ogcLinks`, `ogcTilesetUrl`, `isWebMercatorQuad` and `ogcTileSource` are exported too.

## Gathering features

Three functions gather features as a GeoJSON FeatureCollection, which a GeoJSON source's `setData` takes as it is. They follow the pages and stop at `maxFeatures` (default and cap `MAX_FEATURES`, one million), at `MAX_PAGES` (10,000) or at a page URL seen before; then the result has `exceeded: true`. All take `maxFeatures` besides `ServiceOptions`.

### `ogcFeatures(collection, options)`

OGC API - Features items. `collection` is an `OGCCollection` or an items URL. Options: `bbox` (degrees), `limit` (per page), `datetime`, `properties`. Each page's `next` link is followed.

### `wfsFeatures(capabilities, options)`

A WFS GetFeature.

| Option | Description |
|---|---|
| `typeName` | The feature type. |
| `bbox` | In degrees. |
| `count` | Per page. On WFS 2.0, pages by STARTINDEX while pages come back full. |
| `startIndex` | The first feature. |
| `outputFormat` | Default the first GeoJSON format the service offers, else its latest GML. |
| `crs` | `SRSNAME` of the output. |

GML (2, 3.1 and 3.2) is asked for and read in EPSG:4326 only. Properties are read as strings (nested elements as objects, repeated ones as arrays, `xsi:nil` as null). The axis order follows the srsName: URNs and OGC URLs take the CRS's order, GML 2's `…epsg.xml#4326` is longitude first, and a bare `EPSG:4326` is read in the order asked for. The GML reader (`services-gml.js`) is loaded only when GML is first read. A `bbox` is sent latitude first in EPSG:4326 for WFS 1.1 and 2.0, longitude first for 1.0.

### `arcgisFeatures(layerUrl, options)`

A FeatureServer or MapServer layer's `query` (`…/FeatureServer/0`), in EPSG:4326.

| Option | Description |
|---|---|
| `where` | Default `1=1`. |
| `bbox` | In degrees. |
| `outFields` | Default all. |
| `offset`, `count` | Paging. |
| `format` | `"pbf"`, `"geojson"` (ArcGIS Server 10.4 and later) or `"json"`. Default: PBF if the layer's `supportedQueryFormats` lists it, else GeoJSON, else JSON. |
| `workerUrl`, `wasmUrl` | Where `services-worker.js` and `services.wasm` are served, if not next to the module. |

PBF and JSON answers are read by a worker of their own (`services-worker.js` with `services.wasm`, started on first use) into the same GeoJSON that `arcgisToGeoJSON` of @terraformer/arcgis gives. When the layer supports pagination, pages follow by `resultOffset` while the answer says `exceededTransferLimit`. `terminate()` stops that worker.

### URL builders

`ogcItemsUrl(itemsUrl, options)`, `wfsFeatureUrl(getFeatureUrl, version, options)` and `arcgisQueryUrl(layerUrl, options, format?)` build the first request's URL without fetching. `geojsonFormat(formats)`, `gmlFormat(formats)` and `arcgisFormat(layer)` give the formats chosen by default.

## Following the view

### `followView(map, sourceId, query, options)`

Keeps a GeoJSON source filled with the features of what the map shows. `query(bounds, signal)` is called again after each move (`moveend`) with the view's `[west, south, east, north]`, and the previous query is aborted. Returns the function that stops it.

| Option | Description |
|---|---|
| `minzoom` | Below it, the source is emptied and nothing is asked. |
| `onError` | Gets failed queries. Default `console.error`. |

```js
map.addSource("cities", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
const stop = followView(map, "cities", (bbox, signal) => arcgisFeatures(layerUrl, { bbox, signal }), { minzoom: 10 });
```

### `followImage(map, sourceId, image, options)`

Shows the view as one image from a WMS or ArcGIS service, asked again after each move for the view's EPSG:3857 box at its resolution. The image source is added if the map does not have it, else updated with `updateImage`. Returns the function that stops it.

`image` comes from `wmsImage(capabilities, options)` (options as `wmsSource`'s) or `arcgisImage(url, options)` (options as `arcgisSource`'s).

| Option | Description |
|---|---|
| `pixelRatio` | Device pixels per CSS pixel. Default `devicePixelRatio`. |
| `maxSize` | The most pixels on a side. Default 4096. |

```js
const stop = followImage(map, "wms", wmsImage(capabilities, { layers: "std" }));
map.addLayer({ id: "wms", type: "raster", source: "wms" });
```

## Feature info

Both ask about a 101 × 101 pixel window around a point on a map at `zoom`.

- `wmsFeatureInfo(capabilities, options, lngLat, zoom, serviceOptions)`: a WMS GetFeatureInfo. Options are `wmsSource`'s plus `queryLayers` (default `layers`), `infoFormat` (default the service's GeoJSON format, else its first JSON one; GML answers are not read) and `featureCount`.
- `arcgisIdentify(mapServerUrl, lngLat, zoom, options)`: a MapServer `identify`. Options: `layers` (default `all`; `top`, `visible`, `all`, optionally with `:` ids), `tolerance` (pixels, default 3), `returnGeometry` (default true), `params`. The result is GeoJSON in EPSG:4326, and each feature's `layer` names the layer it was found in (`{ id, name }`).

`wmsFeatureInfoUrl` and `arcgisIdentifyUrl` build the URLs without fetching.

```js
map.on("click", async (e) => {
  const info = await wmsFeatureInfo(capabilities, { layers: "parcels" }, [e.lngLat.lng, e.lngLat.lat], map.getZoom());
  showPopup(info.features);
});
```

## Limits

| Constant | Value | What it caps |
|---|---|---|
| `MAX_DOCUMENT_BYTES` | 32 MB | One document or page. |
| `MAX_GATHERED_BYTES` | 256 MB | All pages of one `ogcFeatures`, `wfsFeatures` or `arcgisFeatures` call. |
| `MAX_FEATURES` | 1,000,000 | Features gathered by one call. |
| `MAX_PAGES` | 10,000 | Pages asked for by one call. |
| `MAX_WMS_LAYERS` | 10,000 | Layers read from one WMS capabilities document. |

## Other exports

`withQuery(url, params)` adds query parameters to a URL, `resolved(url, base)` resolves one, and `isWebMercator(crs)` tells whether a CRS name is Web Mercator.
