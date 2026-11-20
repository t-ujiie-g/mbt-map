# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

- **いま**：単独で使える移植を mooncakes に出す段（VISION §8「単独の移植」）。(1) `clipper`、(2) `draco`・`lepcc`・`meshopt`・`robust`・`tiff`、(3) `pbf`・`mvt`、(4) `proj`・`geodesic` と共有の `trig` を `ports/` に切り出した、(5) 点検まで済み、11 個とも 0.1.0 を mooncakes に公開した（2026-11-17、ユーザー）。0.1.1 は 2026-11-16 に公開済み。次はテーブルの段階（VISION §8）で、T.1（新しい入口 `mbt-map/table` と 1 つの型 `Table`）、T.2（属性の操作：`select`・`filter`・`derive`・`orderby`・`slice`）、T.3（集計と結合：`groupby`・`rollup`・`join`）、T.4（空間結合と揃え直し：`spatialJoin`・`nearestJoin`・`dissolve({ by })`）、T.4b（描画への直結：ソースの `data` にテーブルを渡す）、T.5（Arrow IPC の読み書き：`fromArrow`・`toArrowIPC`）、T.6（GeoParquet の読み込み：ファイル全体、snappy と gzip）、T.6b（zstd の展開の移植）、T.6c（Parquet を `bbox` と `columns` で絞って範囲リクエストで読む）まで済んだ。
- **済んだ段階**（どれも下に日付つきの節がある。決めたことは次の節「進め方と名前の決定」）：
  - 移行：mbmap の Phase 0〜20 とその後の点検（mbmap #165 まで）を、このリポジトリへ移して改名した。
  - MoonBit の API：`mbt-map/moonbit` の入口、型付きの `mbtmap`（地図、カメラ、イベント、生成したスタイルと式）、rabbita の部品 `mbtmap_rabbita` とデモ。
  - 文書：README、docs/ の入口ごとのガイド、その後の点検（リファクタリングとセキュリティ）。
  - GitHub Pages：手書きのトップ、docs の HTML、動く例。サンプル集とテーマの切り替え、例の画面の英語化。
  - 公開の流れ：タグで npm への段階公開と GitHub のリリース、mooncakes は手で。
  - 公開前の直し：3D Tiles の読み直しの繰り返し、出典の HTML、地形で手前の低い土地が描かれない件、CDN から HTML 1 枚で読む、グリフのアトラスがあふれる件、世界のコピー（`renderWorldCopies`）、トップの地図、Firefox と WebKit での pack test、タッチ操作がページに漏れる件と `idle`（公開前の QA）、`updateData` の「全部消して足す」で描画側の属性が消える件・背景レイヤーの描く順・DEM より大きく引いた地形でページが固まる件。
  - 0.1.1：公開後の小さい直し（`interactive: false` の tabindex、属性テーブルの `reveal` と 180° またぎの `zoomTo`、値が 1 つのクラスの凡例、`protomaps` のフィクスチャ）、3D レイヤーの半球光（`hemisphere`）、測地バッファを日付変更線と極で切る・MultiPoint は点ごとの円、サンプルの import map を使う入口だけに。
- **次**：0.2.0 の版上げ（版の番号と CHANGELOG。タグと公開はユーザー）。テーブルの段階は T.8（リファクタリングとセキュリティの点検）まで済み。その後 Phase 21。
- **未解決**：
  - 実機のスマホ（iOS の Safari、Android の Chrome）でのタッチ操作は未確認。
  - `npm:pack` の `showcase-element` がこの Mac でときどき 180 s で落ちる（表の行のクリックの後に地図が止まらない。CI では通る）。2026-11-16 に単独で 8 回、全項目で 1 回回しても再現せず、原因は分かっていない。
  - 3D の断面の枠の半径（6371008.8 m）とモデルの位置の半径（6378137 m）が楕円体の値とそれぞれ 0.23%・0.11% ずれる（100 m で約 0.2 m）。直すなら緯度で半径を決める。
  - Mac で回すもの：`style:public`・`style:compat`、`render` の変種（`--labels` など）、MapLibre の基準の取り直し。
  - Linux の WebKit で `antialias: false` のキャンバスの最後のフレームが出ない件が headless だけのことか。Linux の headless Firefox に WebGL2 がない（pack test は飛ばす）。
  - 世界が画面より狭い（ズーム約 1 未満）とき、同じタイルの別のコピーにはラベルが出ない（MapLibre はコピーごとに配置する）。
  - 地形の上では `background-pattern` を描かない（色の背景は地形のテクスチャに順番どおり入る）。地形つきの背景の順は MapLibre とのピクセル比較に入っていない（`style:golden` の環境で MapLibre 側が地形の上の hillshade を描かず、比べる絵にならなかった）。
  - @maplibre/geojson-vt の `applyPropertyUpdates` は 6.3.1 と main でも `removeAllProperties` のとき足す属性を捨てる（上流へは未報告）。
- **文書の置き場所**：毎回読む決まりは AGENTS.md、仕組みの詳しい説明は docs/dev/ARCHITECTURE.md とその分冊、コマンドの一覧は docs/dev/COMMANDS.md、ツールチェーンと計測で分かったことは docs/dev/TOOLCHAIN.md（AGENTS.md を 130KB から分けた）。

## 進め方と名前の決定（2026-11-15、ユーザー判断）

- **終わったもの**：mbmap の Phase 0〜20 と、その後の点検（mbmap #165 まで）。このリポジトリへ移した（2026-11-15）。
- **名前**（2026-11-15 ユーザー判断。いったん `moon-map` にしたが、月の地図に読めるので同日に `mbt-map` へ改名。リポジトリも `t-ujiie-g/mbt-map`）：npm は `mbt-map`（入口は `mbt-map/ui`、`mbt-map/3d` など）、mooncakes は `t-ujiie-g/mbtmap`、要素は `<mbt-map>`、イベントは `mbt-map-error` など、エラーは `mbt-map: ...`。コードの識別子やラベルは `mbtmap`。
- **進め方**（2026-11-15 ユーザー判断）：
  1. 土台：リポジトリの設定（`main` のルールセット、Dependabot、秘密情報の検出、SECURITY.md）。済み（#1）。
  2. 移行：コードを移し、名前を置き換え、CI を通す。MoonBit のモジュールは直下の 1 つ（`t-ujiie-g/mbtmap`）のまま。`moon.work` は rabbita のモジュールを足すときに入れる（ワークスペースでは `_build` の出力がモジュール名の下に出る）。
  3. MoonBit で書けるように：中身（ファサード）は TS のまま、MoonBit には npm の実装を中で使う型付きの API と rabbita の部品を作る（2026-11-15 ユーザー判断。いったん選んだ案 B「ファサードを MoonBit に移す」は、測った大きさを見て取りやめた。下の節）。スタイルは型付きで書け JSON も渡せる（同日のユーザー判断）。API の形（2026-11-15 ユーザー判断）：スタイルは層ごとの関数とラベル付きの引数（MapLibre の `v8.json` から生成、`@style.Layer::json` で JSON も）、rabbita には `<mbt-map>` 要素を包んで置き（イベントは rabbita のメッセージ、地図の操作は Cmd から型付き API）、モジュールはエンジンを `t-ujiie-g/mbtmap_engine`（内部）、使う人向けを `t-ujiie-g/mbtmap` と `t-ujiie-g/mbtmap_rabbita` に。MoonBit から npm の実装は `#module` の静的 import で読み（呼べるのは関数なので、npm に `mbt-map/moonbit` の入口を足す）、ワーカーと wasm は npm のパッケージが自分の場所から読む。段階：M1 ワークスペースと改名（#7）、M2 `mbt-map/moonbit` と `mbtmap` の土台（地図、カメラ、イベント、JSON のスタイル編集）、M3 型付きのスタイルと式（生成）、M4 `mbtmap_rabbita` と rabbita のデモ。
  4. 文書：英語の README（日本語版も）、docs/ の API とガイド。MapLibre などと張り合う書き方はしない。ベンチは前に出さない。
  5. GitHub Pages：手書きの LP と、依存ゼロの marked で docs を HTML に、動く examples（html / web component / React / MoonBit）。
  6. 公開の準備：Firefox・WebKit での pack test、npm 0.1.0 と mooncakes の公開（ユーザーが実行）。
  7. その後：単独で使える移植（`mvt`、geojson-vt、`proj` など）を mooncakes に。Phase 21。
- **Dependabot**（2026-11-15 ユーザー判断）：bench の依存はゴールデンの比べる相手なので版の更新の提案を止め（`open-pull-requests-limit: 0`）、セキュリティの更新だけ受ける。比べる相手を上げるときは、そのゴールデンを回し直す PR を意図して作る。

## ファサードを MoonBit に移す試み（案 B）とその取りやめ（2026-11-15、Mac）

- 5a-1（#4）でスタイル文書とその編集を js 専用のパッケージ `web` に移した。振る舞いは同じ（ゴールデン、pack test、`draw:setdata`・`draw:many` の速さとも変わらず）だが、表示（メイン）が 161.8 → 167.9KB になった。`web` の正味は gzip 7.67KB で、置き換えた TS は約 1.6KB（4〜5 倍）。
- 大きくなる理由：MoonBit が生成する JS は構造が長い（ラベル付きのブロックと一時変数、`Map` の反復ごとのイテレーターのオブジェクト、`Map` のリテラルの包み、`Option` と `raise` の `Result` の分岐）。最小化しても名前が縮むだけ。ジェネリックな `Map` の値の型を増やすとその型の写しが入る（3 つやめて −1.3KB）。`@json.parse`・`stringify` を使うと +28KB（エンジンは JS の `JSON.parse` から組み立て用の関数で `Json` を作り、MoonBit の JSON の読み書きを持たない）。
- 大きさ重視の書き方を試した（#4 の後）：文字列の埋め込みを `+` の連結に −0.13KB、一番大きい関数（`engine`、`web` の 2 割）をイテレーターや `Map` のリテラルを使わない形に −0.47KB。全体でも −2KB 前後の見込みで、TS の約 3.5 倍にとどまる。
- 判断（ユーザー）：中身は TS のまま、MoonBit には型付きの API。#4 を戻し（revert）、表示（メイン）の予算を 163KB に戻した。MoonBit で書いた処理をメインの束に入れるのは、MoonBit でしか書けない重い処理（描画のエンジンなど）に限るのがよい。

## M2：MoonBit の API の土台（2026-11-15、Mac）

- npm に `mbt-map/moonbit`（`createMap`、0.1KB。MoonBit の `#module` の import は関数として呼ぶので、コンストラクタを関数で渡す）。
- `t-ujiie-g/mbtmap`（`moonbit/mbtmap/`、js 専用）：`Map::new(container, style=Url(..) | Spec(json), center?, zoom?, bearing?, pitch?, 範囲, interactive?, attribution?)`、カメラ（`center`・`zoom`・`bearing`・`pitch`、`jump_to`・`ease_to`・`fly_to`・`fit_bounds`、`project`・`unproject`）、スタイル（`set_style`・`style`、ソースと層の追加・削除・移動、`layer_ids`、`set_paint`・`set_layout`・`set_filter`、`set_data`、`set_feature_state`）、イベント（`EventType` の enum、型付きの `Event` と `Feature`、`on`・`on_layer` が返す `Listener::off`）、`query_rendered_features`（Promise をコールバックに）。JS のメソッドは汎用の `js_call` 1 つを通す。パッケージの中では使う人向けの `Map` が標準の `Map` を隠すので、標準のは `@builtin.Map` と書く。
- 確かめ：`bench/moonbit/app`（モジュール `t-ujiie-g/mbtmap_check`）が MoonBit だけで地図を作り、読み込みでソースと層を足し、落ち着いたら中心の地物を問い合わせ、`paint` とカメラを変え、イベントの受け取りを外す。pack test の `moonbit` が結果を確かめる（20 項目）。`Idle` は `Load` の直後にも来る（MapLibre と同じ）ので、足した層を問い合わせるのはその次の `Idle`（`EventType` の説明に書いた）。
- `moon info` は js 専用のパッケージに `.mbti` を書かない（文書の後の点検で、MoonBit の API のモジュールには `preferred_target = "js"` を置いて書くようにした）。

## M3：型付きのスタイルと式（2026-11-15、Mac）

- `t-ujiie-g/mbtmap/expr`：`Expr`（式の JSON を包む）。定数（`num`・`str`・`bool`・`color`・`nums`・`literal`）、`get`・`has`・`id`・`geometry_type`・`zoom`・`feature_state`・`global_state`、`match_`（ラベルは JSON）・`case_`・`coalesce`・`interpolate`（`Curve`：直線、指数、3 次ベジェ）・`step`、比較・論理・`in_`・四則・文字列・`image`、生の `raw`。
- `t-ujiie-g/mbtmap/style`：`Layer`・`Source`・`Style`（`Style::new(sources~, layers~, sprite?, …)`、`Style::url`、`Style::json`、`Layer::json`、`Source::json`）。層ごとの関数 10 個（`fill` … `background`；`paint`・`layout` のプロパティは省略できるラベル付きの引数で、型は `@expr.Expr`）とソースの関数 6 個（`vector_source` … `video_source`；層の `raster` と名前がぶつかるので `_source` 付き。数や文字列は型付き、複雑なものは JSON）は `bench/moonbit/gen-style.mjs` が style-spec 26.5.0 の `v8.json` から生成する（`npm run moonbit:style`）。生成したものと同じかは bench の `npm test` が確かめる（空白と閉じ括弧の前のカンマを除いて比べ、`moon fmt` の整形は無視する）。予約語の候補（`volatile`）は `_` を付ける。`background` は `source` を取らず、`source_layer` と `filter` は地物を描く層だけ。
- `mbtmap` の `Map::new`・`set_style` は `@style.Style`、`add_source` は `@style.Source`、`add_layer` は `@style.Layer`、`set_paint`・`set_layout`・`set_filter` は `@expr.Expr` を取るように変えた（M2 の `Style` の enum はなくした）。確かめのアプリと README も型付きの書き方に。
- 確かめ：`expr`・`style` の単体テスト（8 件）、pack test の `moonbit`。

## M4：rabbita の部品とデモ（2026-11-15、Mac）

- 依存の確認（AGENTS §8.1）：`moonbit-community/rabbita` 0.16.7 と、それが引く `moonbitlang/async` 0.22.4・`moonbitlang/x` 0.5.1・`moonbitlang/moonback` 0.8.5。どれも Apache-2.0 で MoonBit の公式の組織のもの。rabbita のソースに `eval`・`new Function` はなく、`innerHTML` は `Attrs::inner_html`（XSS の警告付きで `#internal` の印）を使ったときだけ。通信（`fetch`、WebSocket）はそのパッケージを使ったときだけ。使うのは `html`・`cmd`・`sub` と最上位だけ。
- rabbita の公開の API では任意の属性やイベントを要素に付けられない（`Attrs::attribute` と独自のイベントの受け手は非公開。`@html.node(tag, attrs, children)` はある）。そこで `t-ujiie-g/mbtmap_rabbita`（`moonbit/mbtmap_rabbita/`、js 専用）は、
  - `view(id, css?, class?)`：id の付いた `<mbt-map>` を置く。
  - `setup(id, @style.Style, center?, zoom?, bearing?, pitch?)`：描いた後に動く Cmd。要素のプロパティにカメラを入れ、スタイルを渡す（URL なら `style-url`、JSON なら `mapStyle`）。ここで地図ができる。
  - `events(id, on_load?, on_idle?, on_move?, on_moveend?, on_click?, on_error?)`：`subscriptions` から返す Sub。要素のイベントは泡立って Shadow DOM の外へ出るので、`document` で受けて id で選び、メッセージ（型付きの `Camera`・`Click`、エラーの文）にする。
  - `with_map(id, f)`：型付きの `@mbtmap.Map` で操作して、次の Cmd を返す。`query_features(id, point, layers?, emit)`：地物の問い合わせの答えをメッセージに。
- 要素に `mbt-map-click`（`detail` に `point` と `lngLat`）と、id で要素を返す `mbtMapElement(id)` を足した。MoonBit 側は `#module("mbt-map/element")` でこれを import するので、要素の定義も読まれる。
- デモ `examples/rabbita/`（モジュール `t-ujiie-g/mbtmap_rabbita_example`）：rabbita の `create_state_with_init` のアプリ。行き先のボタン（`fly_to`）、`mbt-map-moveend` からの中心とズームの表示、クリックした点の座標と駅名（`query_features`）、点の大きさの切り替え（`set_paint`）。スタイルは MoonBit の型付きの関数で書く（地理院の淡色地図のラスタ、`?local=1` でフィクスチャの標準地図、駅の円とラベル）。Vite などは使わず、`bench/npm/prepare.mjs` が `moon build` の出力を esbuild で縮めて `examples/rabbita/app.js`（gitignore）に置き、ページは import map で `mbt-map` を読む。`app.js` は gzip 25.9KB（rabbita 込み、mbt-map 本体は別）。
- 確かめ：`mbtmap_rabbita` の whitebox テスト 3 件（イベントの `detail` の読み、受け手のある種類だけ答える）。rabbita の `Html` の等しさは物理的な比較なので `view` は単体で比べられず、pack test の `rabbita`（ボタンで富士山へ行って戻る、中心の点のクリックで「（東京駅）」、`circle-radius` の変更）で確かめる。

## 文書 4a：README と docs/ の構成（2026-11-15、Mac）

- 構成（2026-11-15 ユーザー判断）：`docs/` を使う人向けの英語の文書にし、開発者向けの VISION・FORMATS・CLOUD は `docs/dev/` へ移した（参照は機械的に置き換え）。API の説明は手書きの Markdown で、入口ごとのガイドに分ける。PR は 4a（README、npm の README、`docs/README.md` の目次、Getting started、`docs/dev/` への移動）と 4b（入口ごとのガイドと API、MoonBit）の 2 つ。
- README は英語（`README.md`）と日本語（`README.ja.md`）。何ができるかを分野ごとに書き、ほかのライブラリとは比べず、ベンチの数字は載せない。npm の README は英語の短い版にした（これまでの日本語の詳しい説明は 4b で `docs/` の各ガイドへ移す。コードのコメントが `npm/README.md` を指しているところも 4b で付け替える）。

## 文書 4b：入口ごとのガイド（2026-11-15、Mac）

- `docs/` に英語のガイド 11 本：`map`（`Map` の作成、カメラ、イベント、実行中のスタイルの変更、GeoJSON とクラスタ、画像、問い合わせ、地物の状態、地形・空・投影、光と影、3D の選択・見通し・可視域・断面、`track`、`toBlob`、カスタムレイヤー、要求の変更、Worker と wasm の場所）、`style-support`（描くスタイル仕様の範囲と拡張）、`web-component`（HTML と React）、`moonbit`（型付きの API と rabbita）、`ui`、`search`、`draw`（`geodesic` も）、`services`、`data`、`analysis`、`3d`。3 つのエージェントが worktree で並行して書き、名前と引数はソースと照らした。`moonbit.md` のコード例はコンパイルして確かめた。相対リンクと見出しのアンカーは切れていない（その場のスクリプトで確かめた）。
- 書きながら分かった `npm/README.md`（旧）とソースの食い違いは、ソースに合わせた：属性の欄の編集は変わった地物だけ `updateData`、`createMeasurement` の `measure` は省略でき `measure3d` もある、`createGeolocation` の `outOfMaxBounds`、検索の `reverse(lngLat, request)`、MapServer のタイルのキャッシュは `singleFusedMapCache` も要る、空の `atmosphere-blend` は地球儀の大気で読む、`mbt-map/data` の `geotiffUrl`、FlatGeobuf は `bbox` がなくても `data-fgb.js` を読む、など。点のラベルの `text-pitch-alignment` と `text-rotation-alignment` は警告なしに読まない（`style-support` の違いに書いた）。
- コードのコメントが `npm/README.md` を指していたところを、該当するガイドに付け替えた。`timeOfDayLights` の返す `Light` の型をメインの入口から出した。

## 文書の後の点検：リファクタリングとセキュリティ（2026-11-15、Mac）

このリポジトリで足したもの（MoonBit の API、rabbita の部品と例、要素の追加、生成と準備のスクリプト、CI の準備、文書）を AGENTS §7・§8 で点検し、見つけたもの（R1〜R6）を 1 PR で直した（ユーザー判断）。

- R1：`Map::query_rendered_features` は問い合わせの Promise の失敗（ない層など）を受けていなかった。失敗はコンソールに出して `done([])` を呼ぶ。
- R2：`mbtmap_rabbita` のイベント名と受け手を 1 つの表（`handlers`）にした（`handle` と購読の両方がそれを読む。購読のキーは受け手のある種類を並べたもの）。
- R3：確かめのアプリ（`bench/moonbit/app`）が `Map` の全メソッドを呼ぶようにした（層の layout・filter・並べ替え・削除、ソースの追加・削除、`set_data`、地物の状態、`pitch`・`ease_to`・`fit_bounds`・`unproject`、`on_layer` のクリック、`set_style`、`remove`、ない層の問い合わせ）。pack test の `moonbit` が結果を見る。
- R4：出典は文字で表示する（HTML は解釈しない）ので、Getting started と rabbita の例の出典を文字にし、`docs/map.md` に書いた。
- R5：改名の名残の「mbtmap's」などを、型定義に出る説明コメントと大きさの表で「mbt-map」にした（`mbtmap:overlay` などのキーはそのまま）。
- R6：MoonBit の API の 2 つのモジュールに `preferred_target = "js"` を置き、`moon info` が `pkg.generated.mbti` を書くようにした。公開 API の差分は CI の `moon info` の差分の確かめが見る。
- セキュリティ：`npm audit`（npm、bench、examples/react）0 件、Dependabot と秘密情報の警告 0 件。リポジトリの設定（`main` のルールセット、秘密情報の検出と押し込みの防止、Dependabot のセキュリティ更新）は改名の後も有効。新しいコードに `innerHTML`・`eval` はなく、外部コマンドはシェルを通さない。

