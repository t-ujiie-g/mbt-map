# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

- **終わったもの**：mbmap の Phase 0〜20 と、その後の点検（mbmap #165 まで）。このリポジトリへ移した（2026-11-15）。
- **名前**（2026-11-15 ユーザー判断）：npm は `moon-map`（入口は `moon-map/ui`、`moon-map/3d` など）、mooncakes は `t-ujiie-g/moonmap`、要素は `<moon-map>`、イベントは `moon-map-error` など、エラーは `moon-map: ...`。コードの識別子やラベルは `moonmap`。
- **進め方**（2026-11-15 ユーザー判断）：
  1. 土台：リポジトリの設定（`main` のルールセット、Dependabot、秘密情報の検出、SECURITY.md）。済み（#1）。
  2. 移行：コードを移し、名前を置き換え、CI を通す。MoonBit のモジュールは直下の 1 つ（`t-ujiie-g/moonmap`）のまま。`moon.work` は rabbita のモジュールを足すときに入れる（ワークスペースでは `_build` の出力がモジュール名の下に出る）。
  3. MoonBit への移行：TS のファサードを MoonBit に移す（案 B）。2026-11-15 のユーザー判断：スタイルは型付きで書け JSON も渡せる、移行の間は表示（メイン）の予算を 175KB まで、順番は 5a（`web` の土台）→ 5c（残りのファサード）→ 5b（rabbita のモジュールとデモ）→ 5d（UI・draw・search）→ 5e（各入口とワーカーの受け渡し）。5a は 5a-1（スタイル文書）・5a-2（地図の生成・イベント・カメラ・ソース）・5a-3（型付きのスタイルの組み立て）に分ける。
  4. 文書：英語の README（日本語版も）、docs/ の API とガイド。MapLibre などと張り合う書き方はしない。ベンチは前に出さない。
  5. GitHub Pages：手書きの LP と、依存ゼロの marked で docs を HTML に、動く examples（html / web component / React / MoonBit）。
  6. 公開の準備：Firefox・WebKit での pack test、npm 0.1.0 と mooncakes の公開（ユーザーが実行）。
  7. その後：単独で使える移植（`mvt`、geojson-vt、`proj` など）を mooncakes に。Phase 21。
- **前のリポジトリから引き継ぐ未解決**：
  - `protomaps` のフィクスチャの版（`build.protomaps.com/20261103.pmtiles`）が消えた（404）。新しい日付にする。
  - `npm:pack` の `showcase-element` がこの Mac でときどき 180 s で落ちる（表の行のクリックの後に地図が止まらない。CI では通る）。
  - 3D の断面の枠の半径（6371008.8 m）とモデルの位置の半径（6378137 m）が楕円体の値とそれぞれ 0.23%・0.11% ずれる（100 m で約 0.2 m）。直すなら緯度で半径を決める。
  - Mac で回すもの：`style:public`・`style:compat`、`render` の変種（`--labels` など）、MapLibre の基準の取り直し。


## 5a-1：スタイル文書を MoonBit に（2026-11-15、Mac）

- 測ったこと（着手の前）：表示（メイン）158KB のうちエンジン 144.8KB・ファサード（TS）14.8KB（gzip）。`npm/src` の TS は約 1.7 万行、ワーカーの JS の糊は約 5 千行。スタイル編集の試作を MoonBit に移すと、`Json` で書いた本体は +1.9KB、`@json.parse`・`stringify` を使うと +28KB（エンジンはスタイルを JS の `JSON.parse` から組み立て用の関数で `Json` に作り直していて、MoonBit の JSON の読み書きを持たない）。
- 新しいパッケージ `web`（js 専用、ファサードの中身の移り先）：`StyleDoc`（スタイルの `Json`、GeoJSON のデータは渡された JS の値のまま脇の表 `DataTable` に、ソースごとの改訂番号）と編集、`engine`（古い書き方は渡された変換で、グローバルな状態、TileJSON の合わせ込みとまだ来ないソースの除外、タイルの URL の解決、GeoJSON のデータの切り離し、`JSON.stringify` で文字列に）、`tilejson_urls`、クレジット（`attributions`、MapLibre の AttributionControl）、警告のレイヤー名、古い書き方の判定（JS の値の上で 32 段まで、10 万段の入れ子でもスタックをあふれない）。`bundle/main/style_doc.mbt` が `doc_*`・`engine_*` として書き出し、ファサードは `#doc` を持って編集の結果（文書か `Error`）を投げる。
- TS から消えたもの：`style.ts` の編集（型と `copy`・`loadedState`・`invalidCustomLayer` だけ残す）、`tilejson.ts`、`tilejson-merge.ts`（遅れて読む 0.5KB のファイルも）、`engine-style.ts` の `resolveTiles`・`splitGeoJSON`、`index.ts` の `attributionsOf` の使用（`ui` は `inZoomRange`・`layerShown` をまだ使う。5d で移す）。テストは MoonBit へ（21 件）。`GEOTIFF`・`PMTILES` の文字列はミラーのテストで比べる。
- 大きさ：表示（メイン）161.8 → **167.9KB**（予算は 175KB に。ユーザー判断）。エンジン側 +7.8KB、TS 側 −1.6KB。TS の 2KB ほどの処理が MoonBit では 4〜5 倍になった（試作の 1.5〜2 倍の見積もりより大きい）：`Json` の列挙型のパターンマッチ、`Option`、エラー、文字列の組み立てが長い JS になる。ジェネリックな `Map` の値の型を増やすとその写しが入る（`Map[String, Bool]`・`Map[String, Int]`・`Map[String, JsValue]` をやめて 153.9 → 152.6KB）。
- 速さ（M2）：`draw:setdata` は頂点 10〜5000 で中央値 16.5〜16.7 ms（画面の更新の間隔のまま、MapLibre と同じ）、`draw:many`（2000 個の形）は中央値 32.84 ms・p95 34.35 ms（前は 32.85・32.96 ms）。
- 確認：`moon check --target all --deny-warn`、`moon test --target all`（js 969）、`npm test` 424、`npm --prefix bench test`、`npm run size`、pack test 19 項目、ゴールデン（style・raster・labels・query・geojson:update・ui・pmtiles・geotiff:tiles・draw）。
- 次の判断：この比のままファサード全体（TS で約 13KB）を移すと、表示（メイン）はさらに 30KB 前後増える見込みで、175KB に収まらない。進め方をユーザーと相談する。
