# PROGRESS

Where things stand, decisions and open issues. The development history before this repository (Phases 0–20, measurements and reviews) stays in the previous repository `t-ujiie-g/mbmap`; this file starts afresh.

## 現在の状況（2026-11-15）

- **終わったもの**：mbmap の Phase 0〜20 と、その後の点検（mbmap #165 まで）。このリポジトリへ移した（2026-11-15）。
- **名前**（2026-11-15 ユーザー判断）：npm は `moon-map`（入口は `moon-map/ui`、`moon-map/3d` など）、mooncakes は `t-ujiie-g/moonmap`、要素は `<moon-map>`、イベントは `moon-map-error` など、エラーは `moon-map: ...`。コードの識別子やラベルは `moonmap`。
- **進め方**（2026-11-15 ユーザー判断）：
  1. 土台：リポジトリの設定（`main` のルールセット、Dependabot、秘密情報の検出、SECURITY.md）。済み（#1）。
  2. 移行：コードを移し、名前を置き換え、CI を通す。MoonBit のモジュールは直下の 1 つ（`t-ujiie-g/moonmap`）のまま。`moon.work` は rabbita のモジュールを足すときに入れる（ワークスペースでは `_build` の出力がモジュール名の下に出る）。
  3. MoonBit への移行：TS のファサードを MoonBit に移す（案 B）。どう移すかは、着手の前に計測と案を示してユーザーと決める（大きな設計の変更、AGENTS §2）。rabbita のモジュールとデモ。
  4. 文書：英語の README（日本語版も）、docs/ の API とガイド。MapLibre などと張り合う書き方はしない。ベンチは前に出さない。
  5. GitHub Pages：手書きの LP と、依存ゼロの marked で docs を HTML に、動く examples（html / web component / React / MoonBit）。
  6. 公開の準備：Firefox・WebKit での pack test、npm 0.1.0 と mooncakes の公開（ユーザーが実行）。
  7. その後：単独で使える移植（`mvt`、geojson-vt、`proj` など）を mooncakes に。Phase 21。
- **前のリポジトリから引き継ぐ未解決**：
  - `protomaps` のフィクスチャの版（`build.protomaps.com/20261103.pmtiles`）が消えた（404）。新しい日付にする。
  - `npm:pack` の `showcase-element` がこの Mac でときどき 180 s で落ちる（表の行のクリックの後に地図が止まらない。CI では通る）。
  - 3D の断面の枠の半径（6371008.8 m）とモデルの位置の半径（6378137 m）が楕円体の値とそれぞれ 0.23%・0.11% ずれる（100 m で約 0.2 m）。直すなら緯度で半径を決める。
  - Mac で回すもの：`style:public`・`style:compat`、`render` の変種（`--labels` など）、MapLibre の基準の取り直し。
