// Map padding (`setPadding`) moves the picture: mbt-map's frame under a padding against its frame
// without, moved by the padded center's offset, pixel by pixel where they overlap, on terrain, with
// extrusions and on the globe (bench/query/index.html). The center must be drawn at the padded center.
// Usage: node style/padding.mjs [--shots=dir]; writes bench/results/padding-golden.json.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { arg } from "../lib/args.mjs";
import { fujiTerrainStyle } from "../lib/fuji-terrain.mjs";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { SCENES } from "./scenes.mjs";

const [W, H] = [800, 600];
const LIMITS = { mean: 0.05, p99: 1, px: 1e-6 };
const VIEWS = {
  terrain: { style: await fujiTerrainStyle(), camera: { center: [138.7793, 35.3174], zoom: 11.8, bearing: 40, pitch: 60 } },
  extrusions: { style: SCENES["padding-extrusions"].style, camera: { center: [139.7671, 35.6812], zoom: 15.5, bearing: 30, pitch: 60 } },
  globe: { style: SCENES["padding-globe"].style, camera: { center: [120, 40], zoom: 2.5, bearing: 30, pitch: 45 } },
};
const PADDINGS = [{ top: 0, right: 0, bottom: 0, left: 320 }, { top: 200, right: 0, bottom: 0, left: 0 }, { top: 0, right: 100, bottom: 60, left: 0 }];

// An eased and a flown move to a padding end with it and with their center at the padded center, and
// a fit leaves the map's padding free (`relief`: not checked where the ground is not at sea level).
async function moves(page, camera, relief) {
  const r = await page.evaluate(async (camera) => {
    const mb = window.__mb;
    const ended = () => new Promise((done) => mb.once("moveend", done));
    const at = (p) => {
      const c = mb.project(p);
      return [c.x, c.y];
    };
    let end = ended();
    mb.easeTo({ padding: { top: 0, right: 0, bottom: 0, left: 0 }, duration: 150, essential: true });
    await end;
    const eased = mb.getPadding();
    end = ended();
    mb.flyTo({ center: camera.center, zoom: camera.zoom - 0.5, padding: { left: 200 }, duration: 200, essential: true });
    await end;
    const flown = { padding: mb.getPadding(), center: at(mb.getCenter()) };
    const [lng, lat] = camera.center;
    const box = [[lng - 0.02, lat - 0.01], [lng + 0.02, lat + 0.01]];
    mb.jumpTo({ pitch: 0, bearing: 0, padding: { left: 320, top: 100, right: 0, bottom: 0 } });
    end = ended();
    mb.fitBounds(box, { duration: 0 });
    await end;
    return { eased, flown, fit: [at(box[0]), at(box[1])], padding: mb.getPadding() };
  }, camera);
  const [[x0, y0], [x1, y1]] = r.fit;
  const inside = Math.min(x0, x1) >= 320 - 1e-6 && Math.max(x0, x1) <= W + 1e-6 && Math.min(y0, y1) >= 100 - 1e-6 && Math.max(y0, y1) <= H + 1e-6;
  const px = Math.max(Math.abs(r.flown.center[0] - (W / 2 + 100)), Math.abs(r.flown.center[1] - H / 2));
  const kept = JSON.stringify(r.eased) === JSON.stringify({ top: 0, right: 0, bottom: 0, left: 0 }) && JSON.stringify(r.flown.padding) === JSON.stringify({ top: 0, right: 0, bottom: 0, left: 200 }) && r.padding.left === 320;
  return { ok: kept && (inside || relief) && px <= LIMITS.px, mean: 0, p99: 0, "center px": px, getPadding: kept };
}

const shots = arg("shots");
const dir = "bench/dist/style";
await mkdir(path.join(ROOT, dir), { recursive: true });
if (shots) await mkdir(shots, { recursive: true });
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
try {
  for (const [name, view] of Object.entries(VIEWS)) {
    const file = `${dir}/padding-${name}.json`;
    await writeFile(path.join(ROOT, file), JSON.stringify(view.style));
    const page = await browser.newPage({ viewport: { width: W, height: 2 * H }, deviceScaleFactor: 1 });
    page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
    await page.goto(`${origin}/bench/query/index.html?style=/${file}&camera=${encodeURIComponent(JSON.stringify(view.camera))}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    const shot = async (label) => {
      const png = await page.screenshot({ clip: { x: 0, y: 0, width: W, height: H } });
      if (shots) await writeFile(path.join(shots, `padding-${name}-${label}.png`), png);
      return decodePng(png).rgba;
    };
    const plain = await shot("plain");
    for (const padding of PADDINGS) {
      const state = await page.evaluate(async (p) => {
        const mb = window.__mb;
        const idle = mb.once("idle");
        mb.setPadding(p);
        await idle;
        await new Promise((r) => setTimeout(r, 300));
        const c = mb.project(mb.getCenter());
        return { padding: mb.getPadding(), center: [c.x, c.y] };
      }, padding);
      const moved = await shot(`${padding.top}-${padding.right}-${padding.bottom}-${padding.left}`);
      const [dx, dy] = [(padding.left - padding.right) / 2, (padding.top - padding.bottom) / 2];
      const diffs = [];
      for (let y = Math.max(0, dy); y < Math.min(H, H + dy); y++) {
        for (let x = Math.max(0, dx); x < Math.min(W, W + dx); x++) {
          const [i, j] = [(y * W + x) * 4, ((y - dy) * W + x - dx) * 4];
          for (let c = 0; c < 3; c++) diffs.push(Math.abs(moved[i + c] - plain[j + c]));
        }
      }
      diffs.sort((a, b) => a - b);
      const mean = diffs.reduce((s, d) => s + d, 0) / diffs.length;
      const p99 = diffs[Math.floor(diffs.length * 0.99)];
      const px = Math.max(Math.abs(state.center[0] - (W / 2 + dx)), Math.abs(state.center[1] - (H / 2 + dy)));
      const kept = JSON.stringify(state.padding) === JSON.stringify(padding);
      results.push({ view: name, padding: `${padding.top},${padding.right},${padding.bottom},${padding.left}`, ok: kept && mean <= LIMITS.mean && p99 <= LIMITS.p99 && px <= LIMITS.px, mean: Number(mean.toFixed(3)), p99, "center px": px, getPadding: kept });
    }
    results.push({ view: name, padding: "moves", ...(await moves(page, view.camera, name === "terrain")) });
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
console.table(results);
await writeFile(path.join(ROOT, "bench/results/padding-golden.json"), `${JSON.stringify({ env: { browser: "chromium", viewport: `${W}x${H}` }, limits: LIMITS, results }, null, 2)}\n`);
if (results.some((r) => !r.ok)) process.exitCode = 1;
