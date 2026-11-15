# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

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
- **前のリポジトリから引き継ぐ未解決**：
  - `protomaps` のフィクスチャの版（`build.protomaps.com/20261103.pmtiles`）が消えた（404）。新しい日付にする。
  - `npm:pack` の `showcase-element` がこの Mac でときどき 180 s で落ちる（表の行のクリックの後に地図が止まらない。CI では通る）。
  - 3D の断面の枠の半径（6371008.8 m）とモデルの位置の半径（6378137 m）が楕円体の値とそれぞれ 0.23%・0.11% ずれる（100 m で約 0.2 m）。直すなら緯度で半径を決める。
  - Mac で回すもの：`style:public`・`style:compat`、`render` の変種（`--labels` など）、MapLibre の基準の取り直し。

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
