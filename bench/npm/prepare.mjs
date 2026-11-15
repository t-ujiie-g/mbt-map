// Builds and packs npm/, installs the tarball into the examples and the test
// pages that use it and builds the React example. Usage: node npm/prepare.mjs
import { execFileSync } from "node:child_process";
import { build } from "esbuild";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROOT } from "../lib/root.mjs";

const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: ["ignore", "pipe", "inherit"] }).toString();

export async function prepareExamples() {
  const out = path.join(ROOT, "bench/dist/pack");
  run("npm", ["run", "-s", "build"], path.join(ROOT, "npm"));
  await rm(out, { recursive: true, force: true });
  await mkdir(out, { recursive: true });
  const [{ filename, files }] = JSON.parse(run("npm", ["pack", "--json", "--pack-destination", out], path.join(ROOT, "npm")));
  console.log(`${filename}: ${files.map((f) => f.path).join(", ")}`);
  const install = async (dir) => {
    const modules = path.join(ROOT, dir, "node_modules/mbt-map");
    await rm(modules, { recursive: true, force: true });
    await mkdir(modules, { recursive: true });
    run("tar", ["xzf", path.join(out, filename), "--strip-components=1", "-C", modules], ROOT);
  };
  for (const page of ["npm", "element", "geojson", "analysis", "data", "media", "custom", "model", "tiles", "pointcloud", "i3s", "globe", "services", "moonbit"]) await install(`bench/npm/pages/${page}`);
  // The MoonBit app the moonbit page runs, on the MoonBit API (moonbit/mbtmap).
  run("moon", ["build", "--target", "js", "--release", "bench/moonbit/app"], ROOT);
  await install("examples/html");
  await install("examples/element");
  await install("examples/plateau");
  // The rabbita example: its MoonBit app built and minified next to its page.
  await install("examples/rabbita");
  run("moon", ["build", "--target", "js", "--release", "examples/rabbita/main"], ROOT);
  await build({
    entryPoints: [path.join(ROOT, "_build/js/release/build/t-ujiie-g/mbtmap_rabbita_example/main/main.js")],
    outfile: path.join(ROOT, "examples/rabbita/app.js"),
    format: "esm",
    minify: true,
    logLevel: "warning",
  });
  // npm ci empties node_modules, so the tarball goes in afterwards.
  run("npm", ["ci", "--no-audit", "--no-fund"], path.join(ROOT, "examples/react"));
  await install("examples/react");
  run("npm", ["run", "-s", "build"], path.join(ROOT, "examples/react"));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  await prepareExamples();
}