## 3D Tiles の読み直しの繰り返しを直す（2026-11-15、Mac）

- 症状（ユーザーの録画）：PLATEAU の例を引いて見ると、カメラを止めていても建物が出たり消えたりを繰り返し、タイルを読み続けた。
- 原因：`maximumLoadedTiles`（既定 256）を超えると、描いているタイル以外を古い順に解放していた。REPLACE のタイルの子は兄弟が全部そろうまで描かれないので、読み終えた子が解放され、また読まれ、を続けていた（引いた視点で要るタイルが 256 を超えると止まらない）。
- 直し：解放するのは、そのフレームが使わなかったタイル（`lastUsed` がそのフレームでないもの）だけ（`evictable`、`npm/src/tiles/tileset.ts`。loaders.gl のキャッシュも同じ考え）。そのフレームが上限より多く要るときは、上限を超えて持つ。
- 確かめ：PLATEAU の例をズーム 14.6、傾き 55° にして 40 秒見た。直す前は要求が 789 まで増え続け、描くタイルは 23〜170 を行き来した。直した後は 22 秒で 527 要求、354 タイルで止まった。`tiles:golden`、`i3s:golden`、pack test の 3D の 5 項目、単体テスト（`evictable`）。

## GitHub Pages（2026-11-15、Mac）

- 判断（ユーザー）：公開はリリースのタグ（`v*`）を打ったときだけ（手動でも流せる）。トップページは英語と日本語の 2 枚で作ったが、日本語が機械翻訳のようなので、日本語のトップと `README.ja.md` は外した（同日）。トップの地図は 3D に（PLATEAU の東京駅まわり）。
- `site/`：手書きのトップページ（ヒーローに PLATEAU の 3D Tiles の建物：地理院の淡色地図を暗く、低い日の光と影、ゆっくり回り、触ると止まる。動きを減らす設定では回らない）、`site.css`（明暗のテーマ、スマホ幅）、アイコン。`bench/site/build.mjs`（`npm run site`）が `_site/` に組み立てる：`docs/*.md` を marked 18.1.2（依存なし、MIT、既知の脆弱性なし、公開から 2 週間以上の版。bench の開発依存）で HTML にし、コードは組み立てのときに highlight.js 11.12.0（依存なし、BSD-3、既知の脆弱性なし）で色分けし（MoonBit は自前の文法 `bench/site/moonbit-highlight.mjs`、ページは色分けのスクリプトを読まない）（見出しのアンカーは GitHub と同じ、目次は `docs/README.md` から題名だけ、リンクは `bench/site/links.mjs` が文書と公開する例はサイトの中へ、それ以外は GitHub へ）、`npm/dist` の js と wasm を 1 度だけ `lib/` に置き、例（html、element、React、PLATEAU、rabbita）はソースを除いて写し import map を `lib/` に向ける。5.8MB。
- 確かめ：`bench/lib/site.test.mjs`（アンカー、リンクの付け替え、文書の相対リンクとアンカーが切れていないこと）。CI は pack のジョブでサイトを組み立てる。ローカルで全ページを Chromium で開き、コンソールのエラーと 4xx がないこと、見た目（トップ、スマホ幅、暗いテーマ、文書、例）を見た。
- 公開の設定：Pages は GitHub Actions から、`github-pages` 環境は `main` と `v*` のタグから配備できる。

## 例の画面を英語に（2026-11-15、Mac）

- ショーケース（`examples/html`、`element`、`react`、共有の `examples/shared/`）、PLATEAU の例、例の一覧（`examples/index.html`）の画面の文言を英語にした：タブ、見出し、ボタン、入力欄の説明、ツールチップ、状態と誤りの文、凡例の名前と道路の種別、表の見出し、件数、計測と解析の読み出し、`<title>`、`lang="en"`。
- 日本語のまま残したもの（データだから）：地名・駅名、地点の `kind`（駅・名所・山）、国土地理院のベクトルタイルと PLATEAU の属性の値と鍵、サンプルの CSV、同梱した WMTS の文書の名前（地理院タイル、淡色地図）、平面直角座標系の系の名前（`第IX系`。`mbt-map/search` が読む書き方で、検索のプロバイダの出力とも同じ）、出典の文言（国土地理院と PLATEAU の求める書き方）。PLATEAU の属性の表示名は英語（Name、Usage、Measured height など）。例が作る列は英語の名前にした（`area`、`area_km2`、印は `Marker N`）。
- rabbita の例（MoonBit）は対象の外で、日本語のまま。
- pack test の画面の文字を見る確かめ（`pack-test.mjs`、`checks/` の analyze、geo-tools、plateau、search、table、showcase-data、showcase-services）を英語の文言に合わせた。

## 出典の HTML（2026-11-15、Mac）

- サンプルを書くエージェントが見つけた：OpenFreeMap のように出典を HTML（`<a href>`）で書くスタイルでは、出典の欄にタグがそのまま文字で出た（安全のため `textContent` で入れていた）。
- 直し：`attributionParts`（`npm/src/attribution.ts`、DOM を使わない小さな読み取り）が文字と http(s) のリンクだけを取り出し、ほかのタグは落とし、文字参照を戻す。地図の出典の欄はそれを文字とリンク（`target="_blank"`、`rel="noopener noreferrer"`）で組み立てる。HTML としては一切解釈しない。`mbt-map/ui` の `createAttribution` の `items` はタグを落とした文字にした。

## サンプル集とテーマの切り替え（2026-11-15、Mac）

- 判断（ユーザー）：例は「小さな例をたくさん」。ほぼ同じショーケースが 3 つあっても嬉しくないので、サイトに載せるショーケースは 1 つ（element 版はリポジトリと pack test に残す）。
- `examples/samples/`：23 個（地図 8：基本、ベクトルのスタイル、GeoJSON とクリック、クラスタ、ヒートマップ、富士山の地形、建物と影、地球儀／データ 2：読み込み、書き出し／解析 3：バッファ・ボロノイ・凸包、階級区分図、経路／道具 4：作図、計測、UI のコントローラ、検索／Web サービス 2：GIBS の WMTS と WMS、ArcGIS の地物／3D 3：PLATEAU、glTF、見通し／Web Component 1）。3 つのエージェントが worktree で並行して書き、API はソースと照らし、画面写真で見た目を確かめた。
- サイト：例の目次をサンプルのカード（グループごと）とアプリ（ショーケース、PLATEAU、React、rabbita）から組み立て、サンプルごとのページに動くサンプル（iframe）と `main.js`・`index.html` の全文（色分け）を並べる。全ページにライト・ダークの切り替え（既定は端末の設定、選んだものを覚える）。
- 書きながら見つかったエンジンの課題：中心を高い山頂（富士山頂）に置いて傾けると、手前の低い土地のタイルが描かれない（地形のある時の覆うタイルの計算が中心の高さで見ているらしい）。経度 180 度を越えて地図が繰り返さない。地面に沿わない 3D の線がない。漢字の多い地図で都市を何か所も回るとグリフのアトラスがあふれ、文字が欠ける（rabbita の例で）。

## rabbita の例を中国の都市でも見せるショーケースに（2026-11-15、Mac）

- `examples/rabbita/` を作り直した：MoonBit で書いた WebGIS のアプリ。左のサイドバー（rabbita）と右の地図。UI の文は英語、地名は現地の表記。
  - 飛ぶ先：北京・上海・深圳・香港・成都・杭州・東京・大阪（`fly_to`）。都市は GeoJSON の点と名前の層（`cities`、`city-names`）で、`name:zh`・`name:ja`・`name:en` を持つ。
  - ベースマップ：OpenFreeMap の Liberty（世界、OpenStreetMap のベクトルタイル、キー不要）と地理院の淡色地図（日本）を `Map::set_style` で切り替える。Liberty は文書を取ってきて MoonBit の `Json` として直す（都市の層を足す、ラベルの言語と建物の高さを入れる、出典を文字にする：TileJSON の出典は HTML で、ソース自身の `attribution` が勝つ）。地理院と都市の層は型付きの関数で書く。
  - ラベルの言語：中文・日本語・English・現地名。`Map::style()` の記号の層のうち `text-field` が名前を読むもの（道路番号の盾や矢印は除く）を MoonBit で数え上げ、`@expr.coalesce([@expr.get("name:zh-Hans"), @expr.get("name:zh"), @expr.get("name")])` などを `set_layout` で入れる。OpenFreeMap のタイル（OpenMapTiles）は `name:zh`・`name:zh-Hans`・`name:ja`・`name:en`・`name_en` を持つ（フィクスチャで確かめた。日本の地名の `name:zh` は繁体字のことが多い）。
  - 3D の建物：Liberty の `building-3d` の高さを `render_height` / `render_min_height` と 0 で切り替え（`set_paint`）、傾きを 60° にする（`ease_to`）。地理院のときは押せない。
  - クリックした地物の名前（選んだ言語で）、層、種類（`class`、なければソースの層）と、`on_moveend` からのカメラを表示する。
- スタイルの文書は `extern "js"` の `fetch` と `JsValue::to_json` で読む。rabbita の `@http` は `moonbitlang/async` と MoonBit の JSON の読み手を引き、`app.js` が gzip 80KB になったのでやめた（29.5KB。前の例は 25.9KB）。
- `?local=1`：Liberty の文書は `bench/fixtures/styles/ofm-liberty.json`（`bench/npm/prepare.mjs` が `style/public-styles.mjs` の固定した版を sha256 で確かめて取る。取れなければ警告して地理院で始まる）、タイルは `bench/fixtures/ofm-planet`（東京駅の周りの z14 だけ）と `gsi-std`、スプライトは `bench/fixtures/sprites/ofm`。そこで東京で始まる。CI はタイルのフィクスチャを持たないが、確かめはスタイルと都市の層だけで足りる（タイルのフィクスチャを外しても通ることを確かめた）。
- pack test の `rabbita`：最初の Liberty と中文の `text-field`、日本語への切り替え（`label_city` と `city-names`、盾は変わらない）、大阪へ飛んで東京へ戻る、中心の都市のクリックで「東京」と層 `cities`、3D（`fill-extrusion-height` が `["get", "render_height"]`、傾き 60°）、地理院へ切り替えて（3D は押せない）Liberty へ戻る（言語と 3D は保つ）。例の whitebox テスト 10 件（名前の層の見分け、言語ごとの式、Liberty の直し、フィクスチャへの付け替え、地理院のスタイル）。
- 実際のタイルで北京（中文、3D）、上海（English、3D）、東京（日本語、地理院）の画面を見た。都市を何度も回ると「glyph atlas is full」の警告が出る（漢字の多い地図では字の表が足りなくなる。エンジン側の課題）。

## 公開の流れ（2026-11-15、Mac）

- 判断（ユーザー）：タグを打ったら各所に公開されるように。少なくとも npm は自動で、pptx-svg の流れ（信頼された公開と段階公開、2FA で承認）を参考に。
- `.github/workflows/release.yml`（`v*` のタグ）：`verify`（タグ・版・CHANGELOG のそろい、MoonBit のテスト、npm のビルド・テスト・大きさ）→ `npm`（`npm stage publish`、OIDC、npm 11.15 以上。その版がもうあれば飛ばす）、`github-release`（`CHANGELOG.md` の節を本文に）。Pages は `pages.yml` が同じタグで。
- mooncakes は手で公開する（ユーザー判断）：mooncakes のトークンは期限がなくアカウント全体に効き、OIDC のような仕組みもないので、CI の secret に置くと workflow や Actions が乗っ取られたときに任意の版を出されうる。npm は OIDC と 2FA の承認があるので自動のまま。
- 版：npm と MoonBit の 2 モジュールは同じ版（0.1.0）。`bench/lib/release.mjs` が版と CHANGELOG のそろいを見る（`release.test.mjs` が今の版でも確かめる）。npm の `package.json` は `private` を外し、説明、キーワード、ホームページ（Pages）、`publishConfig.access: public`。`npm pack` は 167 ファイル、0.91MB（展開 2.51MB）。`moon publish --dry-run` は通る。
- npm の信頼された公開はパッケージが npm にないと設定できないので、0.1.0 は手元から一度出し、その後に信頼された公開（段階公開だけ）を設定する。手順は docs/dev/RELEASING.md。
- Pages を手動で一度公開した（https://t-ujiie-g.github.io/mbt-map/ ）。

## 地形で手前の低い土地が描かれない（2026-11-15、Mac）

- 症状：3D 地形（地理院の DEM、`"encoding": "gsi"`）で中心を富士山頂（3776 m、誇張 1.5 倍で 5664 m）に置き、ズーム 12・傾き 70° にすると、画面の下（カメラの近くの低い土地）が待っても空いたまま。富士吉田のように低い所を中心にすると出ない。
- 原因：`Transform::covering_tiles` は画面の四隅の光線が海面（z = 0）と交わる四角形を地面の範囲としていた。中心が持ち上がる（`Transform.elevation`）と、画面の下の光線が海面に届く点はカメラから遠くなり、その間の高さの土地（手前の低い斜面）が範囲の外に出る。`bench/pages/terrain` のこの眺め（1000 × 800）では z12 の 3625–3627/1618 の列が覆う集まりから落ちていた。
- 直し（MapLibre の `coveringTiles` が地形のとき各タイルの最低・最高の標高の箱で視錐台を試すのに倣う）：`covering_tiles(min_z, max_z, heights?)` は各タイルの地面を `heights` の最低と最高の標高の間とみなし、その 2 つの高さで四隅の光線が交わる 8 点の凸包（`Transform::footprint`、Jarvis の行進）とタイルの重なりを見る。`heights` がなければ MapLibre の既定と同じく海面と中心の標高の間（地形がなければ高さ 0 だけで、これまでと同じ四角形）。カメラより高い標高はカメラのすぐ下で切る。`map` は `Map::ground_heights` を渡す：そのタイルを含む読み込み済みの DEM タイルの最低・最高（誇張込み）、なければ読み込み済みの DEM タイル全部と中心の標高の範囲（祖先のタイルが子の見える土地を落とさないように）。`terrain_pick` と同じ集計は `dem_range` にまとめた。
- 確かめ：直す前と後の画面（傾き 70°、方位 0° と -20°）で下の空白が消えた。MoonBit のテスト（`core/covering_test.mbt`）：山頂を中心にした眺めで 0 m から中心の標高までの画面内の点がすべて覆われる（直す前は 13 点などが外れて失敗）、`heights` が中心より 5 km 高い土地を覆う、カメラより高い `heights`、海面の眺めは `heights` があっても同じ。`camera:golden`・`globe:golden`（覆うタイル 0 differ）・`track:golden`・pack test（terrain、showcase-html、samples）は通った。`track:golden` の `flank` は main でも時々 319 px 外れる（読み込みの時機による、この変更の前から）。
- 大きさ：主バンドルが gzip 162.3KB → 163.0KB（162,989 バイト、予算 163,000 まで 11 バイト）。
- 予算（2026-11-15 ユーザー判断）：表示（メインの束）の予算を 163KB から 168KB に上げた。この直しで 163.0KB（11 バイト手前）になり、0.1.0 の前に入れる CDN 対応、world copies、グリフのアトラスの直しの分を見込んだ。増えた分は各 PR で測って記録する。

## CDN から HTML 1 枚で（2026-11-15、Mac）

- 判断（ユーザー）：例は npm install 前提でなく、CDN から HTML 1 枚で動く形が適切。0.1.0 の前に入れる。
- 問題：ブラウザは別のオリジンの Worker のスクリプトを起動しない。CDN から読むと、モジュールの隣から読む Worker だけが弾かれ、地図が読み込まれなかった（pack test の `cdn` で、直す前はタイムアウト）。
- 直し：`workerScriptUrl`（`npm/src/urls.ts`）が、ライブラリ自身のフォルダ（CDN の `dist/`）にある Worker を、それを import するだけの同じオリジンの `blob:` から起こす（URL ごとに 1 つ作って使い回す）。オリジンでなくフォルダで判定する（CDN は誰のパッケージも同じオリジンから配るので、オリジンで許すと別のパッケージのスクリプトも通る。自動のセキュリティレビューの指摘）。ページのオリジンとライブラリのフォルダ以外は今までどおり拒むので、`<mbt-map worker-url>` などのマークアップから別のコードは起こせない。CSP を使うページが CDN から読むときは `worker-src blob:` が要る（Getting started に書いた）。wasm と動的 import は別のオリジンからでも読める。
- 確かめ：pack test の `cdn`（`bench/npm/pages/cdn`、パッケージを CORS 付きの別のポートから読む。地図のタイルの Worker、GeoJSON の Worker、解析の Worker がそれぞれ動き、問い合わせと解析の結果が合う）。単体テスト（blob の中身、使い回し、別のオリジンを拒む）。
- 見せ方：Getting started の最初を「CDN から HTML 1 枚」にし、npm は次の節に。README と npm の README に CDN の書き方。サイトのサンプルのページは、表示するコードの import map を jsDelivr の版つきの URL（今の版、`mbt-map@0.1.0`）に、CSS をサイトの絶対 URL にして、コピーしてそのまま動く形にした（サイトで動かすのは今どおり同じオリジンの `lib/`）。

## グリフのアトラスがあふれる問題（2026-11-15、Mac）

- 症状：漢字の多い地図（OpenFreeMap の Liberty に中文・日本語のラベル）で都市を何か所も回ると「the glyph atlas is full; some labels miss characters」が出て、以後のラベルの文字が欠けたままになる。
- 原因：グリフは主スレッドの 1 枚のアトラス（2048 px 四方、R8）に足すだけで、外すことがなかった。TinySDF のグリフは 48 px + 余白 6 px で約 62 px 四方なので、2048 px には 1000 字ほどしか入らない。ワーカーは各グリフを一度しか送らないので、あふれた字は二度と載らない。ワーカー側のキャッシュ（`MAX_GLYPHS` 4096）も満ちると以後の字を空白にしていた。
- 直し：
  - アトラスが満ちたら作り直す（`Map::rebuild_atlas`）。読み込み済みのタイル（Ready、Stale、読み込み中の前のもの）とそのタイルの通知が使うグリフだけを `@label.Atlas::repack` で詰め直す（高いものから。使うグリフが面積の半分を超える間は辺を倍にし、`ATLAS_SIZE` 2048 から `MAX_ATLAS_SIZE` 8192（`MAX_TEXTURE_SIZE` がそれより小さければそれ）まで。少なくなれば 2048 に戻る）。
  - 頂点のアトラス座標は別のバッファ（`uv`）にし、記号のメッシュはグリフの番号と角（4 バイト/頂点）を持つので、作り直しの後は `Renderer::place_glyphs` で書き直すだけ（タイルを読み直さない）。MapLibre のようなタイルごとのアトラスは、グリフの鍵が全体で一つで描画がアトラス 1 枚を前提にしているこの作りでは変更が大きいので採らなかった。
  - 主スレッドは受けたグリフのビットマップを持つ（`@label.GlyphStore`）。作り直しで外したものは、全ワーカーが新しい `{type: "glyphs", epoch}` に答えるまで残す（それ以前に作られたタイルが使いうるため）。ワーカーはそれを受けると「送った」記録を消し、次に使うときに送り直す。ワーカーのキャッシュは満ちたら空にして描き直す（送り直しはしない）。
  - 警告は 8192 px でも読み込み済みのタイルの字が入らないときだけ。
- 再現と確かめ：`npm run labels:atlas`（`bench/labels/atlas.mjs`）。Liberty（ofm-planet のフィクスチャ）に GeoJSON の漢字ラベル（1 段 600 字、段ごとに別の字）を重ね、`setData` で 20 段進めてから、最後の段を新しいページで描いたものと比べる。
  - 直す前：警告 1 回、新しいページと違う画素 26303（GeoJSON のラベルがほぼ全部消える）。
  - 直した後：警告 0、違う画素 0〜2000 弱（建物の縁。ラベルは同じ）。40 段で作り直しは 5 回、各 2〜5 ms（M2、Chromium）、アトラスは 2048 と 4096 を行き来。1 段 1800 字でも警告なし（4096 に広がる）。
- `npm run labels:golden` は全シーン同じのまま。MoonBit のテスト（`label`：repack、`bitmap_at`、`GlyphStore`）とワーカーのテスト（送り直し、キャッシュを空にする）を足した。
- 大きさ：`mbt-map` 162349 → 164177 バイト（+1.8KB、主に `Map[Int32, Bitmap]` の実体化）、ラベルのワーカー部分 9563 → 9612、表示ワーカー 85000 → 85032。記号のメッシュは頂点あたり CPU に 4 バイト（グリフの番号と角）、GPU に 4 バイト（`uv`）増える。

## 世界のコピー（renderWorldCopies、2026-11-15、Mac）

