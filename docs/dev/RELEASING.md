# Releasing

npm の `mbt-map` と mooncakes の `t-ujiie-g/mbtmap`・`t-ujiie-g/mbtmap_rabbita` は同じ版で出す。タグ `vX.Y.Z` を打つと `.github/workflows/release.yml` が npm への段階公開と GitHub のリリースを、`pages.yml` がサイトの公開を行う。mooncakes は手で公開する（mooncakes のトークンは期限がなくアカウント全体に効き、OIDC のような仕組みもないので、CI の secret には置かない）。

## 版を上げる（PR で）

1. `npm/package.json` の `version`、`moonbit/mbtmap/moon.mod` と `moonbit/mbtmap_rabbita/moon.mod` の `version`、`mbtmap_rabbita` が import する `t-ujiie-g/mbtmap@…`（`bench/moonbit` と `examples/rabbita` の import も）を新しい版にする。
2. `CHANGELOG.md` に `## X.Y.Z` の節を書く（GitHub のリリースの本文になる）。
3. `npm --prefix bench test` の `release.test.mjs` が、版と CHANGELOG がそろっているかを見る。マージする。

## mooncakes に出す（タグの前後どちらでも、手元で）

`moon login` 済みの手元で：

```sh
git switch main && git pull
cd moonbit/mbtmap && moon publish
cd ../mbtmap_rabbita && moon update && moon publish   # mbtmap の新しい版が索引に載ってから
```

## 単独で使える移植（`ports/`）

`ports/<名前>/` は 1 つずつが mooncakes のモジュール（`t-ujiie-g/<名前>`）で、エンジンはワークスペース経由で import する。版は移植ごとに独立で、mbt-map の版とはそろえない。その移植のコードか公開 API が変わったときだけ上げる。

1. `ports/<名前>/moon.mod` の `version` と、ルートの `moon.mod` が import する `t-ujiie-g/<名前>@…` を同じ版にする（`npm --prefix bench test` の `ports.test.mjs` が見る。README・LICENSE・NOTICE があることも）。PR でマージする。
2. 手元で `cd ports/<名前> && moon package --list` で入るファイルを確かめ、`moon publish`。ほかの移植に依存するもの（`mvt` は `pbf`、`proj` と `geodesic` は `trig`）は、依存される側を先に出す。梱包したものがリポジトリの外で通るかは、`moon package` の zip を 1 つの空のフォルダに展開し、それらを並べた `moon.work` を置いて `moon check --target all` と `moon test --target all` で確かめられる。

## タグを打つ

```sh
git switch main && git pull
git tag vX.Y.Z && git push origin vX.Y.Z
```

`release.yml`：
- `verify`：タグと版と CHANGELOG（`node bench/lib/release.mjs vX.Y.Z`）、MoonBit のテスト、npm のビルド・テスト・大きさ。
- `npm`：信頼された公開（OIDC、トークンなし）で `npm stage publish`。npm の Staged Packages で 2FA で承認すると公開される（`npm stage approve <id>` でも）。その版が npm にもうあれば飛ばす。
- `github-release`：CHANGELOG の節を本文にリリースを作る。

## 信頼された公開の設定

0.1.0 は手元から出した（npm の信頼された公開は、パッケージが npm にないと設定できない）。設定は npmjs.com → mbt-map → Settings → Trusted publishing：GitHub Actions、owner `t-ujiie-g`、repository `mbt-map`、workflow `release.yml`、environment なし、権限は段階公開だけ（`npm stage publish`）。設定から 2 日以内に最初の公開がないと期限が切れるので、`npm` のジョブが認証で落ちたら作り直してタグのジョブを再実行する。
