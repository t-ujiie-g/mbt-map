// mbt-map under bundlers: installs the packed tarball and pinned bundlers into a temporary directory outside
// the repository, builds bench/bundlers/app with each (and starts their dev servers) and checks in Chromium
// that the map draws, a query finds the features and the analysis, geodesic and data workers answer.
// Usage: node bundlers/run.mjs [--only=vite,webpack] [--no-build] [--keep]   (downloads the bundlers from npm)
import { execFile, execFileSync, spawn } from "node:child_process";
import { copyFile, cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { chromium } from "playwright";
import { arg } from "../lib/args.mjs";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";

const VERSIONS = {
  vite: "8.3.8",
  webpack: "5.112.2",
  "webpack-cli": "7.3.1",
  "webpack-dev-server": "6.1.0",
  rollup: "4.68.3",
  "@rollup/plugin-node-resolve": "16.0.3",
  "@web/rollup-plugin-import-meta-assets": "3.0.1",
  esbuild: "0.28.2",
  parcel: "2.16.4",
};
const APP = path.join(ROOT, "bench/bundlers/app");
const HOST = "127.0.0.1";
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".wasm": "application/wasm", ".css": "text/css", ".json": "application/json" };
// What the documentation says to copy beside an esbuild bundle (docs/getting-started.md "Bundlers").
const ESBUILD_COPIES = /\.wasm$|(worker(-\w+)?|data-\w+|analysis-\w+|prjwkt|projstring)\.js$/;
// Parcel compiles every file named by `new URL(…, import.meta.url)` into its own module format, so the
// library's module workers and their parts lose their exports: checked to notice when that changes.
const KNOWN_FAILURES = ["parcel dev", "parcel build"];
// The app with the library's entries imported at run time from `./mbt-map/` (a copy of its dist/).
const UNBUNDLED_IMPORTS = `const lib = (file) => import(new URL(\`mbt-map/\${file}\`, document.baseURI).href);
const [{ Map }, { load }, { parse }, { inverse }] = await Promise.all(["index.js", "analysis.js", "table.js", "geodesic.js"].map(lib));
`;
const run = promisify(execFile);

function freePort() {
  return new Promise((resolve) => {
    const s = http.createServer().listen(0, HOST, () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

/** Serves `root` on a free port; `cors` as a CDN would. */
async function serveDir(root, { cors = false } = {}) {
  const server = http.createServer(async (req, res) => {
    try {
      let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
      if (p.endsWith("/")) p += "index.html";
      const file = path.join(root, path.posix.normalize(p));
      if (!file.startsWith(root + path.sep)) throw new Error("outside");
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] ?? "application/octet-stream", ...(cors ? { "access-control-allow-origin": "*" } : {}) }).end(body);
    } catch {
      res.writeHead(404).end("not found");
    }
  });
  await new Promise((resolve) => server.listen(0, HOST, resolve));
  return { origin: `http://${HOST}:${server.address().port}`, close: () => server.close() };
}

async function project(tmp, name, tarball, packages, files) {
  const dir = path.join(tmp, name);
  await mkdir(path.join(dir, "src"), { recursive: true });
  await copyFile(path.join(APP, "main.js"), path.join(dir, "src/main.js"));
  for (const [file, text] of Object.entries(files)) await writeFile(path.join(dir, file), text);
  // Install scripts are not run (AGENTS.md §8.1); none of these bundlers needs its own.
  await run("npm", ["install", "--no-audit", "--no-fund", "--ignore-scripts", "--save-exact", tarball, ...packages.map((p) => `${p}@${VERSIONS[p]}`)], { cwd: dir });
  return dir;
}

const html = async (script) => (await readFile(path.join(APP, "index.html"), "utf8")).replace("SCRIPT", script);
const bin = (dir, name) => path.join(dir, "node_modules/.bin", name);

/** Starts a dev server and waits until it answers; the returned function stops it. */
async function devServer(dir, command, args, origin) {
  const child = spawn(command, args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"], detached: true });
  let log = "";
  child.stdout.on("data", (d) => (log += d));
  child.stderr.on("data", (d) => (log += d));
  const stop = () => {
    try {
      process.kill(-child.pid);
    } catch {}
  };
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) break;
    if (await fetch(origin).then((r) => r.ok, () => false)) return stop;
    await new Promise((r) => setTimeout(r, 500));
  }
  stop();
  throw new Error(`the dev server did not start: ${log.slice(-600)}`);
}

async function build(dir, command, args) {
  await rm(path.join(dir, "dist"), { recursive: true, force: true });
  await run(command, args, { cwd: dir }).catch((e) => {
    throw new Error(`the build failed: ${`${e.stdout ?? ""}${e.stderr ?? ""}`.slice(-800)}`);
  });
}