- メルカトルで経度 180 度の東西に世界を繰り返す（MapLibre の `renderWorldCopies`、既定 true）。低いズームで左右が空く、180 度付近（フィジー、太平洋、アラスカとロシアの間）で片側しか出ない、を直した。
- main の取り込み：地形の高さの範囲（`covering_tiles` の `heights`）はコピーごとの歩きの中で正準のタイルについて引き、足跡をそのコピーへずらして使う。
- 設計：`@core.UnwrappedTile`（MapLibre の `UnwrappedTileID`：正準のタイルと `wrap`）。`Transform::covering_tiles` は見える範囲の各コピー（`Transform::wraps`、左右 3 まで）を同じ四分木で歩き、`wrap` 付きで返す。タイルの読み込み・キャッシュは正準のタイルのまま（コピーごとに取り直さない）。`tile_matrix` / `tile_light_matrix` は `wrap~` で 1 世界ずらす。`Draw` は `wrap` と `copy`（同じメッシュを別のコピーでも描くもの）を持ち、地形のテクスチャやヒートマップのタイル内描画は `copy` を飛ばして二重に描かない。パターンの位置（`pattern_tile`）、影、クリッピング、地面の影、背景のパターン、画像・動画ソース（MapLibre の `getVisibleUnwrappedCoordinates` と同じく見えるコピーと左右 1 つずつ）もコピーごと。地形の高さ（`elevation_at`）は x を主の世界に戻して引く。
- カメラ：`Limits.world_copies`。false のとき MapLibre の `defaultConstrain` と同じく経度範囲を ±(180 − 1e-10) に限り、中心の折り返しも `normalizeCenter` もしない。true のときは従来どおり（中心の経度は折り返す）。`project` / `unproject` / `getBounds` は MapLibre と同じく経度を折り返さない（もとから）。
- ラベル：タイルのラベルの状態はメッシュごとに 1 つなので、複数のコピーに出るタイルのラベルは中心に最も近いコピーで配置し、そのコピーでだけ描く（`LabelSet.wrap`）。配置の順は MapLibre と同じ（深いタイル、`wrap`、x、y）。**残り**：世界が画面より狭い（ズーム約 1 未満）ときは、同じタイルの別のコピーにはラベルが出ない（MapLibre はコピーごとに配置する）。
- 問い合わせ：描いた (タイル, コピー) ごとにワーカーへ聞き、ファサードは正準のタイルごとに地物を 1 回にまとめる（MapLibre の `mergeRenderedFeatureLayers`）。並びは z、y、wrap、x（`sortTilesIn`）。ラベルの当たりは配置したコピーでだけ。
- 塗りの輪郭は、層のすべてのタイルの塗りのあとにまとめて描くようにした（MapLibre の `drawFill`：全タイルの塗り、次に全タイルの輪郭）。コピーの境目（経度 ±180 の輪郭）で隣のコピーの塗りが輪郭を消していた。
- ファサード：`renderWorldCopies` オプション、`setRenderWorldCopies` / `getRenderWorldCopies`（undefined は true、null は false）。`map_set_limits` の 9 番目の数。
- 確かめ：`raster:golden` に世界のコピーの場面 5 つ（z0、z1、180 度、回転、`renderWorldCopies: false`）を足し、すべて MapLibre と画素まで同じ。傾けた場面は外した（遠くのタイルのズームの選び方が MapLibre と違うのは以前から）。`style:golden` に `copies-antimeridian`、`copies-wide`（各タイルが 2 つのコピーに出る、ヒートマップ込み）。`labels:golden` に `copies-points`、`copies-line`（69 場面すべて同じ）。`query:golden` に `copies`、`copies-wide`（750 問すべて同じ）。`style:golden` は全場面が限度内。`camera:golden` に `renderWorldCopies: false` の 3 場面（制約、easeTo、flyTo など）。core のテスト（`core/copies_test.mbt`）。
- 大きさ：mbt-map（index.js）は gzip 165.0KB → 166.4KB（+1.4KB、予算 168KB。main を取り込んだあとの数）。被覆の並べ替えはタイルの型で整列を実体化せず `stable_order` で並べる（UnwrappedTile 用の整列が約 10KB の生コードを足していた）。

## トップの地図：端末の時刻の東京、軽い版とテクスチャ（2026-11-15、Mac）

- 判断（ユーザー）：トップの 3D を端末の時刻で変える（実際の太陽の影、地図はライトグレーとダークグレー）。建物はテクスチャ付きの LOD2 も見せたいが、重さとの兼ね合いで「軽い版で始め、ボタンでテクスチャ」。
- `site/hero.js`：端末の時計の時刻を東京の時刻として、`sunPosition` と `timeOfDayLights` で太陽の向きと影（日が出ている間）を置き、太陽の高さ −6°〜+6° で地理院の淡色地図をダークグレーからライトグレーへ移す。夜は青みのある環境光を明るめに保つ（建物が見分けられるように）。1 分ごとに更新、`?time=18:30` で確かめられる。
- 測った通信量（読み込みが落ち着くまで、1280×900、昼）：これまでのトップ（テクスチャなし、ズーム 15.25・傾き 60°）は 89MB・16 秒で、トップページには重すぎた。視点を寄せて（ズーム 16.2・傾き 45°）、`maximumScreenSpaceError: 16` にして 25MB・4 秒。テクスチャ付き（WebP、Draco、1 タイル約 1MB）は同じ視点で約 64MB なので、「Textures」ボタンを押したときだけ読む。
- 追加の直し（同日、ユーザーの指摘）：傾けると地平線の上が暗い背景色のままだった（空を描いていなかった）ので、スタイルの `sky` と背景色も時刻で変える（昼は水色と明るい灰色、夜は濃紺）。夜は太陽の光がなく面に明暗が付かず、建物が一色のかたまりに見えたので、夜は影なしの弱い月明かり（南西から）を当て、環境光の紫を抑えた。

## Firefox と WebKit での pack test（2026-11-15、Mac）

- `bench/npm/pack-test.mjs` に `--browser=chromium|firefox|webkit`（既定 chromium。Metal の GPU フラグは macOS の Chromium だけ）と `--no-prepare`（前の pack を使い回す）を足した。WebGL2 か WebAssembly GC のないブラウザのビルドでは全項目を落とさず、理由を書いて飛ばす（CI では `::warning::`）。
- 版：Playwright 1.64.1、Firefox 157.0、WebKit 27.2（どちらも wasm-gc と WebGL2 あり）。
- Mac（fixtures あり）：直す前は Firefox 14/22、WebKit 18/22。直した後は Chromium・Firefox・WebKit とも 22/22。
  - Firefox：npm・element・geojson・media・custom・moonbit・services は、ライブラリが `console.error(error)` で出す想定どおりの誤りを、Firefox が中身なしの "Error" として Playwright に渡すため、許す誤りの一覧に合わなかった（テスト側。誤りの文はオブジェクトの `message` から取るようにした、`checks/step.mjs` の `watchErrors`）。services はほかに、壊れた XML を DOMParser に読ませたときの Firefox 自身の "XML Parsing Error" の報告。plateau は時間切れ：`setViewshed` と `setClipping` は 1 フレーム描くだけで `idle` は来ない（`idle` は中身が変わったあとに 1 回だけ）。チェックはそのあとの `idle` を待っていて、Chromium では道具を切り替えたときの `idle` がたまたまクリックのあとに届いていた（テストの競合。待ちを先に入れる `awaitAfter` にし、この 2 つは `render` を待つ）。
  - WebKit：ショーケース 3 つの断面図の点の位置（WebKit は `style.transform` の値を丸めて返す。0.01 px 以内で比べる `translatedTo`）。samples は ArcGIS のサンプルが読み込み中のワーカーを、次のサンプルへ移るときに WebKit が失敗として報告していた（サンプルごとに新しいページを開いて閉じる）。media は時々 idle が来ない：ループの頭で動画の `seeked` が idle をやり直させるのを当てにしていたが、WebKit は最初のループでしか seek しない（再生中に一度スタイルを変えて idle を待つ形に）。
- Linux（Docker の `mcr.microsoft.com/playwright:v1.64.1-noble`、arm64、fixtures なしで CI に近づけた）：
  - WebKit：直す前は npm・media・custom・model・services の 5 項目が落ち（17/22）、直した後 22/22。`antialias: false` の WebGL のキャンバスが 1 フレーム遅れて画面に出る（地図を描き直すまで最後のフレームが出ない。素の canvas を 1 回 clear するだけでも同じ、`antialias: true` なら出る）。テストでは画面を読む前に一度描き直す（`checks/pixels.mjs` の `screenshot`）。動画は 2D にも WebGL にもフレームが渡らない（`drawImage` も 0）ので、その環境では動画の画素を求めない。
  - Firefox：headless で WebGL2 が作れない（"AllowWebgl2:false"、`webgl.force-enabled` でも "Exhausted GL driver options"）。pack test は飛ばす。x86 の GitHub のランナーで同じかは確かめていない（Docker の空きが足りず amd64 の像を取れなかった）。
- ライブラリの直しはなし（失敗はすべてテストの前提か、ブラウザのビルドの制約だった）。
- CI：`pack-browsers`（`pack firefox …` / `pack webkit …`、小さいページとショーケース 3 つの 2 つずつ）を足した。必須の `moon` と `pack …` 4 つの名前は変えていない。
- 未解決：`setViewshed`・`setClipping`・`triggerRepaint` のあとに `idle` が来ないのは MapLibre（描き終えるたびに `idle`）と違う。合わせるかは別に決める。Linux の WebKit で最後のフレームが出ない件が headless だけのことか（実際の WebKitGTK の利用者にも出るなら、`antialias: true` か最後にもう 1 フレーム描くかを測って決める。MapLibre も `antialias: false` が既定）。Linux の Firefox の WebGL2。

## NOTICE と VISION の整理（2026-11-15、Mac）

- NOTICE（74.8KB、1278 行）を組み直した：1「mbt-map に含まれる第三者のコード」（移植ごとに、元のプロジェクトと URL、版、著作権表示、ライセンス、由来するファイル）、2「ライセンスの本文」（MIT、ISC、BSD 2-Clause、BSD 3-Clause、Boost 1.0、EDL 1.0、Unlicense を 1 回ずつ。Apache-2.0 は LICENSE）。MIT 16 回・ISC 13 回の同じ本文の繰り返しをやめ、46.4KB になった。名前を挙げる条項など文言が違うもの（MapLibre と Mapbox の BSD 3-Clause、Apple・flatgeobuf・TinySDF の BSD 2-Clause、topojson の旧い ISC、fdlibm）は、その部品の下にそのまま残した。1 行目の製品名を `mbt-map` に直した。
- 配布しないもの（テストデータ、フィクスチャ、bench の比べる相手）は `NOTICE-dev.md`（5.2KB、リポジトリだけ）に分けた。npm の tarball には `NOTICE` と `LICENSE` だけが入る（`npm/package.json` の `files` とビルドの写しは変えていない）。
- 確かめ（リポジトリの外のスクリプト）：著作権表示は前 71 行、後 71 行（NOTICE 61、NOTICE-dev 10）で欠けなし。URL 70、名前と版の組 72 も欠けなし。ライセンスの本文は空白の違いを除いて同じものだけをまとめた。
- ソースの先頭の表記と突き合わせて足したもの：earcut に `tess/earcut_holes.mbt`・`earcut_zorder.mbt`、flatqueue に `analysis/queue.mbt`、geotiff に `data_worker/js/geotiff-read.mjs`、style-spec に `moonbit/mbtmap/style/*.g.mbt`（`v8.json` の名前から生成）。
- 未解決（ユーザーの判断）：
  - mooncakes の `mbtmap` と `mbtmap_rabbita` のディレクトリに LICENSE と NOTICE がない（`moon.mod` の `license` だけ）。`moon publish` に入れるなら、それぞれに LICENSE と短い NOTICE（style-spec の BSD 3-Clause）を置く。
  - 振る舞いを合わせているが NOTICE にないもの：OpenLayers（`npm/src/services/` の GML の属性の読みと要求の形）、terra-draw（`npm/src/draw/` の既定のしきい値）、gl-matrix（`core/matrix.mbt` などの行列の演算）。コードを写したものなら項目を足す。
- VISION.md（44.8KB）を、いまも効いているものだけにした：ゴールと柱、性能目標とサイズ予算（`npm/scripts/size.mjs` に合わせた。メインは 168KB）、アーキテクチャの原則、設計原則、後回し・やらない、API 方針（MoonBit は npm の上の型付きの API と rabbita の部品）、作業ルール、これからの計画（0.1.0、単独の移植、Phase 21）。Phase 0〜20 の表、最初の指示（§9）、ほかのライブラリとの突き合わせ（§10）、パッケージの一覧、予算を上げた経緯は外した（mbmap にある）。節の番号（§1〜§8、§4 の 1〜10）は変えていないので、コードや文書の「VISION §n」はそのまま通る。
- 追加（本線）：MoonBit の 2 モジュールに `LICENSE` を置き、`mbtmap` には生成したスタイルの関数の出どころ（style-spec、BSD-3）を書いた `NOTICE` を置いた（mooncakes に出るのはモジュールのディレクトリだけなので）。ふるまいを合わせて書いた部分にも念のため記載を足した：OpenLayers（GML・WMS・WMTS の読み、BSD-2）、terra-draw（作図のモードとしきい値、MIT）、gl-matrix（行列とベクトル、MIT）。

## テストの見直し（2026-11-15、Mac）

- 依頼：意味の薄いテスト、ほかで保証されているテストを消すか作り直す。全テストの名前と、機械的に拾った弱い形（表明なし、`let _ =`、`is Some(_)` だけ、定数を定数と比べる、数行だけ）を読んだ。
- 結論：消すべきものは少なかった。MoonBit の約 990、npm の 446、bench の 20 のほとんどは、値を表明するか、参照ライブラリの値を埋め込むか、壊れた入力を拒むことを確かめている。`pub fn` で js のテストが 1 行も通らないのは純粋なパッケージ全体で 4 つだけだった（`ExtrusionBuffers::clear`、`Globe::projection`、`Globe::limits`、`PackedTile::length`）。
- 消した（同語反復）：`density` の「the contour caps」と `isolines` の「the segment and nesting caps…」（上限の定数を同じリテラルと比べるだけ。上限が効くことは別のテストが小さい予算で確かめている）、`tess` の `CIRCLE_GRANULARITY == 3` と `las.test.ts` の `MAX_LAS_POINTS == 10_000_000` の 1 行ずつ。
- まとめた：`globe` の「radius correction is 1 once drawn flat」を、同じ補正を確かめる隣のテストへ。
- 値の表明に強めた：`fill-sort-key` と同じ式の `circle-sort-key`（`is Some(_)` → 式そのもの）、180 度をまたぐ線の西端タイル（`is Some(_)` → 切られた座標 `[-64, 8178, 91, 8101]`）、`fit_box` のズーム（9〜11 の間 → `log2(1125)`）、`crsArg` の名前引き（`Float64Array` であること → その PROJ 文字列の定義と同じ）。
- 足した（CI で守られていなかったところ。golden は CI では 1 つも走らない）：
  - `proj/projections_test.mbt`：`proj:golden` の PROJ 文字列 43 個それぞれの 1 点を proj4js 2.22.0 の値と比べ、逆変換で戻す（`bench/proj/unit-cases.mjs` が書く）。`proj` の行カバレッジは 365/1674 → 1430/1674（擬円筒・平射・斜軸の各ファイルは 0 行だった）。
  - `clipper/libcxx_sort_wbtest.mbt`：同じキーの並びを libc++ 21 の `std::sort`（`bench/clipper/libcxx-sort-cases.cpp`、clang++ で作る）と 24 の大きさ × 7 の並びで比べる。`libcxx_sort.mbt` は 17/154 → 145/154。
  - `worker/js/wasm.test.mjs`：ビルドした表示ワーカーの wasm を Node で起こし、`prepare_input` が範囲外の長さを拒むこと、スタイルの前の呼び出しが文を返すこと、スタイルでないバイト列を `init_style` がトラップせずに拒むことを確かめる（`linear_memory.mbt` は whitebox テストが host の import を引くので moonrun では試せない）。`npm test` の前に `npm run build` が要る（CI はその順）。
  - `tess`：`ExtrusionBuffers::clear` のあとの再利用が新しいバッファと同じ出力になること。
- 見つけたこと：
  - `proj:golden` は 6 つの定義（球のカッシーニ、LAEA 3 つ、2 点の斜軸メルカトル、心射）で 1 点も比べていなかった。proj4js は `+x_0` / `+y_0` のない文字列に NaN を返し、golden は「proj4js の届かない点」として黙って外していた（エッケルト VI の逆変換も同じ）。文字列に `+x_0=0 +y_0=0` を足し、1 点も比べない行は失敗にした。足したあとも 97,200 点すべて 1 mm / 1e-8° 以内（最大 4.66e-9 m）。
  - `libcxx_sort` は深さの上限（2 log2 n）を越えると libc++ のヒープソートの代わりに安定ソートを使う（コードの注記どおり）。500 個以上のオルガンパイプ形の同値キーではそこへ入り、同じキーの並びが libc++ と違う。テストはこの違いを違いとして固定した。Clipper2 との一致が要る入力で起きうるかは未確認。
- 数（前 → 後）：`moon test --target all` は wasm 929、wasm-gc 941、js 987、native 929 で変わらず（3 つ減り 3 つ増えた）。npm は 446 → 449、bench は 20 のまま。js の行カバレッジは全体で 28467/39101（72.8%）→ 29664/39101（75.9%）。
- 残した候補（判断待ち）：`core` の「Trig's methods call its functions」（委譲を 12 個なぞる）、`proj` の「Trig::moonbit is what a CRS computes with by default」、`raster` の「LOG2_WORLD_WIDTH is the log written out」（手書きの定数を式と比べる）、`globe` の「copy leaves the original alone」、`bench/backend/kernel` の 2 つ。
- 残る穴：`clipper` の本体（`sweep.mbt` 62%、`horizontal.mbt` 54% など。`clipper:golden` は手元だけ）、`worker/query_geometry.mbt` 27%、`style/distance.mbt` 55%、`draco/edgebreaker_traversal.mbt` 38%。ほかの golden にも「比べた点が 0 の行」を失敗にする確かめが要るかは見ていない。

## バンドラでの動作（2026-11-15、Mac）

- 調べたこと：公開する配置のままでは、既定の設定で動くのは Vite の dev サーバだけだった。
  1. Vite のビルドと webpack は `new URL("./x-worker.js", import.meta.url)` のワーカーをハッシュ付きのアセットとして出すが、ワーカーが自分の隣から `import("./worker-query.js")` などで読む部品（`worker-labels.js`、`worker-pmtiles.js`、`worker-query.js`、`analysis-viewshed.js`、`data-{zip,crs,fgb,geotiff,reproject}.js`）は出力されず 404。`queryRenderedFeatures` は警告だけで `[]` を返していた。
  2. Vite のビルドは 4KB 未満のワーカー（`geodesic-worker.js`、`services-worker.js`）を `data:` URL に埋め込み、`workerScriptUrl` が断っていた。
  3. `workerScriptUrl` の `home` の既定値 `new URL("./", import.meta.url)` で Parcel はビルドに失敗し、Vite は `index.js` をもう 1 つアセットとして出していた。
- 直し：
  - `home` は `import.meta.url` の文字列から切り出す（`npm/src/urls.ts`）。
  - ワーカーの部品はメインスレッドが `new URL("./part.js", import.meta.url)` で名指しし（バンドラがアセットとして出す）、wasm の URL と同じく init メッセージの `parts` で渡す（`workerParts`）。ワーカーは渡された URL を import し、なければ従来どおり隣のファイル（ページが `workerUrl` を渡したとき、bench のページ）。表示ワーカーの分は `create_map` の最後の引数（`@map.WorkerParts`）から `post_init` へ。
  - `workerScriptUrl(given, own, …)`：ページが渡した `workerUrl`（`given`）の規則は変えていない（ページのオリジンか、ライブラリのフォルダ。`data:`・`blob:` は URL オブジェクトでも断る）。渡されないときのライブラリ自身の既定（`own`）だけ、バンドラが置いた場所を認める：http(s) ならどのオリジンでも（ページのオリジン以外は import するだけの blob 経由）、`data:` なら同じ中身の同一オリジンの blob から起動。`own` はライブラリのコードとバンドラが決める値で、実行時の入力（スタイル、属性、オプション）からは作れない。
  - CSP：埋め込まれたワーカーには `worker-src blob:`、ワーカーの中で `data:` から import される部品には `script-src data:` が要る。Vite では `build.assetsInlineLimit: 0` で埋め込みをやめれば `'self'` で足りる（docs/getting-started.md に記載）。
- 結果（`npm run bundlers`、Chromium、`bench/results/bundlers.json`。地図が描かれる、問い合わせが 2 地物を返す、analysis・data（CRS 付き、`data-crs.js` と `proj.wasm`）・geodesic が答える）：

| バンドラ | モード | 直す前 | 直した後 |
|---|---|---|---|
| Vite 8.3.8 | dev | 動く | 動く |
| Vite 8.3.8 | build | 部品が 404、埋め込みワーカーを拒否 | 動く（設定なし） |
| Vite 8.3.8 | build、アセットが別オリジン（`base`） | 未確認 | 動く |
| webpack 5.112.2 | dev / build | 部品が 404 | 動く（設定なし） |
| webpack 5.112.2 | build、別オリジンの `publicPath` | 未確認 | 動く |
| Rollup 4.68.3 | build（node-resolve と `@web/rollup-plugin-import-meta-assets` 3.0.1） | 部品が出力されない | 動く |
| esbuild 0.28.2 | build（ファイルを隣にコピー） | 動く | 動く（コピーするものは同じ） |
| Parcel 2.16.4 | dev / build | ビルド失敗 | ビルドは通るが動かない |
| Parcel 2.16.4 | build、ライブラリを束ねずに配る | 動く | 動く |

