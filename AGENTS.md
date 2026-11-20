# AGENTS.md — mbt-map

Contributor and AI-agent guide (Claude Code, Codex, Cursor, …). `CLAUDE.md` is a symlink to this file. It holds what every session needs: the rules, a map of the repository and the invariants. The detail lives in `docs/dev/`.

mbt-map is a WebGIS library: a MoonBit engine compiled to wasm-gc and JS, a MapLibre-shaped TypeScript facade shipped as the npm package `mbt-map` (with entries for UI, search, drawing, services, data, analysis and 3D), MoonBit API modules, examples, and golden tests against reference implementations in `bench/`.

| Read | For |
| --- | --- |
| `PROGRESS.md` | Where things stand (its top), decisions, measurements, open issues. Read it and VISION before starting a phase. |
| `docs/dev/VISION.md` | The authoritative spec: goals, perf targets and budgets (§2), architecture (§3), design principles (§4), what is deferred or out of scope (§5), API policy (§6), work rules (§7), the plan from here (§8). The history of Phases 0–20 is in the earlier repository `t-ujiie-g/mbmap`. |
| `docs/dev/ARCHITECTURE.md` | Per-subsystem reference and its index (`-RENDERING`, `-MODULES`, `-3D`). Read the part you are about to change. |
| `docs/dev/FORMATS.md` | Binary formats and worker messages; code cites its section names instead of restating layouts. |
| `docs/dev/COMMANDS.md` | Every command and golden, with what it compares and its pass condition. |
| `docs/dev/TOOLCHAIN.md` | MoonBit toolchain notes, measured backend facts, benchmark gotchas. |
| `docs/dev/RELEASING.md`, `docs/dev/CLOUD.md` | Release steps; Claude Code on the web. |

If a task is not in the current phase of VISION §8, confirm scope with the user before widening it. MoonBit skills (`moonbit-agent-guide`, `moonbit-orientation`, `moonbit-refactoring`, …) come from the `moonbit-skills` plugin (`/plugin` → marketplace `moonbitlang/skills`) and auto-engage in `.mbt` files.

## 1. Commands

The validation loop, before committing or reporting complete (from the repository root):

```sh
moon check --target all      # wasm, wasm-gc, js, native; --deny-warn after a refactor (§7.9)
moon test --target all       # one package: moon test <pkg-dir> --target all [-F "glob"]; snapshots: -u on a single target
moon fmt
moon info                    # commit .mbti diffs with the code; a diff means the public API changed: check it is intended
npm --prefix npm run build && npm --prefix npm test && npm --prefix npm run size
npm --prefix bench test      # bench tooling, docs links, release versions
npm --prefix bench run npm:pack   # CI runs it
node bench/lib/long-comments.mjs  # comment blocks over three lines (§7.7)
```

plus the goldens of the area touched: `npm --prefix bench run <area>:golden` (the list, what each compares and its "must stay …" condition are in `docs/dev/COMMANDS.md`).

