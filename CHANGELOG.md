# Changelog

All notable changes to the npm package `mbt-map` and the MoonBit modules `t-ujiie-g/mbtmap` and `t-ujiie-g/mbtmap_rabbita`. They share one version.

## 0.1.0

The first release.

- `mbt-map`: a map drawn with WebGL2 from styles in the MapLibre style specification, with a `Map` API shaped like MapLibre GL JS's: vector and raster tiles, GeoJSON (clusters, updates), PMTiles, images and video, labels and icons, 3D terrain, sky, globe, extrusions, lights and shadows, feature queries and state, custom layers, image export.
- `mbt-map/element`: the `<mbt-map>` web component.
- `mbt-map/data`: CSV, WKT/WKB, GeoJSON, Shapefile, TopoJSON, KML/KMZ, GPX, FlatGeobuf and GeoTIFF/COG in; GeoJSON, CSV and KML out; coordinate systems.
- `mbt-map/analysis`: measures, spatial indexes and relations, buffers and overlays, shapes, surfaces and clustering, routing, classification, terrain analysis and viewsheds.
- `mbt-map/services`: WMS, WMTS, WFS, OGC API and ArcGIS REST.
- `mbt-map/3d`: glTF models, 3D Tiles, I3S and LAS point clouds; picking, lines of sight, viewsheds and clipping.
- `mbt-map/ui`, `mbt-map/search`, `mbt-map/draw`, `mbt-map/geodesic`: headless UI controllers, search, drawing and editing, geodesic measurement.
- `t-ujiie-g/mbtmap`: a typed MoonBit API (styles and expressions generated from the style specification); `t-ujiie-g/mbtmap_rabbita`: the map in rabbita apps.