- Parcel：`new URL(…, import.meta.url)` で名指ししたファイルをすべて自分のモジュール形式に変換するため、モジュールワーカーと部品の export が失われる（dev は「the worker failed」、build は変換後のコードが構文エラー）。ライブラリ側では直せないので「dist を束ねずに配って実行時に import する」と文書にした。`bundlers` は Parcel の 2 行を既知の失敗として持ち、動くようになったら知らせる。
- 大きさ（gzip）：mbt-map（index.js）166.4KB → 166.7KB（+0.3KB、予算 168KB）。GeoJSON ソース 4.65 → 4.85KB（予算 5KB）、mbt-map/analysis 8.50 → 8.74KB（9KB）、mbt-map/data 4.87 → 5.14KB（6KB）、mbt-map/geodesic 1.41 → 1.61KB（2KB）、mbt-map/3d 9.26 → 9.46KB（10KB）、mbt-map/services 11.49 → 11.66KB（12KB）。`urls.ts` が各エントリに入るため。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`、npm のテストと大きさ、pack test（Chromium 23/23、WebKit の npm・cdn・geojson・analysis・data）、`npm run bundlers`。
- 残り：AGENTS.md §8.3 の「例外は 1 つ」の文は、ライブラリ自身の既定のワーカー（バンドラが置いた場所、`data:` の埋め込み）をまだ書いていない。`bundlers` はバンドラを npm から取るので CI には入れていない。Rollup でプラグインなしにファイルをコピーする形と、Firefox・WebKit でのバンドラの出力は確かめていない。

## 公開前の整理：使っていないものを外す（2026-11-15）

監査で見つかったもののうち、ユーザーが認めた分を外した。追跡しているファイルは 1530 個・11.5MB から 1492 個・9.2MB になった。外した実験（バックエンドの比較、モジュール分割の計測）のスクリプトと結果は、前のリポジトリ `t-ujiie-g/mbmap` に残っている。

- **点群のフィクスチャ**：`bench/npm/pages/pointcloud/cloud.las`（1.2MB）を追跡から外した。`bench/las/synthetic.mjs` が毎回同じものを作れるので、パックテストの準備（`bench/npm/prepare.mjs`）が書き、`las:golden` は同じバイト列を関数から受け取る。
- **bench の依存**：どこからも import していない `@turf/difference`、`@turf/points-within-polygon`、`robust-predicates` と、下の実験だけが使っていた `binaryen` を外した。
- **結果のファイル**：一度きりの `draw-many-{before,after}-*.json`（6 個）を消した。`render-chromium*.json` と `maplibre-render-chromium*.json` は中央値などの要約だけにし、各回の値は `*.raw.json`（コミットしない）に書く。`query`・`globe`・`proj`・`las` の黄金テストは、要約と合わなかった行だけを書く（読むスクリプトも文書もなかった）。`bench/results/` は 1.5MB から 0.6MB。描画の数字は古いので、本線で測り直す。
- **bench/entry**：呼ぶスクリプトのない export（`geojson_read`、`geojson_tiler_table`、`geojson_tile_mem`、`last_counts`）を消した。
- **adapters/**：README だけの予約場所だった。役目は `moonbit/mbtmap_rabbita/` が果たしている。
- **bench/backend と bench/split**：Wasm バックエンドの比較（Phase 0）とモジュール分割の計測（Phase 6.5）。結論（wasm-gc で出す、wasm-gc に `wasm-opt` をかけない、入口ごとに 1 つの wasm）は docs/dev/TOOLCHAIN.md と AGENTS.md §4 に事実として残し、MoonBit のパッケージ、スクリプト、npm の `backend:*`・`split`・`opt`、結果の `backend-*.json`・`split.json` を消した。`build:moon` は wasm（線形メモリ）のビルドと `wasm-opt` をしなくなった。
- **CI**：`pack` と `pack-browsers` は npm パッケージを 2 回ビルドしていた（ジョブの手順と `prepareExamples()`）。手順の方を外した。`prepare.mjs` は、`examples/react/node_modules` がロックファイルどおりなら `npm ci` をやり直さない（npm が書く `node_modules/.package-lock.json` と比べる）。
- **型定義**：tsc は内部のモジュールごとに `.d.ts` を書くので、tarball に 104 個入っていた。ビルドの最後に、`package.json` の `exports` の `types` から相対 import をたどって届くものだけを残す（`npm/scripts/declarations.mjs`、64 個）。たどった先がなければビルドが失敗する。11 の入口すべてを `moduleResolution` が `NodeNext` と `Bundler` の tsc（`skipLibCheck: false`）で読めることを確かめた。
- **MoonBit の `pub`**：パッケージの外から使われていない上限の定数や補助の関数を非公開にした（`clusters`、`core`、`delaunay`、`density`、`draco`、`globe`、`hull`、`isolines`、`relate_worker`、`render_webgl2`、`route`、`simplify`、`tiff`、`viewshed`、`xml` の計 38 個）。それを名前で使っていたブラックボックステストは、中身を変えずにホワイトボックスのファイルへ移した。単独で出すかもしれない移植（`clipper`、`relate`、`proj`、`geodesic`、`mvt`、`pbf`、`tiler`、`tess`）、JS のテストが写しを確かめる定数（`worker` の `ENTRY_*`、`core` の `MAX_ZOOM`・`MAX_PITCH`）、トレイトの実装はそのまま。**残したもの**：ブラックボックステストがファイル内の補助関数と一緒に使っている上限など（`formats`、`style`、`tiff`、`isolines`、`kml`、`analysis` など約 35 個）は、テストのファイルごとホワイトボックスにするか補助関数を写すことになるので公開のままにした。
- **文書**：`examples/README.md` にサンプル集（`examples/samples/`）、docs/dev/COMMANDS.md に `las:synthetic`・`tiles:synthetic`・`i3s:synthetic`・`i3s:pcsl-synthetic`、`bench/README.md` に結果の置き方。

## サイトの計測タグ（2026-11-15）

- ユーザーの依頼で、GitHub Pages に Google タグ マネージャー（`GTM-MWGLDWNP`）を入れた。`site/analytics.js` を、サイトの各ページ（トップ、文書、例の目次、サンプルの解説ページ、4 つのアプリ）が読む。解説ページに埋め込んで動かすサンプル本体には入れない（閲覧の二重計上と、見せるコードへの混入を避ける）。
- 公開先（`t-ujiie-g.github.io`）で開いたときだけ読み込む（ローカルの確認や CI を計測に混ぜない）。もらったスニペットに、GTM の「全ページ」のトリガーが動くよう公式の `gtm.start` の合図を足した。フッターに入れた「Google Analytics で訪問を数えている」の一文は、一般的でないので外した（ユーザー判断）。

## 公開前の QA の直し：タッチ操作、`idle`、`<mbt-map>`、キャンバスの名前、バッファ（2026-11-15）

公開前の QA で見つかった 5 件。ブランチ `fix/touch-and-events`。

1. **タッチ操作がページに漏れる（ブロッカー）**
   - 原因：キャンバスの `touch-action` が `auto` のままで、リスナーも passive。スマートフォンで地図をピンチするとブラウザもページを拡大し（`visualViewport.scale` が 1 → 5）、1 本指のドラッグでページもスクロールした。
   - 直し：MapLibre のキャンバスコンテナと同じ値を、有効なハンドラからキャンバスの `touch-action` に入れる（`map/camera.mbt` の `touch_action`。`attach_input` と `Map::set_handler` で設定するので `map.dragPan.disable()` などにも追随する）。`dragPan` と 2 本指のハンドラ（`touchZoomRotate` か `touchPitch`）の両方 → `none`、`dragPan` だけ → `pinch-zoom`、2 本指だけ → `pan-x pan-y`、どちらもなし（`interactive: false` も）→ `auto`。`touchPitch` は MapLibre では値に関わらないが、2 本指の操作なので `touchZoomRotate` と同じ扱いにした。cooperative gestures は入れていない。
   - `touch-action` を見ないブラウザのために、地図が受け取る操作の `touchmove` は passive でないリスナーで `preventDefault` する（`Map::takes_touches`）。`wheel` はもとから passive でなく、`scrollZoom` が有効なあいだ `preventDefault` している（確かめた）。
   - テスト：pack test の `touch`（`bench/npm/checks/touch.mjs`、ページ `bench/npm/pages/touch/`：ビューポートより長いページに `Map`・`<mbt-map>`・ただの箱）。タッチ有効の 400 × 700 のコンテキストで、Chromium では CDP の `Input.dispatchTouchEvent` で本物のタッチを送る：ピンチのあと `visualViewport.scale` は 1 のままズームが 14.5 → 17.08（`Map` もシャドウルートの中の `<mbt-map>` も）、1 本指のドラッグのあと `scrollY` は 0 で中心が動く、`dragPan` を切ると同じドラッグでページが 105 px スクロールして地図は動かない、ただの箱の上の同じピンチはページを 3 倍にする（テストの仕掛けが漏れを見つけられることの確認）。ハンドラごとの `touch-action` の値とホイール（ページは動かずズームだけ変わる）は 3 つのブラウザで見る。Firefox と WebKit には CDP のタッチ入力がないので、本物のタッチの部分は理由をつけて飛ばす。`touch_action` の単体テストは `map/helpers_wbtest.mbt`。

2. **1 フレームだけの変更のあとに `idle` が来ない**
   - 原因：`idle` は「前の変更のあと最初に落ち着いたフレーム」で 1 回だけ出していて（`idle_fired`）、`setViewshed`・`setClipping`・`triggerRepaint` は `idle_fired` を倒さずにフレームだけ頼んでいた。
   - 直し（`map/render.mbt`）：MapLibre の `_render` と同じく、フレームの終わりに、読み込み中のものがなく（タイル、ワーカーに聞いている feature state の範囲）、動いておらず（操作・慣性・アニメーション：`moving`）、次のフレームも頼まれていなければ `idle`。止まっている地図はフレームを描かないので繰り返さない。
   - MapLibre と違えたところ：フレームが続くあいだ（再生中の動画、`render` の中で `triggerRepaint` するカスタムレイヤー）は、落ち着いた最初の 1 回と、止まったときの 1 回だけ（MapLibre は毎フレーム）。`toBlob` が `idle` を待つので、最初の 1 回は残した。
   - 変わったところ：アニメーションや操作の途中では `idle` が出なくなった（これまではタイルがそろっていれば途中でも出ていた。MapLibre は出さない）。操作の終わり（指を離す、ホイールの 200 ms 後）に 1 フレーム頼むので、そこで `idle` が来る。
   - テスト：pack test の `npm` に `idleChecks`（`bench/npm/checks/idle.mjs`）：止まっているあいだは 0 回、`triggerRepaint`・`setClipping`（設定と解除）・`setViewshed`（設定と解除）のそれぞれで描画 1 回と `idle` 1 回、`easeTo` の `moveend` までは 0 回、毎フレーム `triggerRepaint` するリスナーでは止まったときの 1 回だけ、そのあとの `toBlob` が返る。`bench/npm/checks/plateau.mjs` の回避（視域と断面は `render` を待つ）は `idle` を待つ形に戻した。

3. **`<mbt-map>` に `render-world-copies` がない**：属性 `render-world-copies`（`true` / `false` だけ。ほかは `mbt-map-error` で前の値のまま）とプロパティ `renderWorldCopies`（真偽値か属性の文字列）を足した。地図があれば `setRenderWorldCopies`、作り直しても値を持ち越す。`element/parse.ts` に `checkBoolean`、テストは `element/parse.test.ts` と pack test の `touch`。

4. **キャンバスの役割と名前**：`tabindex="0"` でフォーカスできるのに role も名前もなかった。MapLibre 6.16 と同じく `role="region"` と `aria-label="Map"` を付ける（`npm/src/index.ts`）。コンテナに `aria-label` があればそれを名前にし、`<mbt-map aria-label="…">` は自分の値をキャンバスへ渡す（属性の変更にも追随）。あとから `map.getCanvas().setAttribute("aria-label", …)` でも変えられる。MapLibre は `interactive: false` のとき `tabindex="-1"` にするが、そこは変えていない。テストは pack test の `touch`。

5. **`mbt-map/analysis` の `buffer` の距離**
   - 負の距離：Clipper のオフセットは開いたパスと点を距離の絶対値で太らせるので、点と線の `-100` が `+100` と同じ結果になっていた。負の距離では点と線を入れない（`overlay/ops.mbt`）。結果は Turf の `buffer`（点と線の負のバッファは undefined）と同じく図形なしで、行と属性は残る。ポリゴンはこれまでどおり縮む。
   - 大きな距離：測地バッファの上限を 20,000 km から 10,000 km（`@overlay.MAX_GEODESIC_BUFFER`、子午線の 4 分の 1）にした。超えると `a geodesic buffer takes at most 10,000 km` で断る。点の円が半球に収まる範囲で、その先は円が対蹠点側の小さい円になり、リングとして意味を持たない。平面バッファは CRS の単位で 1e9 まで（変えていない）。
   - QA が「でたらめ」とした `999999`（12 点で 37,519,784 km²）は正しかった：半径約 1,000 km の円 1 つが約 3.13 百万 km²、12 個で 37.5 百万 km²（重なりは足したまま）。GeographicLib で測った点の円の誤差は、緯度 0〜89.9° で 100 km が 0.01% 以下、1,000 km が 0.08% 以下、3,000 km が 0.23% 以下、10,000 km が 0.58% 以下。
   - 文書（docs/analysis.md）：負の距離、上限、精度、経度が ±180 を越えても折り返さないこと、極を越えるバッファは極を囲むリングになること。
   - テスト：`overlay/overlay_wbtest.mbt`（点と線の負のバッファは `NoGeometry` で属性は残る、上限とその文言）、pack test の `analysis`（点の `buffer(-100)` は geometry が null、`buffer(1.5e7)` は断る）。

- 大きさ（gzip）：mbt-map（index.js）166.7KB → 166.9KB（+0.2KB、予算 168KB）。mbt-map/element 1.71KB → 1.86KB（予算 5KB）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 929、wasm-gc 941、js 988、native 929）、npm のテスト（453）と大きさ、bench のテスト、pack test（Chromium・WebKit 27.2・Firefox 157 とも 24/24。本物のタッチは Chromium だけ）、`camera:golden`・`globe:golden`・`query:golden`（750/750）・`export:golden`・`clipper:golden`（全部一致）・`buffer:check`・`sight:golden`（0 differ）。
- 残り：実機（iOS Safari、Android Chrome）でのタッチは確かめていない（Playwright の Chromium のタッチ入力まで）。`interactive: false` でもキャンバスは `tabindex="0"` のまま（MapLibre は `-1`）。バッファは日付変更線や極で切らない。

## サイト・サンプル・例の公開前 QA の直し（2026-11-15、Mac）

公開前の QA で見つかった、サイト（`site/`、`bench/site/`）・サンプル（`examples/samples/`）・例のアプリの不具合を直した。ライブラリ（`npm/src`、`element/`、MoonBit）は触っていない。

- **切れたリンク**：サイトに出していない `examples/element/` へのリンクが 3 か所にあった。
  - トップのカードは Web コンポーネントのサンプル（`examples/web-component.html`）へ。
  - ショーケースの見出しのリンクは、ページの `<html data-variants="…">` に名前のあるものだけにした（`examples/shared/shell.js` の `variants()`。サイトのビルドが `SITE_EXAMPLES` を書き込む。リポジトリから開けば 3 つとも）。React も同じ関数を使う。
  - `docs/getting-started.md` の「three styles」は、HTML と React（リポジトリには要素だけの版も）と書き直した。
  - `bench/site/dead-links.mjs`：ビルドした `_site/` の全ページの `href` / `src`（`<pre>` の中の見せているコードは除く）がサイト内のファイルに届くこと、`#` がその先のページの id にあること、ショーケースの `data-variants` の先があることを確かめる。`bench/site/build.mjs` は 1 つでも切れていれば失敗する。直す前のビルドに当てると `index.html: ./examples/element/` だけを挙げた。`bench/lib/site.test.mjs` にテスト。
- **ショーケースの Globe**：既定の地図（GSI のベクトルタイルは z4 以上・日本だけ）で地球にするとベージュの球になり、2D に戻してもズーム 2 のまま真っ白だった。
  - ズーム 4 未満に GSI の標準地図（`std`、世界の z0〜。`?local=1` では `bench/fixtures/gsi-std-world` の z0〜3）をラスタで敷く（`examples/shared/style.js` の `world`。レイヤーの `maxzoom: 4`）。
  - 地球に入るときの中心とズームを覚え、地球から出るときに戻す（`modeEase(mode, zoom, back)`。その間に元より寄っていれば戻さない）。HTML・要素・React とも。
- **コピーしても動くサンプル**：サンプルのページは `main.js` と `index.html` のほかのファイルも載せる。テキスト（`style.json` など、拡張子で決める）は 3 つめのコードとして、バイナリ（`tower.glb`）はサイトの絶対 URL のリンクとして載せ、見せるコードの中の `"./tower.glb"` もその URL にする。全 23 サンプルの見せているコードを別オリジンに置いて開き直し、どれも描けてエラーなし（Chromium）。
- **光**：
  - `examples/samples/buildings-shadows`：19:00（日没）で建物だけが黒かった。太陽の高さ 10° から地平線にかけて、影を薄くし、環境光を足し、地面のレイヤーの色を暗くする。
  - `site/hero.js`：日の出・日の入りの前後で建物が夜より暗い平らな塊になり、朝は日の当たる壁が白く飛んでいた。光を太陽の高さ（-6°・0°・10°）の折れ線にした：環境光と平行光の和は 0.96 まで、薄明の環境光は夜より明るく、影は 0°〜10° で濃くなる。平行光の向きは地平線の下で月（南西）から太陽へ回し、太陽は天頂から 68° より低くは描かない（すれすれの光では屋根が暗く、影が全面を覆う）。`?time=` は 00:00〜23:59 だけ読む。
- **サンプルの細かい直し**：`draw` の Ctrl+Shift+Z（`e.key` が "Z" になる）、`classify` の凡例の数（小数 1 桁まで）、`buffer-voronoi` の距離の確かめとエラーの表示、`web-component` のズームボタン（0〜22 で止める）、`measure` のクリック直後の長さ 0 の区間、`read-data` の「1 rows」とファイル入力の名前、`wmts-wms` はレイヤーを選ぶたびに中心のタイルを 1 枚確かめて、なければそう書く。GSI の淡色地図を使うサンプルとトップの地図は `minzoom: 2`。`terrain` は標高タイルの `bounds` で海の上のタイル（404）を求めない。スライダーの `<label>` は `for` で結んだ。
- **スマホの幅**：docs のナビゲーションは `<details>` にして `site/theme.js` が 860px 以下で畳む（全 13 ページで見出しが最初の画面に入る）。長いインラインコードは折り返す（`style-support.html` の横スクロールがなくなった）。PLATEAU の例の出典は上に移した（下のパネルに重なっていた）。
- **ショーケース**：サービスの URL に届かないときの「Failed to fetch」を、URL と CORS を確かめるよう促す文にした（`serviceError`）。
- **直していないもの（ライブラリ側、または仕様どおり）**：
  - 平行光が 1 つなので、光に背を向けた面はどれも環境光だけの同じ色になる（`npm/src/model/draw.ts` の `max(dot(n, l), 0)`）。トップの地図を太陽の反対側から見たときの一様な灰色はこれで、サイトの側では直せない。半球光か補助光がライブラリに要る。
  - スタイルの途中に置いた半透明の `background` レイヤーが、地面ではなく押し出しの建物の上にだけ描かれる（`buildings-shadows` で地面を暗くするのに使おうとして分かった。サンプルは地面のレイヤーの色を変える形にした）。
  - `?local=1` のショーケースで Globe のあと 3D を押すとページが固まる（直す前のコードでも同じ。DEM が z14 だけのスタイルでズーム 2 から地形つきに入るとき。GSI の実タイルでは起きない）。
  - ショーケースのコロプレスの区切りの最後が重なる（`… / 24.91 / 24.91`）のは `classBreaks` の jenks が simple-statistics と同じく各クラスの下限と最大値を返すためで、いちばん上のクラスが 1 つの値だけのときに起きる。
  - OpenFreeMap のスタイルの `symbol-placement` の式の警告、Firefox の WebGL の性能の警告、GSI のデータの質。
- 確かめ：`npm --prefix bench test`（20 → 21）、`node site/build.mjs`（切れたリンクなし）、pack test の `samples,showcase-html,showcase-element,showcase-react,plateau,rabbita,globe`（Chromium）と `samples,showcase-html`（WebKit）、`node bench/lib/long-comments.mjs`（46 のまま）。

## 公開前のライブラリの直し：`updateData`、背景の描く順、地形で固まる件（2026-11-15、Mac）

公開直前に見つかった 3 件。ブランチ `fix/update-data-and-draw-order`。

1. **`updateData` で `removeAllProperties` と `addOrUpdateProperties` を一緒に渡すと、描かれるデータの属性が消える**
   - 原因：`tiler/source.mbt` の `Source::updated_row` が、@maplibre/geojson-vt 6.3.0 の `applyPropertyUpdates`（`removeAllProperties` なら `{}` を返して終わり）をそのまま移していた。ファサードの `npm/src/geojson-diff.ts`（MapLibre の `applySourceDiff`）は消してから足すので、`getData()` は正しいのにタイルの属性は `{}`、`promoteId` の id は null になり、式は既定値に落ち、feature state は出ず、クエリの属性は空だった。`createFieldEditor`（`propertiesDiff`）はいつもこの形を送るので、フィールド演算・改名・削除のたびに起きていた。
   - 直し：消してから足す（MapLibre の `applySourceDiff` と `GeoJSONSourceDiff` の文書どおり）。geojson-vt からの意図した逸脱で、コードの 1 行と docs/dev/ARCHITECTURE-MODULES.md に書いた。`ClusterIndex::update` も同じ `Source` を通る。`remove_all_properties` を読むのはここと `has_property_changes` だけ。`promoteId` の id は表示ワーカーが属性から読む（MapLibre と同じ）ので、足した属性に入っていれば戻る。
   - 上流：geojson-vt は 6.3.1 と main でも同じ（直っていない）。bench の版は 6.3.0 のまま。
   - ゴールデン：`geojson:diffs` は種つきの差分にこの形が 66 件ある。比べる相手には同じ意味の差分（それまでに出たすべてのキーの `removeProperties` と足す分）を渡す（`forReference`。除外はしない。docs/dev/COMMANDS.md）。18 run、510 差分、189,981 タイルで 0 differ。`geojson:update`（ファサード対 MapLibre）は all identical、`geojson:golden` 0 differ（8,148 タイル）、`cluster:golden` 0 differ。
   - テスト：`tiler/update_test.mbt`（全消し＋追加、全消しだけ、一部を消して追加。全バックエンド）。pack test の `geojson`（`bench/npm/checks/update-data.mjs`）：直す前は `queryRenderedFeatures` が `{}`、`promoteId` のソースは id が消えて 0 件、円は既定の青のまま。直した後は `queryRenderedFeatures`・`querySourceFeatures`・`getData` とも `{kind: "b", note: "new"}`、円は式どおり赤、`promoteId` のソースは feature state の緑。

