# NOTICE-dev: test data, fixtures and development dependencies

Not distributed. What is listed here is used only in this repository, to test mbt-map and to
compare it with other implementations; none of it is part of the npm package `mbt-map` or of
the MoonBit modules `t-ujiie-g/mbtmap` and `t-ujiie-g/mbtmap_rabbita`. The third-party code
that is distributed is in [NOTICE](NOTICE).

## Test and benchmark data

Downloaded into `bench/fixtures/` (gitignored; only the sha256 manifests are committed) unless
an entry says otherwise.

- bench/fixtures/draco/ (downloaded by bench/draco/golden.mjs, not committed): files of Draco
  1.5.7's testdata/ (https://github.com/google/draco), Apache License 2.0, Copyright 2016 The
  Draco Authors. draco/decode_test.mbt and point_cloud_test.mbt embed small meshes and point
  clouds encoded by draco3d 1.5.7.
- bench/dist/lepcc/ (downloaded and built by bench/lepcc/upstream.mjs, not committed): Esri's LEPCC
  sources (https://github.com/Esri/lepcc), Apache License 2.0, Copyright 2016 Esri.
  lepcc/decode_test.mbt embeds small blobs, and bench/npm/pages/i3s/pcsl/ synthetic point clouds,
  encoded by its encoder.
- bench/fixtures/pdal-las/ (downloaded by bench/las/golden.mjs, not committed): LAS files of PDAL
  2.8.0's test/data/las/ (https://github.com/PDAL/PDAL), BSD license, Copyright (c) Hobu, Inc.
- bench/fixtures/gsi-bvmap/ (downloaded, not committed):
  国土地理院ベクトルタイル提供実験 (GSI Japan, experimental_bvmap)
  https://maps.gsi.go.jp/development/vt.html
  Used under the GSI content terms of use (国土地理院コンテンツ利用規約).
- bench/fixtures/gsi-dem/, bench/fixtures/gsi-dem-fuji/ (downloaded, not committed):
  国土地理院 標高タイル (GSI Japan, dem_png)
  https://maps.gsi.go.jp/development/ichiran.html#dem
  Used under the GSI content terms of use (国土地理院コンテンツ利用規約).
- bench/fixtures/gsi-std/ (downloaded, not committed):
  国土地理院 標準地図 (GSI Japan, std)
  https://maps.gsi.go.jp/development/ichiran.html
  Used under the GSI content terms of use (国土地理院コンテンツ利用規約).
- bench/fixtures/styles/ (downloaded, not committed): public MapLibre styles read by
  bench/style/compat.mjs and bench/style/public.mjs, pinned by sha256 in
  bench/style/public-styles.mjs. OpenMapTiles styles (OSM Bright, Positron, Dark Matter,
  MapTiler Basic): design CC-BY 4.0 © OpenMapTiles, code BSD-3-Clause. OpenFreeMap styles
  (liberty, bright, positron): MIT. MapLibre demotiles: BSD-3-Clause.
- bench/fixtures/sprites/ (downloaded, not committed): those styles' sprites, from the
  OpenMapTiles style repositories' gh-pages branches (CC-BY 4.0 © OpenMapTiles) and
  OpenFreeMap (ofm_f384, MIT).
- bench/fixtures/ofm-planet/ (downloaded, not committed): OpenFreeMap vector tiles
  (OpenMapTiles schema, build 20261101_080013_pt) of the GSI fixtures' area.
  © OpenMapTiles, Data © OpenStreetMap contributors (ODbL 1.0,
  https://www.openstreetmap.org/copyright). Served by https://openfreemap.org.
- bench/fixtures/protomaps/ (downloaded, not committed): Protomaps vector tiles
  (Protomaps basemap schema, daily build 20261103) of the GSI fixtures' area.
  Data © OpenStreetMap contributors (ODbL 1.0, https://www.openstreetmap.org/copyright).
  Served by https://build.protomaps.com.
- bench/fixtures/plateau-chiyoda/ (downloaded, not committed): PLATEAU 3D Tiles
  (3D都市モデル 建築物モデル 千代田区 2025年度, LOD2 without texture) around Tokyo Station.
  出典：「3D都市モデル（Project PLATEAU）千代田区（2025年度）」（国土交通省）（https://www.mlit.go.jp/plateau/）を加工して作成（東京駅周辺のタイルを抜き出したもの）.
  Used under PLATEAU's site policy (Public Data License 1.0, compatible with CC BY 4.0;
  the 3D city models' copyright belongs to the local governments). Catalog: https://api.plateauview.mlit.go.jp/datacatalog/plateau-datasets
  (id 13101_bldg_lod2_no_texture).
- bench/fixtures/i3s-sf/, bench/fixtures/i3s-frankfurt/ (downloaded, not committed): layer
  JSON, node pages and the geometry and attribute resources of a few nodes of Esri's public
  sample I3S scene services on ArcGIS Online, SanFrancisco_Bldgs (3DObject) and
  Frankfurt2017_vi3s_18 (IntegratedMesh), https://tiles.arcgis.com/tiles/z2tnIkrLQ2BRzr6P/
  arcgis/rest/services/. © Esri and its data providers; used for testing under Esri's terms
  of use, not redistributed.

## Development dependencies

The libraries mbt-map is compared with (the `devDependencies` of `bench/package.json`,
`npm/package.json` and `examples/react/package.json`) are installed from npm under their own
licenses and are not redistributed. Those whose terms ask for a notice where they are used:

- @protomaps/basemaps 5.7.2 (bench devDependency, not shipped): builds the Protomaps
  styles compared by bench/style/public.mjs and compat.mjs. BSD-3-Clause,
  © The Protomaps Authors.
- CesiumJS 1.146.0 (bench devDependency `cesium`, not shipped): draws PLATEAU's
  buildings beside mbt-map/3d in bench/cesium/run.mjs. Apache-2.0,
  © 2011-2026 CesiumJS Contributors (https://github.com/CesiumGS/cesium).