- `npm:pack` builds and packs `npm/`, installs it into the examples and test pages and checks them in a browser. Options after `--`: `--browser=firefox|webkit` (CI's `pack firefox …` / `pack webkit …` jobs), `--only=a,b` / `--except=a,b` (checks by name), `--no-prepare` (reuse the last packing).
- `npm test` in `npm/` runs with Node type stripping: modules under test must be import-free or import other files with their extension (`./style.ts`).
- First use: `scripts/setup.sh`, or by hand `npm ci` in `npm/`, `bench/` and `examples/react/`, then in `bench/` `npx playwright install chromium firefox webkit` and `npm run fixtures`.
- In `bench/`: `npm run example` serves the repository on 127.0.0.1:8080, `npm run examples` packs `npm/` into the examples first, `npm run site` builds the GitHub Pages site into `_site/`, `npm run moonbit:style` regenerates the MoonBit API's typed style functions (`npm test` fails while they are stale), `node lib/release.mjs vX.Y.Z` checks a release tag against the versions and `CHANGELOG.md`.
- Results go to `bench/results/*.json`; numbers in PROGRESS.md must come from there (VISION §2: never claim "fast" without a reproducible script).

## 2. Workflow

How the user works with agents (standing instructions; they hold in every session, local or on the web):

- Reply to the user in Japanese, short status lines and `AskUserQuestion` dialogs included. Code, identifiers, commit messages and PR descriptions stay in English.
- Never commit to `main` directly: `git switch -c <kind>/<short-description>` (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `phaseN/`), then `gh pr create`.
- Each step ends the same way: validation (§1), commit, push, a PR, CI green, then a short Japanese report of what changed, measured results and open questions, and stop. The user merges and answers 「マージしました」 (often with 「続けて下さい」); never start the next step before that. When several PRs are ready, report and get them merged one at a time, merging `main` into the next before reporting it.
- Never force-push or amend a pushed commit; to bring a branch up to date, merge `origin/main` into it.
- Phase starts, budget changes and design changes are asked with `AskUserQuestion`, with a recommended option first. Major design changes (Wasm backend, package split, rendering approach) need measurements and options presented and the user's confirmation first (VISION §7).
- Phases (VISION §8): confirm a phase's scope, steps and completion criteria with the user before starting it, and deliver it in steps (one PR each, e.g. 13.1-13.4). When a phase is complete, run a refactoring and security review (§7, §8) over what it added before starting the next. PROGRESS.md opens with where things stand.
- A change that claims a perf effect reruns the relevant `bench/` script and updates PROGRESS.md with the new numbers.
- Releases (`docs/dev/RELEASING.md`): one version for the npm package and the MoonBit API modules. A `v*` tag publishes npm (staged through trusted publishing, approved with 2FA), the GitHub release (from `CHANGELOG.md`) and the site. The MoonBit modules are published by hand with `moon publish`: no mooncakes token goes into CI secrets (it never expires and covers the whole account). The user tags, approves and publishes.

Parallel work. Use parallel agents wherever the work splits: the user prefers starting independent lines at once over proposing them and waiting. At the start of a phase or step, look for work that does not depend on the main line (research for the next phase, leftover known issues, benchmarks) and start it alongside, saying what was split off.

- Research runs as a read-only subagent that reports back. The findings go into VISION/PROGRESS when that phase starts, never into a separate planning doc.
- Code runs in its own git worktree and branch (`Agent` with `isolation: "worktree"`, or `git worktree add ../mbt-map-<name> -b <branch>`). Each worktree needs `npm ci` in `bench/`, `npm/` and `examples/react/`, and a copy of `bench/fixtures/` (gitignored). `_build/` is per worktree, and `bench/lib/serve.mjs` picks a free port, so pack tests can run side by side.
- Keep apart: work that must wait for a confirmation (a phase's scope, the review after a phase), and work touching the same files as the main line. Files that often conflict: the top of `PROGRESS.md`, `AGENTS.md`, `npm/scripts/size.mjs`, `bench/npm/pack-test.mjs`, `examples/shared/*`, `npm/src/ui.ts`. Merge `main` into the branch before reporting the PR.
- Never run performance benchmarks in parallel: they compete for the GPU and CPU. Agents that measure take a lock around each run (`until mkdir "$TMPDIR/mbt-map-bench.lock" 2>/dev/null; do sleep 5; done; …; rmdir "$TMPDIR/mbt-map-bench.lock"`), and the main line reruns the final numbers alone.
- Each line of work is still one PR per step, reported and merged one at a time.

## 3. Toolchain

- moon 0.1.20261117 (pinned in `scripts/toolchain.env`) uses the DSL config files `moon.mod` / `moon.pkg`, not `moon.mod.json` / `moon.pkg.json`. MoonBit syntax and tooling change quickly: verify APIs with `moon ide doc`, the generated `.mbti` or docs.moonbitlang.com instead of guessing from memory.
- The repository is a `moon.work` workspace, so build outputs sit under the module name: `_build/<target>/<mode>/build/t-ujiie-g/mbtmap_engine/<package>/`.
- `moon info` writes `.mbti` from each module's `preferred_target` (else wasm): the engine's js-only packages (`map`, `render_webgl2`) get none.
- Automation stays in Node scripts under `bench/` (script mode, `moon run x.mbtx`, currently fails).
- Compiler idioms, export patterns and the rest: `docs/dev/TOOLCHAIN.md`.

## 4. Architecture

Where things live (the reference is `docs/dev/ARCHITECTURE.md` and its companions):

- Engine, MoonBit packages at the root (module `t-ujiie-g/mbtmap_engine`, internal):
  - Pure, tested on every backend: `core` (camera math, tile covering, byte readers and writers, shared constants), `tess`, `style`, `globe`, `geom`, `formats`, `tiler`, `tableops` and the ports the modules run (`analysis`, `relate`, …).
  - `ports/`: ports published on mooncakes on their own, one module each (`ports/clipper` is `t-ujiie-g/clipper`; also `draco`, `geodesic`, `lepcc`, `meshopt`, `mvt`, `pbf`, `proj`, `robust`, `tiff`, and `trig`, the `Trig` they and `core` share). They import nothing of the engine; the engine imports them through the workspace. Versions and publishing: `docs/dev/RELEASING.md`.
  - js only: `render_webgl2`, `map` (DOM events, workers, the frame loop), `bundle/main` (the engine's exports).
  - wasm-gc entries, one wasm each in its own worker: `worker` (the display worker: decode, tessellate, pack tiles) and the `*_worker` packages; `wasmio` is their linear-memory I/O.
- `npm/`: the package. `npm/src/index.ts` is the facade over `bundle/main` (keep `npm/src/engine.d.ts` and the pages that call the exports directly in sync with `bundle/main/main.mbt`); the other entries are `npm/src/{ui,search,draw,geodesic,services,table,data,analysis,3d}.ts`; `npm/scripts/size.mjs` holds the gzip budgets. Worker glue is in `<package>/js/`.
- `element/`: `<mbt-map>` (`mbt-map/element`). `moonbit/`: the published MoonBit API (`mbtmap`, a typed binding to the npm package, and `mbtmap_rabbita`).
- `examples/`: one showcase written three ways (`html/`, `element/`, `react/`) over `examples/shared/` (each phase adds its features to all three), `plateau/`, `rabbita/`, `samples/`. `site/` and `bench/site/`: the GitHub Pages site.
- `bench/`: goldens, benchmarks, the pack test (`bench/npm/`), dev pages (`bench/pages/`), tooling (`bench/lib/`). `scripts/`: setup and the pinned toolchain.

Dependency direction, never reversed (every chain is in `docs/dev/ARCHITECTURE.md`): `pbf ← mvt ← tess/style ← worker` (`core` under `tess` and `style`); `core ← geom ← formats/tiler ← … ← *_worker`; `core ← globe ← render_webgl2 ← map ← bundle/main ← (npm, element) ← moonbit/mbtmap ← moonbit/mbtmap_rabbita`; `wasmio ← wasm-gc entries` only.

Invariants that prevent expensive mistakes:

- `map` must not import `worker` (it would pull mvt/tess into the main bundle); shared constants live in `core` or are mirrored with a pointer to the original (`worker/js/mirror.test.mjs` checks the JS mirrors). Nothing under `map/` may depend on a UI framework.
- The main thread never touches geometry (VISION §4-3), and only the main thread parses and compiles styles: display workers get the compiled bytes, which keeps the parser and compiler (about 22KB gzip) out of the worker wasm.
- One wasm module per entry, run in its own lazily started worker; a feature group gets its own module once its code exceeds ~20KB gzip. `map` and the facade never import the data, analysis, services or 3D entries, which exchange data with the display only through columnar buffers; never link analysis into the display worker. A new entry or module needs a row in `npm/scripts/size.mjs`; bundle sizes are budgets (VISION §2).
- In wasm-gc every call to a `raise` function allocates, even on success: keep `raise` off hot paths, report errors through sticky state (`pbf` reads never raise) and raise only at coarse boundaries.
- Hot paths (pbf/mvt decode, tessellation, worker packing, per-frame rendering) stay allocation-free and write into preallocated `FixedArray`/`Bytes`. Data crosses the JS boundary as buffers in linear memory, never element by element through exports (5–50× slower).
- wasm-gc entries never link core `@json`/`strconv` (24–27KB gzip each: numbers go to the host's `Number()`), `Repr`/`Debug` output (errors are `message()` strings) or core `@math` (the host's `Math` comes in through `@core.Trig`, which is `ports/trig`'s; the clipper port alone keeps `@math`).
- Never run `wasm-opt` on wasm-gc builds (12–45% slower in every browser).
- Ports must keep matching their reference exactly: a golden's "must stay identical / 0 differ" is a hard condition. Do not swap in "equivalent" algorithms (sorts, priority queues, rounding).
- Everything fetched at runtime is untrusted (§8.2); raw-address load/store validates every offset and length.
- Key handlers that pages wire to controllers leave IME composition keys alone (`isComposing`, `keyCode` 229).

## 5. Benchmarks

- Performance numbers come from the M2 dev machine only, measured alone (never in parallel, §2), with the GPU (`--use-angle=metal --enable-gpu --ignore-gpu-blocklist`; headless Chromium otherwise uses SwiftShader). Frame time is vsync-capped there, so compare per-frame render CPU time (`--uncapped`).
- Check that both engines draw before trusting a comparison. Never pass tile templates through `new URL()` (it percent-encodes `{z}`/`{x}`/`{y}` and every tile 404s).
- The other gotchas (Playwright, MapLibre bundling, Firefox and WebKit in the pack test, fixtures) are in `docs/dev/TOOLCHAIN.md`.

## 6. Testing conventions

- Golden data: compare against existing implementations via scripts in `bench/`. Tessellation must also check that total triangle area equals polygon area.
- Every `pub fn` gets ≥1 direct test; every error path (`raise`, `None`) is covered. Tests run on all backends (CI runs wasm-gc and js; wasm and native are tested by the local loop only).
- Prefer `assert_eq` (or `assert_true(x is Pattern(...))`) over snapshots for stable results; derive `Debug` + `debug_inspect` for structured output.
- A test that only re-runs the type checker (`let _ = …`) duplicates `moon check`; delete it.
- Fixtures from external sources carry their attribution (fixtures README and `NOTICE-dev.md`; `NOTICE`, which ships, lists only third-party code that is distributed).

## 7. Refactoring checklist

When the user says **「リファクタリング」 / "refactor" / "tidy up" / "clean up"**, walk these lenses **in order** and write a concrete findings list **before** changing code (consider the `moonbit-refactoring` skill), whether the target is one file or the whole tree.

### 7.1 Constants
Promote magic numbers and repeated literals that name a concept to a `pub let` in the owning package, defined exactly once: extents (`@core.TILE_EXTENT`, VISION §4-2), protobuf wire types and field numbers, Style Spec keys, vertex attribute layouts and strides, worker message type tags.

### 7.2 Duplicate / dead code
- Consolidate identical helpers in the lowest package that may own them, respecting the dependency direction (§4).
- Delete comment-only stub `.mbt` files once a package holds real API; drop unused imports (`unused_package`); make `pub` items with no external caller private, or delete them.

### 7.3 File splitting
A `.mbt` file over ~500 lines is a smell, not a rule. Split only at a logical boundary (varint reader vs message walker; earcut vs line extrusion), never to hit a line count. Keep blackbox (`*_test.mbt`) and whitebox (`*_wbtest.mbt`) tests separate.

### 7.4 Test adequacy
§6 holds: golden tests at every decode/tessellation boundary, the area check for tessellation, every error path covered. Tests assert on values, not just shapes, and pass on all four targets.

### 7.5 Performance
- Hot paths stay allocation-free (§4).
- A refactor touching a hot path reruns the relevant bench and records any regression in PROGRESS.md before merging.
- A refactor must not add dependencies or runtime code to the main-thread bundle without measuring.
- Every refactor also looks for measurable wins in the code it covers. Find the cost first: profile or break the bench down (per-stage rows, `--output-wat` for wasm-gc) instead of guessing. Known traps: `raise` on hot paths, `Array` vs `FixedArray` in tight loops, per-element boundary calls, per-vertex trig, oversized output (`docs/dev/TOOLCHAIN.md`).
- List each candidate with its expected effect before changing code; keep a change only if the bench shows a win beyond run-to-run noise on the target browsers and no regression elsewhere.
- Record what was tried in PROGRESS.md, including changes that did not help and were reverted, so they are not retried blindly.

### 7.6 Documentation freshness
PROGRESS.md, VISION.md and `docs/dev/ARCHITECTURE*.md` match the code state; public APIs have `///` doc comments; `.mbti` is regenerated and its diff is the intended public-API change.

### 7.7 Comment hygiene
**The default is no comment.** Comment only where a reader cannot recover the intent from the code. Keep it to one or two lines, three at most. `node bench/lib/long-comments.mjs` lists the blocks over three lines.

- **Delete what the code already says.** If code needs a paraphrase, fix the code instead: a better name, a named intermediate, a smaller function.
- **Delete documentation that wandered into source.** Design rationale and package tours belong in VISION.md, PROGRESS.md, `docs/dev/` or README; the source may cite them but must not restate them. File-header essays and section banners are this failure mode; `///|` already separates blocks.
- **Delete narration of the past** (what used to happen, what a commit changed). If a bug explains a non-obvious line, keep the reason in one clause and cite the issue (`#N`).
- **Keep the constraint the code can't show**: a spec rule (MVT spec section, Style Spec property, WebGL2 limit), an invariant the compiler doesn't enforce, a deliberate deviation.
- **No phase codes in comments** (`Phase 2`). Name the thing instead. Issue numbers and spec section references are fine.
- No comments between the items of an enumeration: enum variants, struct fields, TS interface members, array and object literals, tables of cases (MoonBit, TS and JS alike). Describe the items in the doc comment above the whole (e.g. "`a`: ..., `b`: ...") or next to the code that uses them.
- Tests get the same treatment: the test name says what it asserts.

### 7.8 Latest MoonBit language-spec conformance
- Migrate deprecated constructs rather than suppressing the warnings.
- Verify constructs against `moon ide doc`, the `moonbit-orientation` skill and local sources, not memory.
- Adopt current idioms where they help clarity: `raise` error handling, pattern-match views, labelled/optional args, method syntax, iterators, derive macros.
- If a `moon` version bump changes formatting or generated output, land that diff on its own.

### 7.9 Validation loop after refactoring
The loop of §1 with `moon check --target all --deny-warn`, then the §8 security check on the touched area. Push only when everything is clean.

## 8. Security check

Run this when the user says **「セキュリティチェック」 / "security check"**, as part of every refactor (§7.9), and before adding or upgrading any dependency or cutting a release. Report findings as a list (severity, location, fix) before changing code.

### 8.1 Dependencies and supply chain
- `npm audit` in every directory with a `package.json` (`bench/`, `npm/`). Also check Dependabot and security advisories for the repo: `gh api repos/{owner}/{repo}/dependabot/alerts`.
- Advisories move faster than `npm audit` sometimes reflects: for each direct dependency, check its GitHub Security Advisories and release notes for the pinned version, especially MapLibre, Playwright, esbuild and anything in the shipped bundle.
- Pin exact versions (`--save-exact`) and commit the lockfile. CI uses `npm ci`, never `npm install`.
- Before adding a package, check its maintainer, download history, install scripts (`preinstall`/`postinstall`) and whether it is a typosquat. Prefer no new dependency when a few lines will do (bundle budget, VISION §2).
- MoonBit deps (`moon.mod` `import`): pin versions, and review the source of new mooncakes packages (`moon fetch`) before depending on them. Keep the toolchain current with `moon upgrade` (then `MOONBIT_VERSION` and both hashes in `scripts/toolchain.env`) and record the version in PROGRESS.md.
- Never pipe a remote script to a shell, and never run downloaded code from its own directory. Fixtures and downloaded tiles are data: verify them against the sha256 manifest.

### 8.2 Untrusted input (tiles, styles, GeoJSON, URLs)
Everything fetched at runtime is attacker-controllable. Decoders must fail safely on malformed input:
- **pbf/mvt**: bounds-check every read. Reject varints longer than 10 bytes and length-delimited fields that exceed the remaining buffer. Cap nesting, feature, key and value counts. No input may produce an infinite loop (zero-length fields, `ClosePath`/`MoveTo` command counts of 0 or huge).
- **tess**: cap vertex and index counts per tile, guard against degenerate or self-intersecting rings blowing up earcut, and check that integer math on quantized coordinates (Int16, VISION §4-2) cannot overflow silently.
- **style**: expression evaluation is bounded (depth, array sizes); no `eval`/`new Function`. Unknown expressions fail with a diagnostic, never execute.
- **GeoJSON**: limit size and coordinate count before tiling. `JSON.parse` only, and keep `__proto__` keys out of property maps (prototype pollution).
- **worker linear memory**: raw-address load/store in `worker/` and `wasmio` must validate every offset and length against the region it owns. A bad length must never read or write outside it. This is the one place where MoonBit's bounds checks don't protect us.

### 8.3 Web platform
- No `innerHTML`/`outerHTML`/`insertAdjacentHTML` with data from tiles, styles or attributes. Use `textContent` and DOM APIs (labels, attribution strings in `<mbt-map>`).
- Work under a strict CSP: no `eval`, no `new Function`, and workers loaded from same-origin URLs. Documented exceptions, all in `workerScriptUrl` (`npm/src/urls.ts`): a worker URL the page gives (`workerUrl`, `<mbt-map worker-url>`) must be http(s) on the page's origin or inside the library's own folder (its `dist/` on a CDN; other folders of that origin are refused, since CDNs serve every package from one origin), never `data:` or `blob:`; the library's own default worker, whose URL comes from its code and the bundler and never from run-time input, may be on any http(s) origin (a bundler's asset host) or a `data:` URL a bundler inlined, and is then started through a same-origin `blob:` script (`worker-src blob:` under a CSP).
- Fetches for tiles, styles and sprites send no credentials by default. URL templates may only substitute MapLibre's placeholders (`{z}/{x}/{y}`, `{prefix}`, `{ratio}`, `{quadkey}`, `{bbox-epsg-3857}`, `{bbox}`; `TILE_PLACEHOLDERS` in `npm/src/urls.ts`, `tile_url` in `map/dom.mbt`), with no open redirects or arbitrary schemes. Any request transform hook is the caller's responsibility and documented as such.
- `postMessage` handlers check message shape and type and ignore unknown messages.
- `<mbt-map>` attributes (`style-url`, `center`, …) are parsed strictly; invalid values are rejected, not coerced.

### 8.4 Repo and tooling hygiene
- No secrets, tokens or personal data in code, fixtures, bench results or commit messages. Bench results record the environment, not user identifiers.
- `bench/lib/serve.mjs` is a dev-only server: it must bind to `127.0.0.1`, refuse paths outside the repo root and dotfiles (`.git`, `.env`), and survive malformed URLs. `bench/lib/serve.test.mjs` pins this down.
- Ported code keeps its license header and a `NOTICE` entry (VISION §7). License review is part of the dependency check.

## 9. Claude Code on the web

`docs/dev/CLOUD.md` has the environment and what differs there. In short: only the repo carries over (no local memory or plugins, which is why §2's standing instructions live here); if `moon` is missing, run `scripts/setup.sh` first; the validation loop and the goldens run there, performance benchmarks do not (§5: a step that needs new measurements says so in its report); if `gh pr create` or `gh pr checks` fail behind the proxy, use the REST calls in CLOUD.md §3.

## 10. Things to avoid

- ❌ Planning docs outside VISION.md / PROGRESS.md.
- ❌ Reversing the package dependency direction, or UI-framework dependencies under `map/`.
- ❌ Allocation in hot paths without a measured reason.
- ❌ Perf claims without a `bench/` script and a results JSON.
- ❌ Adding dependencies without the §8.1 check and a note in PROGRESS.md.
- ❌ Trusting tile, style or GeoJSON input (§8.2).
- ❌ Suppressing deprecation or `unused_*` warnings instead of fixing them.
- ❌ Skipping `moon fmt` / `moon info` before committing, or bypassing hooks with `--no-verify`.
- ❌ Growing this file: subsystem detail goes to `docs/dev/ARCHITECTURE*.md`, commands to `docs/dev/COMMANDS.md`.