2. **背景レイヤーがスタイルの順番で描かれない**
   - 原因：色の `background` は「最初に見つかった 1 枚」を画面の消去色に使うだけで（`Map::background`）、途中に置いた背景は描かれず、2 枚目以降は無視されていた（平面・地形とも。球と模様だけ順番どおり）。半透明の背景を塗りの上・立体の下に置いても塗りに色が乗らなかった。
   - MapLibre の順番（`painter.ts`）：最初の 3D レイヤー（`opaquePassCutoff`）以降は 2D レイヤーの深度テストが切れる（`getDepthModeForSublayer` が `DepthMode.disabled`）。つまりレイヤー順そのままで、立体より上の半透明の塗り・ラスタ・背景は立体の上に乗り、下のものは立体に隠れる。立体の層の「あいだ」に置いた背景は、下の層の立体には乗り、上の層の立体には隠れる（地面だけに乗るのは立体より下に置いたとき）。塗りとラスタはもとからこの順だった。
   - 直し：消去色に使うのは、そのズームで見えるいちばん下のレイヤーが色の背景のときだけ（`Map::base_background`）。それ以外の背景は、置かれた位置で、視野を覆うタイルごとに描く（`Map::draw_background`。球の `draw_globe_background` を平面にも使う。地平線より上の空には乗らない）。地形ではテクスチャの中に順番どおり描く（`map/terrain.mbt`）。
   - テスト：`style:golden` に 4 場面（`background-under-extrusions` 平均 0.13、`background-between-extrusions` 0.093（上に半透明の塗りも）、`background-over-horizon` 0.228、`globe-background-between-extrusions` 0.012。どれも p99 0）。全 69 場面が限度内。地形の場面は入れられなかった（上の「未解決」）。目で見た限り、地形の hillshade の上の半透明の背景は正しく乗る。

3. **`?local=1` のショーケースで Globe → 3D と押すとページが固まる**
   - 原因：フィクスチャの DEM はズーム 14 だけ。Globe でズーム 2 まで引いたあと 3D にすると、地形のタイル選び（`render_terrain` → `@core.Transform::covering_tiles(14, 14)`）が、カメラから 6 距離以内の地面を `min_z` のタイルで埋めようとして、見えている世界のほぼ全部を z14（4^14 枚の規模）まで割っていた（Playwright で再現し、CDP で止めたスタックが `covering_tiles` ← `render_terrain` ← `draw_frame`）。`MIN_ZOOM_SLACK` の判定が、`min_z` まで引き上げられた `max_z` を「カメラが望むズーム」として使っていた。本番の DEM（ズーム 1〜14）では起きない。
   - 直し（`core/covering.mbt`）：望むズームをカメラ自身のタイルズーム（`tile_size` つき）から測り、それより深くは割らない（`min_z` がそれより深いときだけ `min_z`）。`min_z` が望むズームより `MIN_ZOOM_SLACK`（2）を超えて深ければタイルなし。これで枚数は入力によらず抑えられる。呼び出し側（`Map::cover`、地形）は `tile_size` を渡す。ズームが `min_z` 以上のときの結果は変わらない（`camera:golden`、`globe:golden`、`raster:golden` のタイル URL、`query:golden` 750/750）。DEM の最小ズームより 2 を超えて引いた地形は何も描かない（MapLibre も地形のソースの `minzoom` 未満ではタイルを選ばない）。
   - テスト：`core/covering_test.mbt`（ズーム 2 で `(14, 14)` は 0 枚、`(0, 24)` は 100 枚未満で z ≤ 2、ズーム 11〜13 では近くに z14 のタイル）。pack test のショーケース 3 つに「Globe → 3D」：クリックが返り、ピッチ 60 まで動いて次のフレームが描かれる（直す前はクリックが 30 秒で時間切れ）。

- 大きさ（gzip）：mbt-map（index.js）166,922 → 166,971 バイト（166.9KB → 167.0KB、+0.05KB、予算 168KB）。`geojson.wasm` は変わらず。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 930、wasm-gc 940、js 989、native 930）、npm のテスト（457）と大きさ、bench のテスト、pack test（Chromium、24/24）、`geojson:golden`・`cluster:golden`・`geojson:diffs`・`geojson:update`・`style:golden`（69/69）・`raster:golden`・`query:golden`（750/750）・`globe:golden`（794 比較、タイルの違い 0）・`camera:golden`（331 比較）、`long-comments`（47 のまま）。Firefox と WebKit の pack test は回していない。

## サンプル：属性テーブルとフィールド演算（2026-11-15）

- ユーザーの要望（属性テーブルの例がない、フィールド演算を見せたい）で `examples/samples/attribute-table/` を足した（一覧では Tools の先頭）。世界の国（Natural Earth 1:110m、176 件）を地図と表で見せる。表は `createAttributeTable`（見出しで並べ替え、絞り込み、行の選択を feature state で地図に、`zoomTo`）、地図のクリックで行を選んで表をそこまで送る。`createFieldEditor` で式（JSON のスタイル式）から列を足し、見出しから改名・削除できる。プリセットは 4 つ（1 人あたり GDP、人口の割合、1 億人以上、経済規模）。数値の列は `classBreaks`（分位・jenks・等間隔）と `classStep` で塗り分け、凡例を出す。地球儀の切り替えつき。
- データ `countries.json`（177KB、gzip 約 56KB）はサンプルのフォルダに置いた。座標は小数 2 桁、南極は外した（人口と GDP が仮の値で、1 人あたり GDP の階級を 1 つ占めてしまう）。出典は NOTICE-dev.md。
- **ライブラリの不具合（直していない）**：`updateData` の 1 つの更新に `removeAllProperties: true` と `addOrUpdateProperties` の両方があると、ワーカー側（`tiler/source.mbt` の `Source::updated_row`）は足す分も捨てるので、描かれるフィーチャーの属性が空になり、`promoteId` の id も失われる（`getData()` は正しい値を返す：`npm/src/geojson-diff.ts` は消してから足す）。`createFieldEditor` の `propertiesDiff` は常にこの形を送るので、フィールド演算のあと、属性で塗る式は既定値になり、feature state も `queryRenderedFeatures` の属性も消える。サンプルは編集のたびに `setData` で全体を渡し直して避けている（直ったらその 2 行を消す）。
- 足りないもの：表の行がどのページにあるかを id から知る方法がない（地図で選んだ行へ送るため、サンプルは 1 ページに全行を入れて自分でスクロールする）。`zoomTo` は経度 180° をまたぐ国（ロシア、フィジー）で世界全体に合わせる。
- 確かめ：Chromium と WebKit で、人口の降順（中国、インド、米国）、「land」の絞り込み（12 件）、行と地図の相互選択、プリセットの値（日本 40,247 = gdp×1e6/population）、塗り分けと凡例、不正な式（何も変わらずエラー表示）、改名と削除、390×844。pack test の `samples`（Chromium、WebKit）、サイトのビルド、`npm --prefix bench test`。
- 追記：#38 で `updateData` が直ったので、サンプルに入れていた回避（計算のたびに `setData` で丸ごと入れ直す）を外した。サイトのサンプルのページは、20KB を超えるデータファイル（`countries.json`）をコードとして出さずリンクにする。

## 公開前の最後の点検（2026-11-15、Mac M2）

全部がマージされた `main`（#39 まで）で確かめた。

- **セキュリティ**（AGENTS §8）：`npm audit`（npm、bench、examples/react）0 件、Dependabot と秘密情報の警告 0 件。npm のタールボールに余計なファイルなし。workflow の権限は最小（書き込みは Pages の配備と GitHub のリリースだけ）、Actions は SHA で固定。
- **ゴールデン**：60 本すべて通過（ネットワークと GDAL の要るものも）。その後の直し（#36、#38）で関係するものは各 PR で回し直した。
- **pack test**（24 項目）：Chromium、Firefox 157、WebKit 27.2 のどれも 24/24。
- **描画の計測**（`npm run render` とその変種、Chromium、1280×800、11 回の中央値。計測は単独で順に）：
| 条件 | mbt-map 最初の描画 / フレーム CPU 中央値 / p95 | MapLibre 6.16 同 |
|---|---|---|
| 基本 | 131 ms / 0.86 ms / 1.54 ms | 211 ms / 1.63 ms / 2.46 ms |
| 上限なし | 139 ms / 2.21 ms / 2.69 ms | 228 ms / 1.74 ms / 2.83 ms |
| ラベル | 230 ms / 0.70 ms / 1.71 ms | 269 ms / 1.67 ms / 3.04 ms |
| ラベル・上限なし | 243 ms / 2.12 ms / 2.51 ms | 278 ms / 1.19 ms / 2.64 ms |
| 線に沿うラベル | 233 ms / 0.71 ms / 1.89 ms | 284 ms / 1.74 ms / 3.13 ms |
| 地形 | 197 ms / 0.92 ms / 1.82 ms | 465 ms / 1.40 ms / 2.62 ms |
| 地形・傾き 85° | 249 ms / 1.52 ms / 2.75 ms | 349 ms / 1.55 ms / 2.88 ms |
| ラベル・地形 | 301 ms / 1.04 ms / 2.31 ms | 550 ms / 2.86 ms / 4.42 ms |
| 建物 | 248 ms / 1.04 ms / 1.91 ms | 396 ms / 1.79 ms / 2.72 ms |
| 建物・影 | 242 ms / 1.30 ms / 2.26 ms | 399 ms / 1.80 ms / 2.61 ms |

  - **見つけた退行と直し**：地形ありのフレームの CPU が増えていた。地形で手前の低い土地が欠ける件の直し（#22）で、覆うタイルの計算が、見に行くタイル 1 枚ごとにその高さの幅の視野の形（光線 8 本と凸包）を作り直していたため。同じ高さの幅の形は 1 回の計算の中で使い回すようにした（`core/covering.mbt`、選ぶタイルは同じ）。同じ状態で続けて測った地形の条件：#22 の前 0.79 ms、直す前の `main` 1.23 ms、直した後 0.92 ms（MapLibre は 1.38〜1.44 ms で安定）。最初の描画は 196〜199 ms で変わらない。残る +16% は、タイルごとの高さの幅を見るようになった分。
  - 古い結果ファイルの数字とは、計測した時期が違い MapLibre 側も大きく動く（例：地形 2.31 → 1.40 ms）ので、そのままは比べない。比べるときは同じ状態で続けて測る。
- **ワーカー**（`worker:browser`、35 タイルの `process_tile` の中央値）：Chromium 7.81 ms、Firefox 11.38 ms、WebKit 8.56 ms（前の記録は 7.53 / 10.68 / 8.20 ms。ワーカーのコードはほぼ変えておらず、ゆらぎの範囲）。
- **作図**：`draw:setdata` は頂点 10〜1000 で中央値 16.6 ms（1 フレーム）、`draw:many` は 2000 図形で中央値 32.8 ms（2 フレーム）。
- **CHANGELOG**：0.1.0 の節に、読み込み方（CDN、バンドラ）、対応ブラウザ、世界のコピー、タッチ操作を足した。
- **残り**：ユーザーが行う公開（docs/dev/RELEASING.md「初めての公開」）。実機のスマホ（iOS の Safari、Android の Chrome）でのタッチ操作は未確認。

## 0.1.0 の公開（2026-11-15）

`main` の #40（`631b6f9`）を 0.1.0 として出した。

- **npm**：`mbt-map@0.1.0` を手元から公開（127 ファイル、展開して 2.5 MB）。信頼された公開（GitHub Actions、`release.yml`、段階公開だけ）を設定済み。
- **mooncakes**：`t-ujiie-g/mbtmap@0.1.0`、`t-ujiie-g/mbtmap_rabbita@0.1.0` を手元から公開。
- **タグ `v0.1.0`**：`release.yml` の `verify`・`npm`（もうあるので飛ばす）・`github-release` と `pages.yml` が成功。
- **公開後の確かめ**：jsDelivr の `mbt-map@0.1.0` だけを指す HTML 1 枚を Chromium で開き、ラスタと GeoJSON の点が描かれ `queryRenderedFeatures` が答えること（別オリジンからのワーカーと wasm）。サイトのトップとサンプルが開き、コード欄の import map が jsDelivr の 0.1.0 を指すこと。
- **気をつけること**：信頼された公開は設定から 2 日以内に最初の公開がないと期限が切れる。次の版のタグの前に npm の設定を見る。

## 公開後の小さい直し（2026-11-16、Mac）

0.1.0 の前に見送ったもののうち、小さいもの（ユーザーが範囲を決めた）。ブランチ `fix/small-leftovers`。描画（世界のコピーごとのラベル、地形の上の `background-pattern`）と 3D の半径は見送りのまま。3D モデルの半球光と、バッファを日付変更線・極で切る件は別の PR。

- **`interactive: false` のキャンバス**：`tabindex="-1"` にした（MapLibre と同じ。`npm/src/index.ts`。エンジンの `set_tab_index` は付いている値を変えない）。pack test の `touch`。
- **属性テーブルの `zoomTo` が経度 180° をまたぐ国で世界全体に合わせる**：`boxOf`（`npm/src/search/dataset.ts`）が、負の経度に 360 を足した並びの方が狭ければその箱（東が 180 を超える）を返す。`fit_box` は東が 180 を超える箱をそのまま扱う。データセット検索の結果の箱も同じ関数なので同じく変わる。テストは `npm/test/ui-table.test.ts`（またぐもの、西半球だけのもの、点）。
- **表の行のページを id から知る**：`AttributeTable.reveal(id)` を足した。その行のあるページへ移り、絞り込みで外れていれば false。pack test の `table`（最後のページの行で 3、ない id で false）。サンプル（`attribute-table`）は 1 ページに全行を入れる形のまま（サイトのコード欄は公開済みの 0.1.0 を指すので、次の版まで使えない）。
- **jenks の最後の区切りが重なって見える**：`classBreaks` は simple-statistics と同じ値のまま。見せる側で、値が 1 つのクラスはその値だけを書く（ショーケースの「Breaks」は同じ境界を 1 回だけ、`classify` と `attribute-table` の凡例は「24.91」）。pack test の `analyze` が境界の重なりがないことを見る。
- **`protomaps` のフィクスチャ**：日ごとのビルドを `20261115` にして取り直した（35 タイル、4,037,021 バイト）。`style:public` は 24 場面とも限度内で、限度は変えていない（protomaps の 10 場面は平均 0.002〜0.009、p99 0）。
- **`showcase-element` がときどき落ちる件**：直していない。単独で 8 回（どれも 45〜47 s で通過）、全項目で 1 回回しても再現しなかった（並行して別の worktree のビルドとテストが動いている状態）。
- **PROGRESS.md**：「サイトの計測タグ」の重なっていた行（古い方）を消し、見出しの前の空行をそろえた。
- 大きさ（gzip）：mbt-map（index.js）167,101 → 167,118 バイト（予算 168KB）、mbt-map/ui 9,811 → 9,906 バイト（予算 10KB。残り 94 バイト）、mbt-map/search 2,849 → 2,911 バイト（予算 5KB）。
- 確かめ：`moon check --target all`、`moon test --target all`（wasm 930、wasm-gc 940、js 989、native 930）、npm のテスト（458）と大きさ、bench のテスト（21）、pack test（Chromium、24/24）、`style:public`、`long-comments`（47 のまま）。Firefox と WebKit の pack test は回していない（CI の `pack-browsers` が見る）。

## 3D レイヤーの半球光：`hemisphere`（2026-11-16、Mac）

「直していないもの」の 1 件目（光に背を向けた面がどれも環境光だけの同じ色になる）の直し。ブランチ `feat/model-hemisphere-light`。

- **足したもの**：`mbt-map/3d` の `modelLayer`・`tilesLayer`・`i3sLayer` のオプション `hemisphere`（型 `Hemisphere`：0〜1 の数、または色をつける `[r, g, b]`）。平行光に真っすぐ背を向けた面に残る環境光の割合で、光を向いた面は全部を保ち、その間は法線と光の向きの角度でならす：`ambient * (1 - (1 - hemisphere) * (0.5 - 0.5 * dot(n, l)))`。既定の 1 は今までと同じ式（シェーダーは `u_shade` が 0 のとき係数を `vec3(1.0)` にするので、既定の描画は変わらない）。範囲の外や形の違う値は無視する。スタイルの `lights` がないときの固定の光（0.55 + 0.45 × Lambert）の 0.55 にも同じようにかかる。
- **半球の軸を「上」ではなく「光の向き」にした理由**：建物の壁は法線の上向きの成分がどれも 0 なので、上向きの軸（空と地面の色を `n.up` で混ぜる普通の半球光）では、太陽の反対側から見える 2 枚の壁が同じ色のままで、屋根と壁の差しか出ない（屋根は今も日が当たって違う色）。光の向きを軸にすると、壁の向きごとに環境光が変わり、太陽が真上のときは普通の半球光と同じになる。
- **スタイルの `lights` ではなくレイヤーのオプションにした理由**：`lights` はエンジン（メインのバンドル、167.1KB / 168KB）が読んで `custom_numbers` で渡すので、そこに足すとメインのバンドルが増える。今回は 3D のエントリだけにとどめた。そのため押し出し（fill-extrusion）にはかからない。押し出しにも要るなら、`lights` の ambient に同じ意味のプロパティを足し、`render_webgl2` の押し出しのシェーダーに同じ 1 行を入れる形になる（メインのバンドルを測ってから）。
- **サイトのトップ**（`site/hero.js`）：`hemisphere: 0.6`。`?time=10:00`、方位 150°（太陽の反対側から）、傾き 62° のスクリーンショットで、一様な灰色だった壁に面ごとの明るさの差と稜線が出ることを見た。太陽の側（方位 -30°）の見た目はほとんど変わらない。`buildings-shadows` のサンプルは押し出しなので対象外。
- **サイズ**（gzip、`npm --prefix npm run size`）：`mbt-map/3d` 9463 → 9671 B（予算 10000）。`mbt-map` 167101 B、3D Tiles 10487 B、I3S 8323 B、3d worker 44086 B は変わらず。
- **確かめ**：`npm --prefix npm test`（458、`hemisphereShade` の値と無視する値）、pack test の `model` に 1 件追加（下からの光 `[0, 180]` で、箱の上面は環境光だけの色のまま、`hemisphere: 0.5` のレイヤーの箱はその半分：`[229, 26, 26]` と `[115, 13, 13]`）。pack test は Chromium で `model,tiles,pointcloud,plateau,custom,samples`、WebKit と Firefox で `model,tiles`。`npm --prefix bench test`（21）、`node bench/lib/long-comments.mjs`（触ったファイルに増えた塊なし）。MoonBit は触っていない（`moonbit/mbtmap` は 3D のレイヤーを写していない）。
- **法線のないモデル**（画面の微分から作る法線）：`hemisphere` には符号つきで使う（見ている側を向く）。pack test のモデルはどれも法線を持つので、その場かぎりのスクリプトで確かめた：法線のない水平な四角形を真上から見て、環境光 0.5・平行光 0.25・`hemisphere: 0.5` で、真上からの光は `[191, 191, 191]`（0.75）、真下からの光は `[128, 128, 128]`（0.25 + 0.25）。三角形の巻き方を逆にしても同じで、Chromium・Firefox・WebKit で同じ値。
- **確かめていないこと**：性能の計測はしていない（フラグメントごとに掛け算と足し算が数回増えるだけ）。I3S のレイヤーでの見た目（3D Tiles と同じプログラムを通る）。

## 測地バッファを日付変更線と極で切る（2026-11-16）

`mbt-map/analysis` の測地 `buffer` の結果が ±180° を越えたり、極を含むときに極のまわりの輪になったりしていた件（docs/analysis.md に制限として書いていたもの）を直した。結果の形が変わる。

- **原因**：バッファは地物ごとの正距方位図法の平面で作り、頂点を経緯度へ戻すだけだった。経度は平面の中心から ±180° の範囲で出るので 180° をまたぐとそのまま越え、極を含む円は経度を一周する輪になり、平面の道具（このライブラリのタイル化も）は帯として塗っていた。
- **直し**（`overlay/antimeridian.mbt`、`@overlay.buffer` から呼ぶ）：
  - `may_wrap`：地物の範囲と距離から、±180° にも極にも届かないと分かるもの（中心から 10° 以内で、距離の 3 倍の余裕がある）は今までの経路のまま。出力はビット単位で同じ。
  - それ以外は各リングを経緯度（1e-7° の整数）へ戻し、辺ごとに近い側を通るとして経度を連続にする（`lift`）。閉じたときに経度が 360° ずれるリングは極を回っている。
  - 閉じるリングはそのままと 360° ずらした写しを、極を回るリングは写しをつないだ 1 本の道を南緯 90° に沿って閉じたものを Clipper に入れ、北極が覆われている回数だけ世界全体の四角を足して、巻き数が正のところを [-180, 180]×[-90, 90] で切る（`cut_to_world`）。穴、複数の部分、両極を含む形も同じ式で出る。切る必要がなかった場合（±180° の内側で、極も回らない）は今までの経路へ戻す。
  - Clipper の移植には手を入れていない。写しは左右 2 つまで（入力の経度は 540° まで）、2 回以上回るリング（壊れた入力）は切らずに今までどおり出す。
