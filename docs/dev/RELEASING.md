# Releasing

npm の `mbt-map` と mooncakes の `t-ujiie-g/mbtmap`・`t-ujiie-g/mbtmap_rabbita` は同じ版で出す。タグ `vX.Y.Z` を打つと `.github/workflows/release.yml` が npm への段階公開、mooncakes への公開、GitHub のリリースを、`pages.yml` がサイトの公開を行う。

## 版を上げる（PR で）

1. `npm/package.json` の `version`、`moonbit/mbtmap/moon.mod` と `moonbit/mbtmap_rabbita/moon.mod` の `version`、`mbtmap_rabbita` が import する `t-ujiie-g/mbtmap@…`（`bench/moonbit` と `examples/rabbita` の import も）を新しい版にする。
2. `CHANGELOG.md` に `## X.Y.Z` の節を書く（GitHub のリリースの本文になる）。
3. `npm --prefix bench test` の `release.test.mjs` が、版と CHANGELOG がそろっているかを見る。マージする。

## タグを打つ

```sh
git switch main && git pull
git tag vX.Y.Z && git push origin vX.Y.Z
```

`release.yml`：
- `verify`：タグと版と CHANGELOG（`node bench/lib/release.mjs vX.Y.Z`）、MoonBit のテスト、npm のビルド・テスト・大きさ。
- `npm`：信頼された公開（OIDC、トークンなし）で `npm stage publish`。npm の Staged Packages で 2FA で承認すると公開される（`npm stage approve <id>` でも）。その版が npm にもうあれば飛ばす。
- `mooncakes`：リポジトリの secret `MOONCAKES_TOKEN` があれば `mbtmap`、続けて `mbtmap_rabbita` を公開する（索引に載るのを待って 5 回まで試す）。なければ手で公開する（下）。
- `github-release`：CHANGELOG の節を本文にリリースを作る。

## 初めての公開（0.1.0、一度だけ）

npm の信頼された公開は、パッケージが npm にないと設定できない。最初の版は手元から出す。

1. `npm --prefix npm run build`（MoonBit のツールチェーンが要る）。
2. `cd npm && npm publish`（`publishConfig.access` は public。2FA を聞かれる）。
3. npmjs.com → mbt-map → Settings → Trusted publishing：GitHub Actions、owner `t-ujiie-g`、repository `mbt-map`、workflow `release.yml`、environment なし、権限は段階公開だけ（`npm stage publish`）。設定から 2 日以内に最初の公開が要るので、次の版のタグはそれまでに打つか、期限が切れたら作り直す。
4. mooncakes：`moon login` 済みの手元で `cd moonbit/mbtmap && moon publish`、続けて `moon update && cd ../mbtmap_rabbita && moon publish`。CI で出すなら、`~/.moon/credentials.json` の `token` をリポジトリの secret `MOONCAKES_TOKEN` にする（`gh secret set MOONCAKES_TOKEN`、値は画面に出さない）。
5. タグ `v0.1.0` を打つ：npm と mooncakes はもうあるので飛ばされ、GitHub のリリースと Pages が出る（mooncakes は同じ版を二度出せないので、手で出したなら secret はタグの後に置く）。