// Each scenario prepares its project in `tmp` and gives the URL to open and what to stop afterwards.
const WEBPACK_CONFIG = (port, publicPath) => `module.exports = {
  entry: "./src/main.js",
  output: { clean: true${publicPath ? `, publicPath: ${JSON.stringify(publicPath)}` : ""} },
  performance: { hints: false },
  devServer: { host: "${HOST}", port: ${port}, static: "./public", client: { overlay: false } },
};
`;
const ROLLUP_CONFIG = `import resolve from "@rollup/plugin-node-resolve";
import { importMetaAssets } from "@web/rollup-plugin-import-meta-assets";
export default { input: "src/main.js", output: { dir: "dist", format: "es" }, plugins: [resolve(), importMetaAssets()] };
`;
const PARCEL_PACKAGE = { private: true, source: "src/index.html", "@parcel/resolver-default": { packageExports: true } };

const BUNDLERS = {
  vite: {
    packages: ["vite"],
    files: async () => ({ "package.json": JSON.stringify({ private: true, type: "module" }), "index.html": await html("/src/main.js") }),
    modes: {
      dev: async (dir) => {
        const port = await freePort();
        const origin = `http://${HOST}:${port}`;
        return { url: origin, stop: await devServer(dir, bin(dir, "vite"), ["--host", HOST, "--port", String(port), "--strictPort"], origin) };
      },
      build: async (dir) => {
        await build(dir, bin(dir, "vite"), ["build"]);
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
      "build, assets on another origin": async (dir) => {
        const assets = await serveDir(path.join(dir, "dist"), { cors: true });
        await build(dir, bin(dir, "vite"), ["build", "--base", `${assets.origin}/`]);
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: () => (server.close(), assets.close()) };
      },
    },
  },
  webpack: {
    packages: ["webpack", "webpack-cli", "webpack-dev-server"],
    files: async () => ({ "package.json": JSON.stringify({ private: true }) }),
    modes: {
      dev: async (dir) => {
        const port = await freePort();
        const origin = `http://${HOST}:${port}`;
        await mkdir(path.join(dir, "public"), { recursive: true });
        await writeFile(path.join(dir, "public/index.html"), await html("/main.js"));
        await writeFile(path.join(dir, "webpack.config.js"), WEBPACK_CONFIG(port));
        return { url: origin, stop: await devServer(dir, bin(dir, "webpack"), ["serve", "--mode", "development"], origin) };
      },
      build: async (dir) => {
        await writeFile(path.join(dir, "webpack.config.js"), WEBPACK_CONFIG(0));
        await build(dir, bin(dir, "webpack"), ["--mode", "production"]);
        await writeFile(path.join(dir, "dist/index.html"), await html("./main.js"));
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
      "build, assets on another origin": async (dir) => {
        const assets = await serveDir(path.join(dir, "dist"), { cors: true });
        await writeFile(path.join(dir, "webpack.config.js"), WEBPACK_CONFIG(0, `${assets.origin}/`));
        await build(dir, bin(dir, "webpack"), ["--mode", "production"]);
        await writeFile(path.join(dir, "dist/index.html"), await html(`${assets.origin}/main.js`));
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: () => (server.close(), assets.close()) };
      },
    },
  },
  rollup: {
    packages: ["rollup", "@rollup/plugin-node-resolve", "@web/rollup-plugin-import-meta-assets"],
    files: async () => ({ "package.json": JSON.stringify({ private: true, type: "module" }), "rollup.config.js": ROLLUP_CONFIG }),
    modes: {
      build: async (dir) => {
        await build(dir, bin(dir, "rollup"), ["-c"]);
        await writeFile(path.join(dir, "dist/index.html"), await html("./main.js"));
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
    },
  },
  esbuild: {
    packages: ["esbuild"],
    files: async () => ({ "package.json": JSON.stringify({ private: true, type: "module" }) }),
    modes: {
      "build, files copied": async (dir) => {
        await build(dir, bin(dir, "esbuild"), ["src/main.js", "--bundle", "--format=esm", "--minify", "--outfile=dist/main.js"]);
        const lib = path.join(dir, "node_modules/mbt-map/dist");
        for (const f of await readdir(lib)) if (ESBUILD_COPIES.test(f)) await copyFile(path.join(lib, f), path.join(dir, "dist", f));
        await writeFile(path.join(dir, "dist/index.html"), await html("./main.js"));
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
    },
  },
  parcel: {
    packages: ["parcel"],
    files: async () => ({ "package.json": JSON.stringify(PARCEL_PACKAGE), "src/index.html": await html("./main.js") }),
    modes: {
      dev: async (dir) => {
        const port = await freePort();
        const origin = `http://${HOST}:${port}`;
        return { url: origin, stop: await devServer(dir, bin(dir, "parcel"), ["serve", "--host", HOST, "--port", String(port), "--no-cache"], origin) };
      },
      build: async (dir) => {
        await build(dir, bin(dir, "parcel"), ["build", "--no-cache"]);
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
      "build, library served unbundled": async (dir) => {
        const app = await readFile(path.join(APP, "main.js"), "utf8");
        const imports = /^(import .* from "mbt-map.*";\n)+/m;
        if (!imports.test(app)) throw new Error("app/main.js has no mbt-map imports to replace");
        await writeFile(path.join(dir, "src/main.js"), app.replace(imports, UNBUNDLED_IMPORTS));
        await build(dir, bin(dir, "parcel"), ["build", "--no-cache"]);
        await cp(path.join(dir, "node_modules/mbt-map/dist"), path.join(dir, "dist/mbt-map"), { recursive: true });
        const server = await serveDir(path.join(dir, "dist"));
        return { url: server.origin, stop: server.close };
      },
    },
  },
};

/** Opens the app and reads its result: every step answered, the circle is on screen and no request failed. */
async function drive(browser, url) {
  const page = await browser.newPage({ viewport: { width: 600, height: 400 } });
  const failed = new Set();
  const workers = new Set();
  page.on("pageerror", (e) => failed.add(`pageerror: ${e.message}`.slice(0, 300)));
  page.on("worker", (w) => workers.add(w.url().startsWith("blob:") ? "blob:" : new URL(w.url()).pathname));
  page.on("response", (r) => r.status() >= 400 && !r.url().endsWith("/favicon.ico") && failed.add(`${r.status()} ${new URL(r.url()).pathname}`));
  try {
    await page.goto(url, { waitUntil: "load" });
    await page.waitForFunction(() => window.__result, null, { timeout: 90_000 });
    const result = await page.evaluate(() => window.__result);
    const { width, rgba: data } = decodePng(await page.screenshot());
    const at = (300 + 200 * width) * 4;
    const drawn = data[at] > 150 && data[at + 1] < 60 && data[at + 2] < 60;
    const problems = [...result.errors, ...failed];
    if (result.map !== "idle") problems.push("the map did not go idle");
    if (!drawn) problems.push(`the circle is not drawn: rgb ${data[at]}, ${data[at + 1]}, ${data[at + 2]} at the center`);
    if (JSON.stringify(result.query) !== '["a","b"]') problems.push(`query: ${JSON.stringify(result.query)}`);
    if (JSON.stringify(result.analysis) !== "[139.765,35.675]") problems.push(`analysis: ${JSON.stringify(result.analysis)}`);
    if (result.geodesic !== 768) problems.push(`geodesic: ${result.geodesic}`);
    if (JSON.stringify(result.data) !== "[139.767,35.685]") problems.push(`data: ${JSON.stringify(result.data)}`);
    return { ok: problems.length === 0, problems, workers: [...workers].sort() };
  } catch (e) {
    return { ok: false, problems: [e.message.slice(0, 300), ...failed], workers: [...workers].sort() };
  } finally {
    await page.close();
  }
}

const only = arg("only")?.split(",");
const unknown = (only ?? []).filter((name) => !(name in BUNDLERS));
if (unknown.length) throw new Error(`bundlers: no bundler named ${unknown.join(", ")}`);
if (!process.argv.includes("--no-build")) execFileSync("npm", ["run", "-s", "build"], { cwd: path.join(ROOT, "npm"), stdio: ["ignore", "ignore", "inherit"] });
const tmp = await mkdtemp(path.join(os.tmpdir(), "mbt-map-bundlers-"));
const [{ filename }] = JSON.parse(execFileSync("npm", ["pack", "--json", "--pack-destination", tmp], { cwd: path.join(ROOT, "npm") }).toString());
const tarball = path.join(tmp, filename);
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const rows = [];
try {
  for (const [name, bundler] of Object.entries(BUNDLERS)) {
    if (only && !only.includes(name)) continue;
    const version = bundler.packages.map((p) => `${p} ${VERSIONS[p]}`).join(", ");
    let dir = null;
    for (const [mode, start] of Object.entries(bundler.modes)) {
      const row = { bundler: name, mode, version, ok: false, known: KNOWN_FAILURES.includes(`${name} ${mode}`), problems: [], workers: [] };
      rows.push(row);
      let stop = () => {};
      try {
        dir ??= await project(tmp, name, tarball, bundler.packages, await bundler.files());
        const started = await start(dir);
        stop = started.stop;
        Object.assign(row, await drive(browser, started.url));
      } catch (e) {
        row.problems.push(e.message.slice(0, 900));
      } finally {
        stop();
      }
      console.log(`${row.ok ? "ok  " : row.known ? "fails as known" : "FAIL"} ${name} ${mode}${row.ok ? "" : `: ${row.problems.join("; ")}`}`);
    }
  }
} finally {
  await browser.close();
  if (process.argv.includes("--keep")) console.log(`projects kept in ${tmp}`);
  else await rm(tmp, { recursive: true, force: true });
}
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/bundlers.json"), `${JSON.stringify({ env: { browser: "chromium", node: process.version, platform: process.platform }, rows }, null, 2)}\n`);
console.log("\n| bundler | mode | result |\n|---|---|---|");
for (const r of rows) console.log(`| ${r.version} | ${r.mode} | ${r.ok ? "ok" : `fails${r.known ? " (known)" : ""}: ${r.problems[0]}`} |`);
const surprises = rows.filter((r) => r.ok === r.known);
if (surprises.length) {
  console.error(`bundlers: ${surprises.map((r) => `${r.bundler} ${r.mode} ${r.ok ? "works now (update KNOWN_FAILURES and the docs)" : "fails"}`).join("; ")}`);
  process.exit(1);
}