- **結果の形**：180° をまたぐものは経度が ±180° に収まる MultiPolygon（RFC 7946 §3.1.9）。極を含むものは ±180° に沿って緯度 ±90° まで上がり、そこを横切る 1 つのポリゴン。切ったものの座標は 1e-7° の格子（約 1 cm）。180° より外にだけある入力（経度 190° など）の結果も ±180° の内側へ戻る。
- **テスト**（`overlay/antimeridian_wbtest.mbt`、4 ターゲット）：179.9°E・100 km（2 部分、経度は ±180° 内、面積は切らない同じ円と 1e-6 で一致）、89.5°N と南極側・100 km（1 ポリゴン、緯度 90° に届き経度 -180〜180、面積は πr² の 1% 以内、円周上の頂点は距離どおり）、縁が極を通る前後を 1 m 刻みで 80 例（面積が跳ばない）、180° をまたぐ線、穴が 180° にかかるポリゴンとかからないポリゴン、極のまわりの帯、両極を含む形、切らないバッファは平面の頂点のまま、平面バッファは切らない。
- **ゴールデン**：`buffer:check` に 180° をまたぐ 2 例と両極の 2 例を足した（部分の数、±180° 内、円周上の頂点が GeographicLib の距離の 0.01% 以内。50 km で最大 1.88 m）。既存の 36 行は前と 1 桁も変わらない。`clipper:golden`（10720 + 4500 すべて一致）、`analysis:golden`（2,783,078 値すべて一致）。pack test の `analysis` に 2 例（`areas()` が πr² の 1% 以内）を足し、Chromium で通過。
- **MultiPoint の測地バッファ**（別のコミット、ユーザー判断で同じ PR）：`shape_of` が点の種類でも辺の分割（0.01° ごと）をしていたので、離れた点の MultiPoint は点を結ぶ線のバッファになっていた（GeoJSON の MultiPoint は 1 つのリングに全点が入る）。点の種類では分割しない。1° 離れた 2 点・1 km は 2 つの円（面積は点 1 つの 2 倍と 0.1% 以内）。`overlay/overlay_wbtest.mbt`。
- **サイズ**（gzip）：geometry.wasm 41.8KB → 43.0KB（予算 50KB）。ほかのエントリは変わらない。
- **残り**：
  - 出力の辺は分割していない。長いまっすぐな辺（長い線のバッファの側面、マイター結合の大きな四角）は前からの挙動どおり 2 頂点のままで、経緯度では端を結ぶ直線になる。極の近くではずれが大きい。
  - 中心から半球を越える形（投影がもともと正しくない範囲）は、有限の結果になることだけを確かめた。
  - 性能の計測（`geometry:node`）はしていない。届かない地物は `may_wrap` の計算が増えるだけ。

## 0.1.1 の前の点検と版上げ（2026-11-16、Mac M2）

0.1.0 のあとに入った分（#42〜#45）を AGENTS §7・§8 で見て、版を 0.1.1 にした。ブランチ `chore/release-0.1.1`。

- **点検で直したもの**：`@overlay.buffer` の説明の文（`cut_to_world` への参照が「行は残る」の側に付いていた）。ほかに直すものは見つからなかった：定数は名前つき（`TURN`・`HALF_TURN`・`POLE`・`MAX_COPIES`）、新しい `pub` はなし（`.mbti` の差分なし）、ホットパス（デコード、テッセレーション、フレーム）には触れていない、`long-comments` は 47 のまま。
- **試して戻したもの**（大きくなった）：`cut_to_world` と `buffer` の `match` を `Option::map`・`bind` にする → geometry.wasm 43,044 → 43,281 バイト（クロージャの分）。属性テーブルの `zoomTo` と `reveal` の同じ述語を関数にまとめる → mbt-map/ui 9,906 → 9,911 バイト（予算まで 94 バイトしかない）。
- **計測**（`geometry:node`、単独で。GSI の建物 17,764 件、5 回の中央値）：バッファ 10 m は 388.7 ms（Turf 1246.8 ms）。前の記録は 490.8 ms（Turf 1176.9 ms）で、切る処理（`may_wrap` の判定）を足しても遅くなっていない。dissolve 170.3 ms（前 192.8）、clip 59 ms（前 74.3）も同じ向きに動いており、差は計測した時期の違いと見る。
- **セキュリティ**：`npm audit`（npm、bench、examples/react）0 件、Dependabot の開いている警告 0 件。依存は足していない。新しい入力の経路は測地バッファの切り分けだけで、写しは左右 2 つまで、2 回以上回るリングは切らずに返し、繰り返しはリングと頂点の数で止まる。`hemisphere` は 0〜1 の数か 3 つ組のほかは無視する。
- **版**：`npm/package.json`（とロックファイル）、`moonbit/mbtmap`、`moonbit/mbtmap_rabbita`（import する `mbtmap` も）、`bench/moonbit`、`examples/rabbita` を 0.1.1 に。README・docs/getting-started.md・npm/README.md の CDN の URL も 0.1.1（npm に出るまでは開けない）。CHANGELOG の `## Unreleased` を `## 0.1.1` にした。
- **README のバッジ**（ユーザーの依頼）：README.md と npm/README.md の先頭に npm の版・月間ダウンロード・CI・ライセンス・型（shields.io と GitHub Actions のバッジ）と mooncakes へのリンク。mooncakes の版を出す動的なバッジは見当たらず、パッケージ名だけの静的なバッジにした。CI は PR でだけ走るので、バッジは直近の実行の結果を出す。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 942、wasm-gc 952、js 1001、native 942）、npm のテスト（459）と大きさ、bench のテスト（22）、`node bench/lib/release.mjs v0.1.1`、pack test（Chromium、24/24）、`long-comments`（47 のまま）。

## 単独の移植 (1)：形の決めと `clipper`（2026-11-17、Mac）

- **決めたこと**（ユーザー判断）：移植ごとに 1 つのモジュールにする（1 つのまとめモジュールや、エンジンを丸ごと出す形は取らない）。最初の範囲は 10 個（`clipper`、`draco`、`meshopt`、`lepcc`、`tiff`、`robust`、`pbf`、`mvt`、`proj`、`geodesic`）。版は移植ごとに独立で 0.1.0 から。
- **調べたこと**：エンジンのパッケージの依存を見ると、`clipper`・`draco`・`meshopt`・`lepcc`・`tiff`・`robust` はエンジンのほかのパッケージを import しない。`pbf` は `@core` の UTF-8 の補助を 1 か所、`proj` と `geodesic` は `@core.Trig` だけを使う。`tiler`・`relate`・`delaunay`・`hull`・`simplify`・`isolines`・`tess` などは `@core` の定数や `@geom.Table` に依存するので、今回の範囲の外。
- **分ける前の計測**（AGENTS §2：パッケージの分割は計測してから）：`clipper` を別モジュールにした実験で、全ターゲットの `moon check`、wasm-gc のテスト（952）、npm のビルドが通り、geometry.wasm は 43,066 → 43,051 バイト（gzip）。モジュールの境界は出力の大きさに効かない。
- **形**：`ports/<名前>/` に `moon.mod`（`t-ujiie-g/<名前>`）と、パッケージのファイル、README（使い方の例）、LICENSE、NOTICE（移植元の著作権とライセンスの本文）。`moon.work` のメンバーにし、ルートの `moon.mod` が同じ版を import する。エンジンのパッケージは `"t-ujiie-g/<名前>"` を import する（別名は前と同じ `@clipper` なので、使う側のコードは変わらない）。`bench/lib/ports.test.mjs` が、版・ワークスペース・3 つのファイル・エンジンを import していないことを見る。出し方は docs/dev/RELEASING.md。
- **`clipper`**：`t-ujiie-g/clipper` 0.1.0。ライセンスの欄は `Apache-2.0 AND BSL-1.0`（移植は Apache-2.0、Clipper2 は BSL-1.0）。`moon package --list` はその 15 個の `.mbt` と `moon.mod`・`moon.pkg`・`.mbti`・README・LICENSE・NOTICE だけ。README の例は一度テストとしてコンパイルして通した（リポジトリには残していない）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 942、wasm-gc 952、js 1001、native 942：前と同じ数）、npm のテスト（459）と大きさ、bench のテスト（23）、`clipper:golden`（10720 + 4500 すべて一致）、`buffer:check`（結果のファイルは変わらない）、`long-comments`（47 のまま）、pack test の `analysis,showcase-html`（Chromium）。

## 単独の移植 (2)：`draco`・`lepcc`・`meshopt`・`robust`・`tiff`（2026-11-17、Mac）

- エンジンのほかのパッケージを import しない 5 つを、(1) と同じ形で `ports/` に移した（コードは変えていない）。どれも `t-ujiie-g/<名前>` 0.1.0。ライセンスの欄：`draco` と `lepcc` は `Apache-2.0`（移植元も Apache-2.0）、`meshopt` と `tiff` は `Apache-2.0 AND MIT`、`robust` は `Apache-2.0 AND Unlicense`。NOTICE に移植元の著作権とライセンスの本文。
- README：何を読めるか、公開 API、出力の並び（`draco` の `to_bytes`、`lepcc` の表）、移植していないもの（エンコーダ、`robust` の `orient2d` 以外、`tiff` の Deflate・JPEG は呼ぶ側で展開）、どのゴールデンで元の実装と比べているか。例は一度コンパイルして通した（`robust` はテストとして実行）。
- import する側：`model_worker`（draco・lepcc・meshopt）、`geotiff_worker`（tiff）、`hull`・`delaunay`・`isolines`（robust）、`bench/entry`。別名は前と同じ。`worker/js/mirror.test.mjs` が読む `draco/decode.mbt` の場所を直した（npm のテストが 1 件落ちて気づいた）。
- 大きさ（gzip）：3d worker 44,086 → 44,150 バイト（+64、予算 50KB）、GeoTIFF 19,834 → 19,807 バイト（-27、予算 20KB）。ほかは変わらない。コードは同じなので、モジュール名が変わったことによる並びの違いと見る。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 942、wasm-gc 952、js 1001、native 942：前と同じ数）、npm のテスト（459）と大きさ、bench のテスト（23）、`draco:golden`（12,515 件、0 differ）、`meshopt:golden`（12,040 件すべて一致）、`lepcc:golden`（2,237 件、0 differ）、`geotiff:golden`（304 件、0 differ）、`shapes:golden`（all identical）、pack test の `model,tiles,i3s,pointcloud,data,analysis`（Chromium）、`moon package --list`（各モジュールともその移植のファイルだけ）、`long-comments`（47 のまま）。

## 単独の移植 (3)：`pbf`・`mvt`（2026-11-17、Mac）

- `pbf` と `mvt` を `ports/` に移した。どちらも `t-ujiie-g/<名前>` 0.1.0、`Apache-2.0`。移植元のコードは無い（仕様から書いたもの）ので、NOTICE はその旨だけ。`mvt` のモジュールは `t-ujiie-g/pbf@0.1.0` を import する（公開は `pbf` が先：RELEASING）。
- `pbf` が `core` を使っていたのは `read_string` の `@core.utf8_lossy` の 1 か所。移植はエンジンを import できないので、1 パスの復号（`core/utf8_nonjs.mbt`、js では `@utf8.decode_lossy`）の写しを `ports/pbf` に持たせた。`@utf8.decode_lossy` をそのまま使う案は、検証と復号の 2 つを wasm に入れる（モジュールごとに約 2.7KB gzip：ARCHITECTURE）ので取らなかった。壊れた並びごとに `@utf8.decode_lossy` と同じになるテストを `pbf` に足した。
- 依存の向きの書き方：`core ← pbf ← …` を `pbf ← mvt ← tess/style ← worker`（`core` は `tess`・`style` の下）に直した（AGENTS、ARCHITECTURE）。
- 大きさ（gzip）：表示ワーカー 85,095 → 85,381 バイト（+286、予算 100KB）、サービスのワーカー 20,281 → 20,312 バイト（+31、予算 21KB）。復号の写しの分。ほかは変わらない。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 943、wasm-gc 953、js 1002、native 943：足したテスト 1 件の分だけ増えた）、npm のテスト（459）と大きさ、bench のテスト（23）、`mvt:golden`（35/35）、`tess:golden`（35/35）、`esri:golden`（19 of 19 ok）、pack test の `showcase-html,services,data,tiles`（Chromium）、`moon package --list`（各モジュールともその移植のファイルだけ）、`long-comments`（47 のまま）。README の例は一度テストとしてコンパイル・実行して通した。

## 単独の移植 (4)：`proj`・`geodesic` と共有の `trig`（2026-11-17、Mac）

- `Trig` の置き場（ユーザー判断）：小さい共有モジュール `ports/trig`（`t-ujiie-g/trig`）。`core/trig.mbt` の定義とテストをそのまま移し、`core` は `pub using @trig {type Trig}` で `@core.Trig` として出し直す。エンジンのほかのコードは変えていない（`.mbti` の `@core.Trig` が `@trig.Trig` になっただけ）。ほかの案（移植ごとに自分の `Trig`、`geodesic` が持って `proj` が借りる）は取らなかった。モジュールは 11 個になった。
- `proj` と `geodesic` を `ports/` に移した（コードは `Trig` の import 元だけ変えた）。どちらも 0.1.0、`Apache-2.0 AND MIT`、`t-ujiie-g/trig@0.1.0` を import する。`trig` は `Apache-2.0`。公開は `trig` が先（RELEASING）。
- README：`proj` は PROJ 文字列や WKT の解析を持たない（mbt-map では TS 側）ので、EPSG のコードで作る例と `Definition` を手で組む例（Lambert 93）を載せた。`geodesic` は緯度が先の関数（GeographicLib と同じ）と経度が先の補助 3 つの違いを書いた。例は一度テストとして実行して通した。
- `proj/encoding.mbt` を指していたコメントと `worker/js/mirror.test.mjs` の読む場所、NOTICE のパスを `ports/proj/…` に直した。
- 大きさ（gzip）：どれも ±31 バイト以内（座標系 21,628 → 21,650、測地ワーカー 12,039 → 12,070、`mbt-map` 本体 167,118 → 167,113 など）。コードは同じなので並びの違いと見る。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 943、wasm-gc 953、js 1002、native 943：前と同じ数）、npm のテスト（459）と大きさ、bench のテスト（23）、`proj:golden`（240 CRS、97,200 点、最大の差 4.66e-9 m）、`geodesic:golden`（19 組すべて一致）、`geojson:golden`（8,148 タイル、0 differ）、`buffer:check`、`tess:golden`（35/35）、pack test の `showcase-html,analysis,geojson,data`（Chromium）、`moon package --list`（3 つともその移植のファイルだけ）、`long-comments`（47 のまま）。

## 単独の移植 (5)：点検（2026-11-17、Mac）

- 梱包したものをリポジトリの外で確かめた：11 個の `moon package` の zip を空のフォルダに展開し、それらだけの `moon.work` で `moon check --target all --deny-warn` と `moon test --target all`（各ターゲット 160 件）が通る。エンジンにも、リポジトリのほかのファイルにも頼っていない。手順は RELEASING に書いた。
- 見つけて直したもの：
  - `bench/proj/unit-cases.mjs` が `proj/projections_test.mbt`（移す前の場所）に書いていた。`ports/proj/…` に直し、作り直して差が出ないことを確かめた。
  - 古いパスの残り：`NOTICE-dev.md`（draco・lepcc のテスト）、`bench/clipper/libcxx-sort-cases.cpp`、COMMANDS。
  - 移植の文書コメントが `docs/dev/FORMATS.md` とだけ書いていた（mooncakes の API 文書では何の文書か分からない）ので `mbt-map's FORMATS.md` にした。
  - `ports.test.mjs`：移植どうしの import（`mvt` → `pbf`、`proj`・`geodesic` → `trig`）の版が相手の `moon.mod` と同じことも見る。
- 直さなかったもの：UTF-8 の復号の写し（`core` と `ports/pbf`：(3) に書いた理由）。移植元のコードを含まないファイル（`extends.mbt`、出力の並び、`mvt`・`pbf`・`trig`）にライセンスのヘッダが無いのはそのまま（NOTICE が言う）。
- セキュリティ：`npm audit`（`npm/`・`bench/`・`examples/react/`）は 0 件、Dependabot の未対応は 0 件。依存は増えていない。信頼できない入力を読む移植（`pbf`・`mvt`・`draco`・`lepcc`・`meshopt`・`tiff`）は、コードを変えていないので上限と範囲の検査も前のまま（各 README に書いた）。
- `moonbit/mbtmap` と `moonbit/mbtmap_rabbita` の README に、サイト（文書・例・デモ）と MoonBit のガイドへの案内を足した（ユーザーの希望）。mooncakes に出るのは次にこの 2 つを公開したとき。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（前と同じ数）、npm のテスト（459）と大きさ（変わらない）、bench のテスト（23）、`long-comments`（47 のまま）。

## 単独の移植の公開と、テーブルの段階の計画（2026-11-17）

- 単独の移植 11 個（`trig`・`pbf` を先に、続けて `mvt`・`proj`・`geodesic`・`clipper`・`draco`・`lepcc`・`meshopt`・`robust`・`tiff`）を、ユーザーが 0.1.0 で mooncakes に公開した。公開の前に確かめたこと：`trig` と `pbf` の公開後、`mvt`・`proj`・`geodesic` の梱包物を単独でリポジトリの外に展開し、依存をレジストリから取って全ターゲットのチェックとテストが通る。残り 9 個の `moon publish --dry-run` はどれも `202 Accepted`（`moon update` は要らなかった）。
- 振り返り（ユーザーの問い：解析を geopandas のようなデータフレームにそろえられたか）：データの持ち方はすでに列指向の 1 つの形で、フォーマットの違いは読み書きの層で終わっている。足りないのは属性の操作（選択、絞り込み、計算、集計、結合）と、面のそろい方（番号の配列を返すもの、`DataTable` と `Dataset` が別の型）。移植した計算は変えずに、その上の面を直せる。
- 決めたこと（ユーザー判断）：Phase 21 の前に「テーブルの段階」を置き、0.2.0 とする。範囲は属性の操作、空間結合、型の一本化、Arrow と GeoParquet の入出力。条件と計算はスタイルの式。既存の面は揃え直す（壊れる変更、移行の案内つき）。段階 T.1〜T.8 と、各段階の初めに決めることは VISION §8「テーブルの段階」。
- 分かっている制約：解析ワーカーは 30.3/31KB で余裕がなく、式の評価器は約 20KB（GeoJSON ワーカーの式つき 56.5KB と式なし 37.0KB の差）なので、属性の操作は別の wasm にする。GeoParquet は圧縮の展開が要る（§5 で後回しにしていた理由）。

## テーブルの段階 T.1：入口 `mbt-map/table` と 1 つの型（2026-11-18、Mac）

- 決めたこと（ユーザー判断）：入口は新しい `mbt-map/table`。データは使うまでページに置き、最初の操作で解析ワーカーへ移す。描画への直結もこの段階に入れる（T.4b を足した）。予算は table 9KB、共有の接続 2KB、analysis 6KB（9 から）、data 2KB（6 から）。
- 作り：
  - `npm/src/table.ts`：`read`・`parse`・`write`（data ワーカー）、`fromGeoJSON`・`grid`・`Table` の操作（解析ワーカー）、`Network`、`defineCrs`。`Table` は読んだバッファ（ページ）か、解析ワーカーの中のハンドルのどちらか。最初の操作でバッファを transfer して `load_table` する。読んだテーブルの id は `Table` が持ち続け、ワーカーへ移したあとの `toGeoJSON` にも付ける（操作の結果のテーブルは id なし：前と同じ）。
  - `npm/src/clients.ts`（`dist/clients.js`）：data と解析の `WorkerClient` を 1 つずつと、`defineCrs` の名前。table・data・analysis の 3 つの入口が読むので、どの入口から使ってもワーカーは 1 つずつになる。
  - `mbt-map/data` はラスタだけ（`read`・`parse`・`write`・`DataTable` は消した）。`mbt-map/analysis` は標高グリッド・`transform`・クラス分けと、移行中の別名（`Dataset` = `Table`、`load` = `fromGeoJSON`。テーブルを渡すと GeoJSON 経由で読み直す）。別名は T.7 で消す。
  - 解析ワーカー：結果のテーブルに列の名前を付けて返す（wasm の `columns_out`：`Table.columns` をどのテーブルでも読めるように）。`table`（テーブルのバイト列を返す：`write` 用）を足した。
