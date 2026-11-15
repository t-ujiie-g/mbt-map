# mbt-map

[MoonBit](https://www.moonbitlang.com/) で書いた、ブラウザのための軽量な WebGIS ライブラリです。ベクトルとラスタの地図、GIS のデータ形式、空間解析、GIS の Web サービス、3D の都市モデルを 1 つにまとめ、どの部分もページが初めて使うときに読み込みます。

[English](README.md)

```js
import { Map } from "mbt-map";

const map = new Map({
  container: "map",
  style: "https://example.com/style.json",
  center: [139.7671, 35.6812],
  zoom: 14,
});
map.on("click", "stations", (e) => console.log(e.features[0].properties.name));
```

> 最初の公開（0.1.0）に向けて準備中です。npm のパッケージと MoonBit のモジュールはまだ公開していません。

## できること

- **地図**：ベクトルタイル、ラスタと標高のタイル、GeoJSON（クラスタ、データの更新）、PMTiles、画像と動画。スタイルは MapLibre のスタイル仕様で書き、ラベルとアイコン、3D の地形、空、地球儀の表示、建物の押し出し、光と影を描きます。`Map` の API は MapLibre GL JS と同じ形です。
- **データ**（`mbt-map/data`）：CSV、WKT/WKB、GeoJSON、Shapefile、TopoJSON、KML/KMZ、GPX、FlatGeobuf、GeoTIFF/COG を読み、GeoJSON、CSV、KML に書き出します。座標系の変換（平面直角座標系を含む）もします。
- **解析**（`mbt-map/analysis`）：計測、空間索引と空間関係、バッファとオーバーレイ、単純化、凸包と凹包、ボロノイ図、補間、等値線、クラスタリング、経路探索、階級区分、地形の傾斜と可視域。
- **Web サービス**（`mbt-map/services`）：WMS、WMTS、WFS、OGC API、ArcGIS REST のレイヤーを、地図のソースや地物として読みます。
- **3D**（`mbt-map/3d`）：glTF のモデル、3D Tiles、I3S、LAS の点群。地物の選択、見通し、可視域、断面も。
- **道具**：見た目を持たない UI のコントローラ（`mbt-map/ui`：縮尺、凡例、レイヤーの一覧、計測、属性テーブルなど）、検索（`mbt-map/search`）、作図と編集（`mbt-map/draw`）、楕円体の上の計測（`mbt-map/geodesic`）。
- **使い方**：JavaScript/TypeScript の API、Web Component の `<mbt-map>`（React などのフレームワークからも）、MoonBit の型付きの API と Web フレームワーク [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) の部品。

描画のエンジンと重い処理（タイルの読み込みと三角形分割、解析、形式の読み込み）は MoonBit から WebAssembly にしたもので、Worker で動きます。メインスレッドには小さな TypeScript の層だけを置いています。

## インストール

```sh
npm install mbt-map
```

パッケージは素の ES モジュールで、Worker と `.wasm` はモジュールの隣から読みます。そのまま配信すれば（import map や `dist/` の静的なコピー）設定なしで動きます。バンドラを使うときは [Getting started](docs/getting-started.md#bundlers) を見てください。

MoonBit のアプリ（js ターゲット）からは：

```sh
moon add t-ujiie-g/mbtmap            # 型付きの API
moon add t-ujiie-g/mbtmap_rabbita    # rabbita の部品
```

## 入口

| 入口 | 内容 |
|---|---|
| `mbt-map` | 地図の `Map` |
| `mbt-map/element` | Web Component `<mbt-map>` |
| `mbt-map/ui` | 見た目を持たない UI のコントローラ |
| `mbt-map/search` | 地名と座標の検索 |
| `mbt-map/draw` | 作図と編集 |
| `mbt-map/geodesic` | WGS 84 の楕円体の上の距離、面積、円 |
| `mbt-map/data` | GIS のデータの読み込みと書き出し |
| `mbt-map/analysis` | 空間解析と座標系 |
| `mbt-map/services` | GIS の Web サービス |
| `mbt-map/3d` | 3D のモデル、3D Tiles、I3S、点群 |

## 文書

文書は英語です。

- [Getting started](docs/getting-started.md)
- [文書の目次](docs/README.md)：地図、スタイル、Web Component、MoonBit、入口ごとのガイド
- [例](examples/)：同じショーケースのアプリを JavaScript の API、Web Component、React で書いたもの、3D の都市（PLATEAU）のページ、rabbita のアプリ

## ブラウザ

WebAssembly GC が要ります：Chrome と Edge 119 以降、Firefox 120 以降、Safari 18.2 以降。Content Security Policy を使うページでは `script-src 'wasm-unsafe-eval'` と `worker-src 'self'` が要ります。`eval` は使っていません。

## 開発

このリポジトリには、MoonBit のエンジン、npm のパッケージ（`npm/`）、Web Component（`element/`）、MoonBit の API（`moonbit/`）、例、テストと比較のスクリプト（`bench/`）があります。開発の決まりは [AGENTS.md](AGENTS.md)、設計は [docs/dev/VISION.md](docs/dev/VISION.md)、進み具合は [PROGRESS.md](PROGRESS.md) にあります。

## ライセンス

[Apache License 2.0](LICENSE)。移植したコードは元のライセンスのままで、[NOTICE](NOTICE) に一覧があります。例は国土地理院のタイルと、国土交通省の PLATEAU の 3D 都市モデルを読みます。
