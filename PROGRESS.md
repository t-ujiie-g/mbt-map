# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

- **終わったもの**：mbmap の Phase 0〜20 と、その後の点検（mbmap #165 まで）。このリポジトリへ移した（2026-11-15）。
- **名前**（2026-11-15 ユーザー判断）：npm は `moon-map`（入口は `moon-map/ui`、`moon-map/3d` など）、mooncakes は `t-ujiie-g/moonmap`、要素は `<moon-map>`、イベントは `moon-map-error` など、エラーは `moon-map: ...`。コードの識別子やラベルは `moonmap`。
- **進め方**（2026-11-15 ユーザー判断）：
  1. 土台：リポジトリの設定（`main` のルールセット、Dependabot、秘密情報の検出、SECURITY.md）。済み（#1）。
  2. 移行：コードを移し、名前を置き換え、CI を通す。MoonBit のモジュールは直下の 1 つ（`t-ujiie-g/moonmap`）のまま。`moon.work` は rabbita のモジュールを足すときに入れる（ワークスペースでは `_build` の出力がモジュール名の下に出る）。
  3. MoonBit で書けるように：中身（ファサード）は TS のまま、MoonBit には npm の実装を中で使う型付きの API と rabbita の部品を作る（2026-11-15 ユーザー判断。いったん選んだ案 B「ファサードを MoonBit に移す」は、測った大きさを見て取りやめた。下の節）。スタイルは型付きで書け JSON も渡せる（同日のユーザー判断）。API の形（2026-11-15 ユーザー判断）：スタイルは層ごとの関数とラベル付きの引数（MapLibre の `v8.json` から生成、`@style.Layer::json` で JSON も）、rabbita には `<moon-map>` 要素を包んで置き（イベントは rabbita のメッセージ、地図の操作は Cmd から型付き API）、モジュールはエンジンを `t-ujiie-g/moonmap_engine`（内部）、使う人向けを `t-ujiie-g/moonmap` と `t-ujiie-g/moonmap_rabbita` に。MoonBit から npm の実装は `#module` の静的 import で読み（呼べるのは関数なので、npm に `moon-map/moonbit` の入口を足す）、ワーカーと wasm は npm のパッケージが自分の場所から読む。段階：M1 ワークスペースと改名（#7）、M2 `moon-map/moonbit` と `moonmap` の土台（地図、カメラ、イベント、JSON のスタイル編集）、M3 型付きのスタイルと式（生成）、M4 `moonmap_rabbita` と rabbita のデモ。
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