- 変わる動き：`toGeoJSON()` は Promise を返す（前の `DataTable` は同期）。`tableBytes()` は無い。
- 大きさ（gzip）：`mbt-map/table` 6,234（新、予算 9KB）、`clients.js` 1,749（新、2KB）、`mbt-map/analysis` 8,739 → 5,316（6KB）、`mbt-map/data` 5,140 → 1,435（2KB）。入口の合計は 13,879 → 14,734。解析ワーカー 30,351 → 30,637（予算 31KB：`columns_out` の分。残り 363 バイト）。
- 呼び出し側：ショーケースのデータ読み込み（`examples/shared/data.js`）、サンプル（read-data、write-data）、pack test の data ページとチェック、bundlers のアプリを `mbt-map/table` に移した。data ページは、読んだテーブルをそのまま解析に使い（`pointsWithin`、`buffer`）、ワーカーへ移す前後で `toGeoJSON` と `write` の結果が同じこと、結果のテーブルの行数と列を見る。解析だけを使う例は別名のまま（T.7 で移す）。
- 文書：`docs/data.md`・`docs/analysis.md` の入口と例、README の入口の表、FORMATS（結果の `columns`、`table`）、ARCHITECTURE-MODULES、VISION §8 に面の対応表（T.4 で確定）。`docs/analysis.md` の本文は `Dataset`・`load` のまま（別名で動く。T.7 で書き直す）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（前と同じ数）、npm のテスト（460：`stringList` の 1 件を足した）と大きさ、bench のテスト（23）、pack test（Chromium、全 24 件）、`long-comments`（46）。
- 残り：解析ワーカーの余裕が 363 バイトしかない。T.2 以降の wasm は別のモジュールにする（計画どおり）。

## テーブルの段階 T.2：属性の操作（2026-11-18、Mac）

- 決めたこと（ユーザー判断）：名前は Arquero にそろえる。`table.wasm` の予算は 45KB。
- 式をどこでコンパイルするか（計測で決めた）：ページ側の JS でコンパイルすると、エンジンの式のコンパイラを JS に出した 41.8KB（gzip）と、評価だけの wasm 25.5KB が要る。wasm の中でコンパイルすれば 36.6KB の 1 つで済む。JSON のパーサ（core の `@json` は 24〜27KB）を wasm に入れないよう、ページ側で式を小さいバイト列に詰める（`npm/src/pack.ts`、FORMATS「Table operations」）。
- 作り：
  - `tableops`（純粋な MoonBit、全ターゲットでテスト）：`select`・`filter`・`derive_columns`・`orderby`・`slice`・`column_kinds`。行は `@style.FeatureContext` として式に見せる（`["get"]` は列、`["geometry-type"]` は行のジオメトリの型）。`@geom.Table` に `take`（行を番号で取る）と `with_columns`（ジオメトリを共有して列を差し替える）を足した。
  - 並べ替えは Arquero の比較（`compare.js`）のとおり：null が先、次に NaN、あとは JavaScript の `<`（文字列どうしは UTF-16 の符号単位、ほかは数にして比べる。文字列を数にするのはホストの `Number()`）。安定なマージソートを自前で持つ（core の `sort_by` は安定とは決まっていない）。NOTICE に Arquero（BSD-3-Clause）を足した。
  - `table_worker`（`table.wasm`）：解析ワーカーが最初の属性の操作で読む。式のコンパイル、ホストの `Math`・`Number`・`String`・`Intl`。入力は上限つきで読む（JSON の深さ 64、数はどれも残りのバイト数まで、行の番号は範囲を検査）。
  - `Table` のメソッド：`select`・`filter`（式、または番号の型付き配列）・`derive`（式、または行ごとの値）・`orderby`・`slice`・`array`・`columnTypes`。
- 計測（gzip）：`table.wasm` 40,653 バイト（予算 45KB）。`mbt-map/table` 6,234 → 7,235（9KB）、解析ワーカー 30,637 → 30,842（31KB、残り 158 バイト：ワーカーの JS に操作の受け口を足した分）、共有の接続 1,749 → 1,762。
- ゴールデン（`table:golden`、Arquero 8.0.3、種を固定した表 60 個）：select 90、filter 896、derive 172、orderby 484、slice 448、番号での行の取り出し 104、列の値 227、断るもの 9：0 differ。表 400 個でも 0 differ。違いは 1 つだけ：列を 1 つも選ばないとき、こちらは行を残す（ジオメトリがあるため）。Arquero は行も無くなる。
- 途中で直したもの：`Packer` が、バッファを伸ばすときに古い `DataView` へ書いていた（テストで見つけた）。wasm の公開名 `derive` と MoonBit の関数名（`derive` は予約語なので `derive_columns`）の取り違え。
- 分かっていること：操作の結果のテーブルは地物の id を持たない（T.1 と同じ）。`Hooks`（式が使うホストの関数の束）が `cluster_props` と `tableops` の 2 か所にある（T.8 の点検で `style` に寄せるかを見る）。解析ワーカーの残りが 158 バイトなので、T.3 と T.4 でワーカーの JS に足す分は、別ファイルに分けるか予算を伺う。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 953、wasm-gc 963、js 1012、native 953：`geom` 2 件と `tableops` 8 件を足した）、npm のテスト（464：`pack` 4 件）と大きさ、bench のテスト（23）、`npm audit`（bench、0 件）、pack test の `data,analysis,samples,showcase-html,cdn`（Chromium。data のページで各メソッドと断り方を見る）。

## テーブルの段階 T.3：集計と結合（2026-11-18、Mac）

- 決めたこと（ユーザー判断）：集計は 14 種（`count`・`valid`・`distinct`・`sum`・`mean`・`min`・`max`・`median`・`any`・`variance`・`stdev`・`quantile`・`mode`・`product`）。書き方は式と同じ配列の形（`["sum", 列名か式]`、一番外側だけ）。`groupby` → `rollup` の結果はジオメトリなし。欠けた値は Arquero のとおり。`table.wasm` の予算は 45KB → 50KB。
- 作り：
  - `tableops/rollup.mbt`：行をキーの「型と値」の文字列でまとめ（最初に現れた順）、グループごとに欠けていない値を集めて集計する。集計は Arquero の `aggregate-functions.js` と `quantile.js` のとおり（平均と分散は逐次の式、`min`・`max` は JavaScript の `<`、`quantile` は安定な並べ替えのあと線形に補う、`mode` は同数なら先に現れた値）。結果は `Table::push_row` で作るジオメトリなしの行。
  - `tableops/join.mbt`：Arquero のハッシュ結合のとおりの行の順（行の少ない表をハッシュに入れ、多い表を順に走査。`left` のときは合わなかった左の行を最後に）。キーは型と値で合わせ、null・キーなし・NaN は合わせない。列は左の全部、次に右（同じ名前のキーは 1 つ）、両方にある名前に接尾辞。ジオメトリは左の行のもの。
  - `table_worker`：`rollup` と `join`（表を 2 つ受ける）。引数は JSON を解釈せず、ページ側で詰めたバイト列を読む（集計は番号）。列名で書いた値は、その列が無ければ断る（行が 0 のときは通す）。
  - `Table`：`groupby(...keys)`（`rollup` を持つものを返す。同期）、`rollup(集計)`、`join(other, on?, { left, suffix })`。`on` を省くと両方にある列。集計の名前と引数の数、結合のキーの形はページ側で確かめる。
  - 解析ワーカーの JS は `rows` を表 2 つに広げただけ（`join` のとき `other`）。別ファイルにも予算の変更にもならなかった。
- 計測（gzip）：`table.wasm` 40,653 → 45,616 バイト（予算 50KB）。内訳は、結合 約 1.9KB、グループ化と集計の土台 約 2.9KB、統計の 4 種（`quantile`・`mode`・`mean`・分散）約 0.5KB。`mbt-map/table` 7,235 → 7,763（9KB）、解析ワーカー 30,842 → 30,885（31KB、残り 115 バイト）。
- 大きさで試したこと：はじめは 48,540 バイト。効いたもの：`Map` の型を `Map[String, Int32]` の 1 つにそろえる・数を文字列にするのに `Int64::to_string` を使わない（-1.7KB）、集計と結合の引数を JSON でなくバイト列にして解釈をページ側へ移す（-1.1KB）。効かなかったもの：結合のキーの読み方をまとめる・`contains` を `search_by` にする（+30 バイト、戻した）。
- ゴールデン（`table:golden`、Arquero 8.0.3、種を固定した表 60 個）：rollup 602（キーなし、1〜3 個のキー、式のキー。値の列ごとに 12 種と `quantile` 5 通り、式の値の `sum`）、join 794（キー 1〜2 個、左右で別の名前、共通の列、内部と左、接尾辞。行の数が左右どちらが多い場合も）：0 differ。全体も 0 differ、表 400 個でも 0 differ。比べるときにそろえた所：`groupby` は null とキーなしを 1 つのグループにする（Arquero は 2 つ）。値の無い集計は null（Arquero は `undefined`、数にならない合計は NaN）。
- 分かっていること：種類の混じった値（文字列と数）の `quantile` は、比較が順序にならないので Arquero と同じとは限らない（ゴールデンの列は 1 種類ずつ）。複数キーのグループ化で、Arquero はキーを `|` でつないだ文字列で見分けるので `|` と引用符を含む文字列が衝突しうるが、こちらは衝突しない。結果のテーブルが id を持たないのは T.2 と同じ。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 964、wasm-gc 974、js 1023、native 964：`tableops` 11 件を足した）、npm のテスト（464）と大きさ、bench のテスト（23）、pack test の `data,analysis,samples,showcase-html,cdn`（Chromium。data のページで集計・結合と断り方を見る）。

## テーブルの段階 T.4：空間結合と揃え直し（2026-11-18、Mac）

- 決めたこと（ユーザー判断）：名前は `spatialJoin` と `nearestJoin`。`relate` は残し、`collect` は消して `spatialJoin` の `rollup` オプションにする。`dbscan` と `kmeans` は列を足したテーブルを返す。グループごとの `dissolve({ by })` を足す。`splitFeatures`・`mergeFeatures` は `mbt-map/analysis` にそのまま残した（`mbt-map/draw` に渡す Feature 用の口で、テーブルの面ではない）。
- 作り：
  - 空間結合は「行の組を作る所」と「組からテーブルを作る所」に分けた。組は relate.wasm（`relate` と同じ）か解析の wasm（`nearest_pairs`：行の箱の中心から、相手の箱までの距離で近い順）が作り、テーブルは table.wasm の `pairs` が作る（`@tableops.join_pairs`：属性の `join` と同じ列の並べ方。`@tableops.rollup_pairs`：左の行ごとに相手の行の値を集計して列にする。ジオメトリは左のまま）。ページ側で 2 つの呼び出しをつなぐので、解析ワーカーの JS には受け口を足していない。
  - `dissolve({ by })`：`@tableops.column_groups`（`rollup` と同じグループ分け）を geometry.wasm から呼び、`@overlay.dissolve_groups` がグループごとにポリゴンを併合してキーの列を付ける。式の評価器は geometry.wasm に入らない（列の値だけで分ける）。
  - `dbscan`・`kmeans`：ワーカーの結果を `derive` で列にする（ページ側だけの変更）。
  - 消したもの：`Table.collect`、型 `Collected`、解析ワーカーの `collect`、wasm の `collect`、`@analysis.collect`。
- 計測（gzip）：`table.wasm` 45,616 → 46,881 バイト（50KB）。`geometry.wasm` 43,051 → 45,226（50KB）。`relate.wasm` 26,826 → 26,881（30KB）。`mbt-map/table` 7,763 → 7,913（9KB）。解析ワーカー 30,885 → 29,525（31KB：`collect` を消した分が、`nearestPairs` と `dissolve` の引数の分より大きい）。予算の変更はなし。
- ゴールデン：`analysis:golden` の `collect` の比較を、空間結合（`intersects`）と集計（count・valid・sum）の経路に付け替えた。Turf の `collect` と all identical（2,783,078 値）。`relate:golden` all identical、`table:golden` 0 differ（断るもの 22）。
- 速さ（`analysis:node`・`analysis:browser`、GSI の建物 42,515 ポリゴン × 8,018 点、ポリゴンごとの点の数と合計）：旧 `collect` は Node 11.1 ms・Chromium 9.3・Firefox 12.0・WebKit 10.3。新しい経路は Node 51.7 ms・Chromium 39.2・Firefox 50.5・WebKit 48.0（Turf は 17〜25 ms）。約 4〜5 倍遅くなった。内訳（Node）：テーブルを relate.wasm へ渡して読む 約 17 ms、組を作る 約 11 ms、table.wasm で読んで集計して書く 約 14 ms、解析の wasm から書き出す 約 5 ms。旧 `collect` は解析の wasm の中（読み済みのテーブル）で点とポリゴンだけを見ていた。
  - 試して効いたもの：`intersects` の相手が 1 つの点のとき、行列を作らずに JTS の点の位置判定（`PointLocator` の移植、`locate`）で答える。組を作る所が 21 → 11 ms（`relate:golden` は all identical のまま。JTS の行列でも、孤立した点の行は同じ判定から決まる）。
  - 残っているもの：6MB のテーブルをモジュールごとに読み直す所（`Table::from_bytes`）が大きい。どの wasm の間の受け渡しにも効くので、T.8 の点検で見る。
- 途中で直したもの：pack test のチェックで、最近傍の結合の期待値を見積もり違いしていた（箱の中心からの距離で手計算し直して合わせた）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 970、wasm-gc 980、js 1029、native 970：`tableops` 4 件、`overlay` 1 件、`analysis` 1 件を足した）、npm のテスト（464）と大きさ、bench のテスト（23）、`geometry:node`（dissolve 165 ms、前回 170 ms）、pack test の `data,analysis,samples,showcase-html,cdn`（Chromium。analysis のページで結合・集計・グループごとの dissolve・クラスタの列と断り方を見る）。

## テーブルの段階 T.4b：描画への直結（2026-11-18、Mac）

- 決めたこと（ユーザー判断）：テーブルは GeoJSON ワーカーがバイト列のまま読む。予算は GeoJSON ワーカー 37 → 39KB、式つきの版 57 → 59KB。
- 作り：
  - `geojson_tiles` の `load`：`flags` の bit 1 が立っていると、入力を「テーブルのバイト列（長さつき）と、行ごとの id」として読み、`@geom.Table::from_bytes` の結果をそのままタイラーに渡す（GeoJSON を経ない）。bit 0 はこれまでの `lineMetrics`。
  - `geojson.js`：ソースの `data` がテーブル（`writeArgs` を持つもの）なら、行と id のバイト列をもらってワーカーへ送る。ページにあるテーブルはコピー、解析ワーカーにあるテーブルはワーカーから取り寄せる。届くまでの間、そのソースのタイルとクラスタの問い合わせは送らずに待たせる。`updateData` はテーブルのソースでは断る（`error` イベント）。
  - 本体（`npm/src/style.ts` の `copy`）：スタイルを JSON で写すとき、テーブルは参照のまま残す。
- 計測（gzip）：GeoJSON ワーカー 36,994 → 38,309 バイト（39KB）、式つきの版 56,491 → 57,774（59KB）、`geojson.js` 4,850 → 4,995（5KB、残り 5 バイト）、本体 167,113 → 167,170（168KB）。
- 速さ（`table:source`、Node、5 回の中央値）：ワーカーでの読み込みは、建物 88,375 件で GeoJSON の文字列から 418 ms、テーブルから 113 ms。道路 105,617 件で 356 → 119 ms、点 8,018 件で 15.3 → 5.6 ms、混在 116,840 件で 537 → 152 ms。これまでの経路でページ側にかかっていた分（テーブルを GeoJSON にして文字列にする：建物 115 + 123 ms、道路 214 + 91 ms、混在 252 + 155 ms）は無くなる。
- 確かめ（同じタイルになるか）：`table:source` で 4 つのデータ × 13 タイル（ズーム 0・4・10・14・16）を、GeoJSON から読んだ場合とバイト単位で比べて all tiles identical。`geojson:golden`・`cluster:golden`・`geojson:update` は 0 differ / all identical のまま。
- 途中で直したもの：
  - 解析ワーカーにあるテーブルを渡すと何も描かれなかった。行を取り寄せる間に、タイルの要求が先に GeoJSON ワーカーへ届き、「読み込みが無い」として空のタイルが返っていた。行を送り終えるまでタイルと問い合わせを待たせた。
  - スタイルの写し（JSON）でテーブルがただのオブジェクトになっていた（`copy` を直した）。
  - テーブルのソースに `updateData` を呼ぶと、黙って空の FeatureCollection に置き換わっていた（断るようにした）。
- 分かっていること：`setData(table)` の直後に `table.dispose()` を呼ぶと、行を取り寄せる前に破棄されて読み込みが失敗する（`error` イベント。文書に書いた）。`geojson.js` の残りが 5 バイトなので、次にここへ足すときは予算を伺う。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 970、wasm-gc 982、js 1029、native 970：`geojson_tiles` 2 件を足した）、npm のテスト（465：`copy` 1 件）と大きさ、bench のテスト（23）、pack test の `npm,geojson,data,analysis,samples,showcase-html,cdn`（Chromium。data のページは 3 つのソースをテーブルのまま渡し、差し替え・`updateData` の断り・破棄済みのテーブルを見る）。

## テーブルの段階 T.5：Arrow（2026-11-19、Mac）

- 決めたこと（ユーザー判断）：口は `mbt-map/table` に足す（`read` が `.arrow`・`.arrows`・`.feather`、`fromArrow`、`table.toArrowIPC()`）。書くときのジオメトリは `geoarrow.wkb` が既定で、`{ geometry: "native" }` で GeoArrow のネイティブ型。新しい `arrow.wasm` の予算は 30KB で、LZ4 フレームのバッファも読む（ZSTD は断る）。
- 作り：
  - 読み（`formats/arrow.mbt`）：IPC のストリームと、ファイル形式（フッターのスキーマとブロックから読む）。FlatBuffers のメタデータは、位置をすべて検査する小さい読み手で読む。列はバッファを入力のビューのまま持ち、行ごとに値を取り出す（辞書、複数のレコードバッチ、辞書の差し替えと追加）。ジオメトリは `geoarrow.wkb`（既存の WKB の読み手）と、ネイティブ型 6 種（座標は並べた形と x・y を分けた形）。拡張型が無いときは、スキーマの `geo` メタデータ（GeoPandas の `to_feather`）か、`geometry` などの名前のバイナリ列。日付と時刻は ISO 8601 の文字列、10 進数は数にする。リスト・構造体などの列は読み飛ばす。
  - LZ4（`formats/lz4.mbt`）：フレームとブロックの形式の説明から書いた（依存なし、チェックサムは検査しない）。1 つの入力で展開できるのは合計 1GB まで。
  - 書き（`formats/arrow_write.mbt`）：前へ並べる FlatBuffers の書き手（テーブルの前に vtable、指す先は後ろ）、スキーマ・レコードバッチ 1 つ・終端、ファイル形式ならフッター。列の型はセルから決める（整数が 32 ビットに収まれば Int32、ほかの数は Float64、真偽値、文字列、混ざった列は文字列、値が無ければ Null）。ジオメトリは ISO WKB か、種類が 1 つ（または種類とその Multi）のときのネイティブ型。
  - CRS：ジオメトリの列のメタデータ（拡張型の `crs`、無ければ `geo` メタデータ）から、JS（`data_worker/js/arrow.mjs`）が EPSG コードを取り出し、データワーカーのいつもの変換（proj.wasm）に渡す。EPSG コードが分からない CRS は `options.crs` を求めて断る。
  - `arrow_worker`（`arrow.wasm`）と `data-arrow.js` は、データワーカーが初めての Arrow の読み書きで読む（データワーカーは 40.7/41KB で入らない）。
- 計測（gzip）：`arrow.wasm` 28,312 + `data-arrow.js` 608 = 28,920 バイト（予算 30KB）。データワーカー 40,695 → 40,790（41KB）、`mbt-map/table` 7,913 → 8,057（9KB）、共有の接続 1,762 → 1,783（2KB）。
- ゴールデン（`arrow:golden`、apache-arrow 21.2.0、種を固定した表 40 個ずつ）：書いたものを apache-arrow で読む 1,724 件（ストリームとファイル、WKB とネイティブ、型と値と拡張メタデータ。WKB は wkx 0.5.0 で読む）、apache-arrow が書いたものを読む 4,480 件（整数 8 種、浮動小数 3 種、真偽値、文字列 2 種、辞書、日付 2 種、時刻 4 種、Null、読み飛ばす 3 種、WKB 3 通りとネイティブ 3 通り、2 バッチ、LZ4）、往復 248 件、壊した入力（途中で切る、バイトを変える：4 つのファイルで各 4,000 回）でトラップなし：0 differ。表 300 個でも 0 differ。
- pyarrow 23.0.1 での確かめ（手で、この Mac）：こちらが書いた 4 通り（WKB / ネイティブ × ストリーム / ファイル）を `validate(full=True)` つきで読めて、値と型が合う（shapely で WKB も読めた）。pyarrow が GeoPandas と同じ形（WKB、`geo` メタデータに PROJJSON の EPSG:6677、LZ4）で書いた Feather を読めて、経緯度に直る。そのファイルを pack test の data ページの入力にした（`bench/data/feather-fixture.py`）。
- 分かったこと：apache-arrow（JS）21.2.0 は、圧縮したバッファの先頭 8 バイトに、仕様の「展開後の長さ」でなく圧縮後の長さを書く（`ipc/writer.js` の `_compressBodyBuffers`）。pyarrow は仕様どおり。こちらはこの値を使わず、LZ4 フレームを最後まで展開して長さを得る（上流へは未報告）。apache-arrow（JS）のファイル形式は、メッセージの並びにスキーマを入れない（フッターだけ）。
- 途中で直したもの：ネイティブの点の列で、点数の上限が効いていなかった（テストで見つけた。点を足す所で数える）。128 ビットの 10 進数の小さい負の値が、上位と下位を足すときに桁落ちして -0 になった（符号を外してから足す）。
- 依存（`bench` の開発用、配布物には入らない）：apache-arrow 21.2.0（Apache-2.0、導入スクリプトなし）、lz4js 0.2.0（ISC、導入スクリプトなし。apache-arrow に LZ4 で書かせるため。これまでも他の依存の下にあった）。`npm audit` は 0 件。
- 残したもの：`geoarrow.wkt` の列は読まない。ZSTD で圧縮したバッファは断る。地物の id は書かない。FlatBuffers の読み手が FlatGeobuf 用と Arrow 用の 2 つある（T.8 の点検で寄せるかを見る）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 984、wasm-gc 996、js 1043、native 984：`formats` 14 件を足した）、npm のテスト（469：`arrow.mjs` 4 件）と大きさ、bench のテスト（23）、`data:golden`・`write:golden`（0 differ のまま）、pack test の `npm,data,analysis,samples,showcase-html,cdn`（Chromium。data のページで Feather を読み、書いて読み戻し、断り方を見る）。

