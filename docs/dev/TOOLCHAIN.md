# Toolchain notes, measured backend facts and benchmark gotchas

Things learned about MoonBit, its backends and the benchmark setup. `AGENTS.md` §3–§5 keep the rules that follow from them; the measurements themselves are in PROGRESS.md and `bench/results/`.

## MoonBit toolchain

- moon 0.1.20261119 uses the **new DSL config files `moon.mod` / `moon.pkg`**, not `moon.mod.json` / `moon.pkg.json`. MoonBit syntax and tooling change quickly: verify APIs with `moon ide doc`, generated `.mbti`, or docs.moonbitlang.com instead of guessing from memory.
- The workspace (`moon.work`), its modules and where build outputs sit: [ARCHITECTURE.md](ARCHITECTURE.md) "MoonBit workspace and API modules".
- `bench/entry` shows the working patterns for exports (`pkgtype(kind: "foreign_library")` + `#export_name`), `export-memory-name`, and per-file conditional compilation (`options(targets: {...})`).
- `moon info` writes `.mbti` from each module's canonical backend: `preferred_target` in `moon.mod`, else wasm. The js-only MoonBit API modules (`moonbit/mbtmap`, `moonbit/mbtmap_rabbita`) set `preferred_target = "js"`, so their public API is tracked like the rest; the engine module stays on wasm, so its js-only packages (`map`, `render_webgl2`, internal) get none (`moon info --target js` only prints the diff against wasm).
- Inline wasm via `extern "wasm" fn f(...) = #|(func ...)` works on both wasm and wasm-gc and is how linear memory is accessed.
- Current idioms the compiler insists on: `#derive(Eq, Debug)` (before the type) on a public type needs a `pub extend T with ...` entry in the package's `extends.mbt` (copy a neighbouring one); `extend` is a keyword; `Ref(x)`, `Map([], capacity=n)`, `Array(capacity=n)`, `@cmp.minimum`; `try?` is gone (`try Some(e) catch { _ => None }`). In a function with a bare `raise`, `catch` can match constructors of several suberror types.
- Script mode (`moon run x.mbtx`) currently fails with a core `gzip` alias conflict, so automation stays in Node scripts under `bench/`.
- Bumping `moon`: update `MOONBIT_VERSION` and both hashes in `scripts/toolchain.env` (CI and `scripts/setup.sh` read it), and record the version in PROGRESS.md.

## Backend facts measured so far

See PROGRESS.md for the numbers' sources. The backend comparison (wasm, wasm-gc, js, `wasm-opt`) and the module-split measurement behind "one wasm per entry" were scripts of the earlier repository `t-ujiie-g/mbmap` (`bench/backend`, `bench/split`), not kept here.

- **In wasm-gc every call to a `raise` function allocates its result object, even on success.** Keep `raise` off hot paths: report errors through sticky state or return values, and raise only at coarse boundaries. This alone made the mvt decoder go from 1.3–2.2× slower than JS to faster than JS.
- wasm (linear memory) uses refcount + TLSF and is 6–9× slower than wasm-gc/JS on allocation-heavy code.
- `wasm-opt -O3` made the wasm-gc mvt decoder 12–45% *slower* in every browser; do not run it on wasm-gc builds. For wasm (linear memory) it helps only on Node 22, whose older V8 does not inline small wasm functions.
- In hot loops `FixedArray` beats `Array` (an `Array` access also loads and checks its length): switching earcut's node pool cut its time by about 25%. Prefer incremental rotation over per-vertex `sin`/`cos`/`atan2` (it made line extrusion about 40% faster).
- V8 does not switch a running wasm call to optimized code, so a worker's first tile runs in baseline code (about 3–5× slower than warm). Warming up with a synthetic tile at init did not help first render in measurements and was removed.
- Sharing one buffer between layers with the same geometry and packing in place instead of copying made `process_tile` 23–27% faster (median tile) and the output 17% smaller. Compiling the worker wasm once on the main thread and sending the module to every worker made no difference to first render and was reverted.
- Line output size matters more than tessellation speed: round caps are square extensions that the line shader cuts with `length(side, along)`, and layers with at most 65536 vertices use 16-bit indices; together they cut the center tile's packed size from 2.0 MB to 0.8 MB and `process_tile` from 5.4 to 3.2 ms.
- Bundle size: `Repr`/`Debug` output and `@string.parse_double` (strconv) pulled about 28KB gzip into the main bundle (49.1 → 20.6KB once removed); shipped code reports errors with `message()` strings instead. A second instantiation of `Expr::eval` cost about 11KB minified but only 0.2KB gzip.
- Copying linear memory into GC `Bytes` is fast when done 4 bytes per load into a `FixedArray[Byte]` and reinterpreted (`bench/entry/linear_memory.mbt`); `Bytes::makei` calls a closure per byte and is 2–6× slower.
- Per-element calls on GC arrays through exported functions were 5–50× slower than passing buffers through linear memory ([ARCHITECTURE.md](ARCHITECTURE.md) "The wasm-gc boundary").

## Benchmark gotchas

- Headless Chromium defaults to SwiftShader; GPU benches must launch with `--use-angle=metal --enable-gpu --ignore-gpu-blocklist`.
- On the M2 dev machine frame time is vsync-capped at 16.67ms even for MapLibre; use per-frame render CPU time (and `--uncapped`) as the proxy metric. Real Android measurement is out of scope for now.
- Bundling MapLibre `src/` with esbuild requires `useDefineForClassFields: false` and an alias to `node_modules/maplibre-gl/src` (package `exports` blocks deep imports).
- Inline `<script type="module">` in bench pages did not execute under Playwright; keep page code in external `.mjs` files.
- Register MapLibre `load`/`idle` listeners immediately after constructing the map (idle can fire in the same task as load).
- Pack-test checks in Firefox and WebKit (`--browser=`): both hand Playwright `console.error(error)` as a bare "Error" (`watchErrors` reads the error object); a one-frame change can be idle before a click returns, so listen first (`awaitAfter`); WebKit on Linux shows an `antialias: false` WebGL canvas one frame late and gives canvases no video frames (`checks/pixels.mjs` `screenshot` draws again first); headless Firefox on Linux has no WebGL2, so the run is skipped there.
- Never pass tile templates through `new URL()`: it percent-encodes `{z}`/`{x}`/`{y}` and every tile 404s (MapLibre then draws an empty map quietly, which voided the render comparisons until Phase 9.2). Check that both engines draw before trusting a comparison.
- `bench/fixtures/gsi-bvmap/` (~13MB) is gitignored; only the manifest is committed. Attribution: 国土地理院ベクトルタイル提供実験.
