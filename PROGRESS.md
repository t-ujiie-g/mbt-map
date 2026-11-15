# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

- **いま**：最初の公開（0.1.0）の準備中。npm の `mbt-map` と mooncakes の `t-ujiie-g/mbtmap`・`t-ujiie-g/mbtmap_rabbita` を同じ版で出す。残りは、ユーザーが行う公開（docs/dev/RELEASING.md「初めての公開」：npm、mooncakes、タグ `v0.1.0`）。
- **済んだ段階**（どれも下に日付つきの節がある。決めたことは次の節「進め方と名前の決定」）：
  - 移行：mbmap の Phase 0〜20 とその後の点検（mbmap #165 まで）を、このリポジトリへ移して改名した。
  - MoonBit の API：`mbt-map/moonbit` の入口、型付きの `mbtmap`（地図、カメラ、イベント、生成したスタイルと式）、rabbita の部品 `mbtmap_rabbita` とデモ。
  - 文書：README、docs/ の入口ごとのガイド、その後の点検（リファクタリングとセキュリティ）。
  - GitHub Pages：手書きのトップ、docs の HTML、動く例。サンプル集とテーマの切り替え、例の画面の英語化。
  - 公開の流れ：タグで npm への段階公開と GitHub のリリース、mooncakes は手で。
  - 公開前の直し：3D Tiles の読み直しの繰り返し、出典の HTML、地形で手前の低い土地が描かれない件、CDN から HTML 1 枚で読む、グリフのアトラスがあふれる件、世界のコピー（`renderWorldCopies`）、トップの地図、Firefox と WebKit での pack test。
- **次**：公開のあと、単独で使える移植（`mvt`、geojson-vt、`proj` など）を mooncakes に。Phase 21（VISION §8）。
- **未解決**：
  - `protomaps` のフィクスチャの版（`build.protomaps.com/20261103.pmtiles`）が消えた（404）。新しい日付にする。
  - `npm:pack` の `showcase-element` がこの Mac でときどき 180 s で落ちる（表の行のクリックの後に地図が止まらない。CI では通る）。
  - 3D の断面の枠の半径（6371008.8 m）とモデルの位置の半径（6378137 m）が楕円体の値とそれぞれ 0.23%・0.11% ずれる（100 m で約 0.2 m）。直すなら緯度で半径を決める。
  - Mac で回すもの：`style:public`・`style:compat`、`render` の変種（`--labels` など）、MapLibre の基準の取り直し。
  - `setViewshed`・`setClipping`・`triggerRepaint` のあとに `idle` が来ない（MapLibre は描き終えるたびに `idle`）。合わせるかは別に決める。
  - Linux の WebKit で `antialias: false` のキャンバスの最後のフレームが出ない件が headless だけのことか。Linux の headless Firefox に WebGL2 がない（pack test は飛ばす）。
  - 世界が画面より狭い（ズーム約 1 未満）とき、同じタイルの別のコピーにはラベルが出ない（MapLibre はコピーごとに配置する）。
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
- 公開先（`t-ujiie-g.github.io`）で開いたときだけ読み込む（ローカルの確認や CI を計測に混ぜない）。もらったスニペットに、GTM の「全ページ」のトリガーが動くよう公式の `gtm.start` の合図を足した。フッターに「Google Analytics で訪問を数えている」と書いた。

## サンプル：属性テーブルとフィールド演算（2026-11-15）

- ユーザーの要望（属性テーブルの例がない、フィールド演算を見せたい）で `examples/samples/attribute-table/` を足した（一覧では Tools の先頭）。世界の国（Natural Earth 1:110m、176 件）を地図と表で見せる。表は `createAttributeTable`（見出しで並べ替え、絞り込み、行の選択を feature state で地図に、`zoomTo`）、地図のクリックで行を選んで表をそこまで送る。`createFieldEditor` で式（JSON のスタイル式）から列を足し、見出しから改名・削除できる。プリセットは 4 つ（1 人あたり GDP、人口の割合、1 億人以上、経済規模）。数値の列は `classBreaks`（分位・jenks・等間隔）と `classStep` で塗り分け、凡例を出す。地球儀の切り替えつき。
- データ `countries.json`（177KB、gzip 約 56KB）はサンプルのフォルダに置いた。座標は小数 2 桁、南極は外した（人口と GDP が仮の値で、1 人あたり GDP の階級を 1 つ占めてしまう）。出典は NOTICE-dev.md。
- **ライブラリの不具合（直していない）**：`updateData` の 1 つの更新に `removeAllProperties: true` と `addOrUpdateProperties` の両方があると、ワーカー側（`tiler/source.mbt` の `Source::updated_row`）は足す分も捨てるので、描かれるフィーチャーの属性が空になり、`promoteId` の id も失われる（`getData()` は正しい値を返す：`npm/src/geojson-diff.ts` は消してから足す）。`createFieldEditor` の `propertiesDiff` は常にこの形を送るので、フィールド演算のあと、属性で塗る式は既定値になり、feature state も `queryRenderedFeatures` の属性も消える。サンプルは編集のたびに `setData` で全体を渡し直して避けている（直ったらその 2 行を消す）。
- 足りないもの：表の行がどのページにあるかを id から知る方法がない（地図で選んだ行へ送るため、サンプルは 1 ページに全行を入れて自分でスクロールする）。`zoomTo` は経度 180° をまたぐ国（ロシア、フィジー）で世界全体に合わせる。
- 確かめ：Chromium と WebKit で、人口の降順（中国、インド、米国）、「land」の絞り込み（12 件）、行と地図の相互選択、プリセットの値（日本 40,247 = gdp×1e6/population）、塗り分けと凡例、不正な式（何も変わらずエラー表示）、改名と削除、390×844。pack test の `samples`（Chromium、WebKit）、サイトのビルド、`npm --prefix bench test`。