## テーブルの段階 T.6：GeoParquet の読み込み（2026-11-19、Mac）

- 決めたこと（ユーザー判断）：圧縮は snappy と gzip。zstd は次の段（T.6b）で MoonBit に移植する（依存は増やさない）。範囲と列を絞って読む所まで入れる（T.6c）。Parquet は `parquet.wasm` に分ける（予算 24KB）。
- 作り（`formats/parquet.mbt`）：
  - フッター（Thrift のコンパクトプロトコル）からスキーマ・行グループ・`geo` メタデータを読む。位置と数はすべて検査し、入れ子は 32 段まで。
  - 行そのものの列（グループの中でも繰り返しでもない葉）だけを読む。ページは辞書ページ、データページの v1 と v2。値のエンコーディングは PLAIN、辞書（RLE とビット詰めの混成）、RLE（真偽値）、DELTA_BINARY_PACKED、DELTA_LENGTH_BYTE_ARRAY、DELTA_BYTE_ARRAY、BYTE_STREAM_SPLIT。
  - 型：真偽値、整数（符号つき・なし）、浮動小数（16〜64 ビット）、10 進数（INT32・INT64・固定長・可変長）、文字列、日付、時刻（INT96 も）。リスト・構造体・バイナリ・時刻だけの列などは読み飛ばす。
  - ジオメトリは WKB の列：`geo` メタデータの `primary_column`、無ければ Parquet の `GEOMETRY`・`GEOGRAPHY` 型、無ければ `geometry` などの名前。CRS は Arrow と同じ道（`data-arrow.js` が EPSG コードを取り出して変換）。
  - snappy は形式の説明から書いた（依存なし）。gzip はブラウザの `DecompressionStream`：wasm の `pages()` が展開するページの位置と長さを並べ、JS が展開して、ファイルの後ろに付けて `read()` に渡す。
- 計測（gzip）：`parquet.wasm` 22,896 バイト（予算 24KB）。Arrow と 1 つの wasm にすると 38,889 バイトだった（分けた場合 Arrow 28,280 + Parquet 22,896）。`data-arrow.js` 608 → 926（`arrow.wasm` と合わせて 29,206、予算 30KB）、データワーカー 40,790 → 40,835（41KB、残り 165 バイト）、`mbt-map/table` 8,057 → 8,073、共有の接続 1,783 → 1,799。
- ゴールデン（`parquet:golden`）：
  - pyarrow 23.0.1 が書いた 15 ファイル（`bench/table/parquet/`、合計 0.5MB をコミット。`bench/data/parquet-fixtures.py` が、読めるはずの行も値から計算して `expected.json` に書く）：圧縮なし・snappy・gzip、ページ v1・v2、辞書あり・なし、小さいページと行グループ、3 つの delta と byte stream split、INT96、投影の CRS、`geo` なしで名前から見つける列、ジオメトリなし、0 行：284 件 0 differ。zstd・lz4・brotli の 3 ファイルは断る。
  - hyparquet 1.33.1：hyparquet-writer 0.18.0 が種を固定した表 30 個から書いたファイルを、hyparquet と同じ値に読む：0 differ（表 200 個でも 0 differ）。
  - 壊した入力（4 ファイルを途中で切る、バイトを変える各 1,500 回。半分はフッターを狙う）：トラップなし。
- 分かっていること：2^53 を超える 10 進数は、バイトごとに足すので最後の桁が近似になる（ゴールデンでは相対 1e-14 で比べる）。GeoParquet 1.1 の GeoArrow エンコーディング（入れ子のリスト）は読まず、そのファイルは断る。
- 途中で直したもの：入れ子の列（リスト・構造体）の後ろにある列が「入れ子の中」と数えられて読まれなかった。0 行のファイルと、空のリストの書き方（要素の型が 0）を断っていた。10 進数を 10 で何度も割っていたので、最後の桁がずれることがあった（10 の累乗 1 回で割る。Arrow の 10 進数も同じに直した）。
- 依存（`bench` の開発用、配布物には入らない）：hyparquet 1.33.1、hyparquet-writer 0.18.0、hyparquet-compressors 1.1.3（どれも MIT、導入スクリプトなし）。`npm audit` は 0 件。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 991、wasm-gc 1003、js 1050、native 991：`formats` 7 件を足した）、npm のテスト（471：`arrow.mjs` 2 件）と大きさ、bench のテスト（23）、`arrow:golden`（0 differ のまま）、pack test の `npm,data,analysis,samples,showcase-html,cdn`（Chromium）と data ページを WebKit・Firefox で（pyarrow が gzip で書いた GeoParquet を読み、EPSG:6677 から経緯度に直る）。

## テーブルの段階 T.6b：zstd の展開（2026-11-19、Mac）

- 決めたこと（ユーザー判断）：zstd は単独の `zstd.wasm`（予算 7KB）。`data-arrow.js` は自分の行（1.5KB）に分け、`arrow.wasm` は 30KB のまま。
- 作り：
  - `zstd`（純粋な MoonBit、全ターゲットでテスト）：fzstd 0.1.1（MIT）の展開の移植。FSE の表、ハフマンの表（重みの直接指定と FSE 圧縮）、リテラル（生・RLE・ハフマン 1 本と 4 本・表の使い回し）、シーケンス（既定の表・RLE・記述・使い回し、繰り返しオフセット）、生と RLE のブロック、複数のフレームとスキップ可能フレーム。読み取りはすべて範囲を検査する（移植元は範囲外を未定義値として読む作り）。出力は 1 本の伸びるバッファで、一致はフレームの先頭までさかのぼれる。辞書つきのフレームは断る。チェックサムは検査しない。NOTICE に足した。
  - 流れは gzip と同じ：parquet.wasm と arrow.wasm の `pages()` が圧縮された部分（位置・長さ・展開後の長さ・コーデック）を並べ、`data-arrow.js` が gzip はブラウザで、zstd は zstd.wasm で展開して、ファイルの後ろに付けて `read()` に渡す。Arrow はレコードバッチごとにバッファの一覧を先に見て、ZSTD のものだけを並べる（LZ4 はこれまでどおり wasm の中）。
- 計測（gzip）：`zstd.wasm` 6,665 バイト（予算 7KB）。`parquet.wasm` 22,896 → 22,927（24KB）、`arrow.wasm` 28,280 → 29,461（30KB）、`data-arrow.js` 926 → 1,129（1.5KB）、データワーカー 40,835 → 40,825（41KB：URL の受け取りをループにまとめた）、共有の接続 1,799 → 1,810。
- ゴールデン：
  - `zstd:golden`（Node の zlib = libzstd）：6 種類のデータ × 10 通りの大きさ（0 バイト〜3MB）を、レベル -5・1・3・9・19、チェックサムあり・内容の大きさなし・小さい窓で圧縮した 900 件を同じバイト列に戻す：0 differ（400 件 × 15 通りでも 0 differ）。複数フレームとスキップ可能フレーム、上限、辞書の断り。壊した入力（4 つ、各 3,000 回）でトラップなし。
  - `parquet:golden`：pyarrow が zstd で書いた 2 ファイル（ページ v1・v2）が加わり 320 件 0 differ。断るのは lz4 と brotli。
  - `arrow:golden`：apache-arrow に zstd で書かせたストリームとファイルが加わり、読み 6,720 件 0 differ。
  - 手で（pyarrow 23.0.1）：zstd の Feather と IPC ストリーム（3 バッチ）を読めた。
- 手元の道具：この Mac の MoonBit のコアが新しくなり、`Bytes::new` が非推奨の警告になった（`wasmio`・`surface_worker` の 2 か所を `Bytes::make` に直した。固定版でも通る書き方）。`moon fmt` が `style/` の 2 ファイルの末尾カンマを変えたが、戻した（版上げは別の PR で）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 999、wasm-gc 1011、js 1058、native 999：`zstd` 7 件、`formats` 1 件を足した）、npm のテスト（471）と大きさ、bench のテスト（23）、pack test の `npm,data,analysis,samples,showcase-html,cdn`（Chromium）と data ページを WebKit・Firefox で（pyarrow が zstd で書いた GeoParquet と Feather を読む）。

## テーブルの段階 T.6c：Parquet を範囲と列で絞って読む（2026-11-19、Mac）

- 決めたこと（ユーザー判断）：`bbox` はファイルの座標で受ける（FlatGeobuf と同じ）。範囲の手がかりが無いファイルは全部読んで行を絞る。予算は `parquet.wasm` 24 → 27KB、`data-arrow.js` 1.5 → 3KB。
- 作り：
  - 読み手を 3 段にした（`formats/parquet.mbt`）：`parquet_open`（フッターだけ）→ `ParquetFile::plan`（`bbox`・`columns`・covering の列名から、読むバイト範囲を出す）→ `ParquetFile::read`（取ってきた断片から読む）。断片は「ファイル上の位置・入力上の位置・バイト列」で渡し、列チャンクは自分を含む断片から読む。ファイル全体を渡す `read_parquet` は、その上の薄い包み。
  - 行グループの見送り：GeoParquet 1.1 の `covering`（各行の箱を持つ `bbox.xmin` などの列）の統計（`min_value`・`max_value`、古い `min`・`max`）が `bbox` の外なら、その行グループは計画に入れない。統計が無ければ残す。
  - 行の絞り込み：読んだ行のジオメトリ（WKB）の箱が `bbox` にかかるものだけ残す（covering の有無によらず結果は同じ）。ジオメトリの無い行は `bbox` があれば落とす。
  - `columns`：名前で属性の列を選ぶ（ジオメトリは常に読む。順はファイルのまま）。読めない列や無い名前は断る。
  - 取得（`data_worker/js/arrow.mjs`）：URL は末尾 64KiB（フッターの大半が入る）を先に取り、足りなければフッターを取り直す。計画された範囲は 16KiB 以内の隙間ならまとめて 1 回で取り、並行に取る。合計 256MB まで。範囲リクエストに答えないサーバ（200）や、`Content-Range` を見せないサーバは、ファイル全体を取って同じ結果にする。Blob とバイト列は全体を持っているので、同じ計画で一部だけを読む。
- 計測（gzip）：`parquet.wasm` 22,927 → 25,943 バイト（27KB）、`data-arrow.js` 1,129 → 2,628（3KB）、データワーカー 40,825 → 40,865（41KB）、`mbt-map/table` 8,057 → 8,134（9KB）。
- 大きさで試したこと：はじめ 26,810 バイト。パスの連結を `join` でなく自前に、断片探しをイテレータでなくループにして -0.9KB。
- ゴールデン（`parquet:golden`）：covering つきの 2 ファイル（float64 と、外向きに丸めた float32。西から東へ並べて小さい行グループ）を足した。部分読み 174 件（5 ファイル × 7 通りの `bbox`・`columns` を、バイト列から・範囲リクエストで・範囲なしのサーバで・大きさを見せないサーバで読み、期待する行を絞ったものと比べる。covering つきなら小さい箱で計画されるチャンクが半分未満）：0 differ。全体も 0 differ（pyarrow 334、hyparquet 30、壊した入力 10）。
- 分かっていること：covering の無いファイルでは `bbox` は通信量を減らさない（文書に書いた）。行グループが大きい、または空間で並んでいないファイルも同じ。実際の大きいファイル（Overture など）での通信量は測っていない（ゴールデンのファイルは最初の 64KiB より小さいので、計画されるチャンクの数で見送りを確かめている）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 1002、wasm-gc 1014、js 1061、native 1002：`formats` 3 件を足した）、npm のテスト（474：範囲読みの 4 件に書き直した）と大きさ、bench のテスト（23）、`arrow:golden`（0 differ のまま）、pack test の `npm,data,analysis,samples,showcase-html,cdn`（Chromium）と data ページを WebKit・Firefox で（`bbox` と `columns` で一部を読む、断り方）。

## テーブルの段階 T.7：例・文書・移行（2026-11-20、Mac）

- ショーケース（html・element・react。`examples/shared/analyze.js`）：解析のタブに「Table: read, join, count, draw」を足した。公園の CSV を `read` で読み、地点から駅を `filter` で絞り、`nearestJoin` で公園ごとに最寄りの駅を付け、`groupby`・`rollup` で駅ごとに数え、`join` で駅に戻し、そのテーブルをソースの `data` にそのまま渡して円で描く（半径は公園の数）。途中のテーブルは終わりに `dispose` する。
- 別名の削除：`mbt-map/analysis` の `load` と `Dataset` を消した（`mbt-map/analysis` 5,316 → 5,263 バイト gzip）。呼び出し側（ショーケース、サンプル buffer-voronoi・route・classify、pack test と analysis・cdn のページ、bundlers のアプリ）を `mbt-map/table` の `fromGeoJSON` に移した。classify のサンプルは、結合の結果のテーブルをそのまま `setData` に渡す。
- 文書：`docs/migrating.md`（0.1 → 0.2：移った名前、変わった戻り値、新しい機能、配るファイル）。`docs/analysis.md` を `Table`・`fromGeoJSON` の言葉に直し、`docs/data.md` の入口をテーブル中心（読む → 絞る → 結合 → 集計 → 描くの例）に書き直した。`CHANGELOG.md` に Unreleased の節。
- チェック（`bench/npm/checks/analyze.mjs`）：5 つの公園が最寄りの 4 駅に数えられ（有楽町駅 2、ほか 1）、ソースの `getData()` がテーブルで、列が `name, kind, name_station, parks, first`、タイルに「有楽町駅 2」があること。
- 確かめ：`moon check --target all --deny-warn`、npm のテスト（475）と大きさ、bench のテスト（23）、pack test の全部（Chromium）。

## テーブルの段階 T.8：リファクタリングとセキュリティの点検（2026-11-20、Mac）

- リファクタリング（AGENTS §7 の順）：
  - 定数：`formats/parquet.mbt` の Thrift の型、parquet.thrift の `Type`・`Encoding`・`CompressionCodec`・`PageType` に名前を付けた（1 回だけ出る構造体のフィールド番号は、その構造体を読む `match` のまま）。
  - 重複：`Hooks`（式が要るホストの関数）が `tableops` と `cluster_props` に同じ定義で 2 つあった → `@style.Hooks` に 1 つ（両方の `core` の import が要らなくなった）。
  - 統合しなかったもの：FlatBuffers の読み手 2 つ（FlatGeobuf の `Fgb`、Arrow の `Flat`）。エラーの持ち方が違い（位置と文言・読んだ量の予算／フラグ 1 つ）、無いテーブルの扱いも違う。別の wasm に入るので大きさも減らない。`value_of`・`prop_of`（`@geom.Prop` ↔ `@style.Value`）も、`geom` と `style` の両方を知る下の層が無いのでそのまま。`read_parquet`・`parquet_packed_pages` はテストだけが呼ぶが、ファイル全体の入口としてブラックボックスのテストが使うので公開のまま。
- 性能（空間結合の集計、GSI の建物 42,515 ポリゴン × 8,018 点。`analysis:node`・`analysis:browser`）：Node 51.7 → 40.9 ms、Chromium 39.2 → 29.1、Firefox 50.5 → 36.5、WebKit 48.0 → 34.8（旧 `collect` は 9〜12 ms、Turf は 18〜26 ms）。
  - 内訳を段ごとに測り、wasm をデバッグ名つきでプロファイルした（Node）：relate.wasm の初回 29.7 ms（うち組を作る所 13.0）、table.wasm 18.4、解析の wasm からの書き出し 4.9。
  - 効いたもの 1：relate.wasm が入力を `Bytes` に写してから 1 バイトずつ読んでいた（`BytesView::at` が最上位）→ ほかのモジュールと同じく線形メモリからその場で読む（`@wasmio.input_table`）。初回 29.7 → 26.1 → 17.5 ms（下の 2 と合わせて）。
  - 効いたもの 2：組を作る所は `Index::search` が 37%。行の多い側（ポリゴン）を 1 行ずつ、少ない側（点）のインデックスで引いていた → 行の少ない側から多い側のインデックスを引き、組を第 1 のテーブルの順に並べてから同じ順で判定する（`indexed`）。13.0 → 2.75 ms。`relate:golden` は all identical、`analysis:golden` も all identical のまま。
  - 効かなかったもの（戻した）：`Index::search` のスタック用の配列を検索ごとに作らず使い回す → 13.0 ms のまま（検索そのものの時間だった）。
  - 残り：table.wasm の 18 ms は 1 か所に集まっていない（文字列の属性の復号と符号化、属性の読み書き、書き出し）。旧 `collect` との差は、テーブルを 2 つのモジュールへ渡して結果のテーブルを作る分。
- セキュリティの点検（AGENTS §8。読み取り専用のサブエージェントが調べ、再現する入力を作って確かめた）：メモリの外への読み書き、XSS、プロトタイプ汚染、資格情報つきの取得、スキームの抜け道は無し。`npm audit` は `npm/`・`bench/` とも 0 件、この段階で足した開発用の依存はすべて版を固定、配る `npm/` の依存は増えていない。見つかったのは、小さい細工ファイルでワーカーを止める・メモリを使い切らせる類と、正しいファイルでも値を落とすバグ 1 件。すべて直した：
  - Parquet のバグ：辞書で符号化したページに値が 1 つも無い（全部 null）と、その列の後のページの値が全部 null になった（数値の列。DECIMAL などではトラップ）。値の無いページが別の種類の空の配列を返し、ページをつなぐ所が後のページを黙って捨てていた → 辞書と同じ種類の空を返し、種類が合わないページはエラーにする。pyarrow は既定で辞書を使うので、先頭のページが全部 null の疎な列で実際に起きうる。
  - 行数の上限が無かった（Arrow・Parquet）：属性の列が無いテーブルはセル数が 0 のままなので、160 バイトのストリームや 29 バイトのフッターが 4 千万行（200MB）のテーブルになった → 読んだ行を数える（3,200 万行）。
  - Parquet の DELTA_BINARY_PACKED：ブロックの大きさ 2^24・幅 0 のミニブロックで、値が 1 つでも 1,600 万回まわった（26 バイトのページあたり約 15 ms、1MB のファイルで約 10 分）→ 残りの値の数だけ読み、ミニブロックの残りはバイト数で飛ばす。20 ページ 291 → 1 ms。
  - 行の間で共有される文字列（Parquet の辞書の値、DELTA_BYTE_ARRAY の接頭辞）：1MB のファイルが 419MB のテーブルになった → 読む属性の文字列とバイト列を合計 256MB まで（ほかの読み手の入力の上限と同じ）。
  - Arrow のスキーマとフッター：オフセットが同じ文字列を何度でも指せる（フィールド × メタデータの組 × キーの長さ）→ 1 メッセージで復号する名前とメタデータを 64MB まで。フッターのブロックはファイルの順（同じメッセージを何度も読ませない）。辞書は 3,200 万値まで。
  - そのほか：Thrift の `skip` がリストとマップで深さを数えていなかった（20 万重のリストでスタックあふれ）、マップの中の真偽値を 0 バイトと数えていた、スキーマの入れ子に上限が無かった → 32 段。`(n + 7) / 8` が 2^31 近くで負になった（Arrow の列の長さを 2^30 まで、Parquet は 64 ビットで比べる）。Arrow の入れ子の列の有効ビットが子より短いとトラップした（ビット列の外は null）。Parquet の件数からの先取り確保（行数ぶんの配列、BYTE_ARRAY・真偽値・幅 0 の固定長）をバイト数と照らしてから作る。Snappy の展開後の長さを入力の 64 倍まで。v2 の定義レベルをレベルの範囲だけから読む。結合の結果（同じキーが n × m 行になる）をテーブルの上限（3,200 万セル、2,000 万点）で断る。Parquet の範囲リクエストを同時 8 本まで。`type in GRIDS` などの引数の確かめを自分のキーだけに（`Object.hasOwn`）。
  - 直さなかったもの：GZIP のページは、ヘッダーの言う長さ（1GB の予算の内）ぶんを先に確保する。Parquet のフッターは 256MB まで読む。`nearestJoin` の組は行 × `k` で、`k` は呼び出し側の値。
- T.7 の CI で起きた失敗（WebKit のショーケースで、テーブルのソースのタイルに地物が出ない）：チェックの側の競合だった。この PR の CI でもう 1 度起き、残した記録で分かった（待ちは 5 ms で通り、直後に読み直した一覧が空）。GeoJSON ソースは行がワーカーに入るとタイルを作り直すので、その間 `querySourceFeatures` は空を返す。待つのと読むのを 1 回の呼び出しにまとめた。
- 計測（gzip）：relate.wasm 26,866 → 27,685 バイト（30KB）、table.wasm 46,848 → 47,226（50KB）、arrow.wasm 29,466 → 29,663（30KB）、parquet.wasm 25,943 → 26,323（27KB）。
- 確かめ：`moon check --target all --deny-warn`、`moon test --target all`（wasm 1010、wasm-gc 1023、js 1069、native 1010）、npm のテスト（475）と大きさ、bench のテスト（23）、`arrow:golden`・`parquet:golden`・`table:golden`・`zstd:golden`（0 differ）、`relate:golden`・`analysis:golden`（all identical）、pack test の `npm,geojson,data,analysis,samples,showcase-html`（Chromium）。
