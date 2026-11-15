// The glyph atlas over a long session: OpenFreeMap's Liberty on the ofm-planet fixture with a GeoJSON
// layer whose CJK labels change at each step (bench/labels/atlas-page.mjs), thousands of distinct
// characters in all. Fails when the engine warns that the atlas is full, or when the last step drawn
// after the others differs from the same step drawn in a fresh page.
// Usage: node labels/atlas.mjs [--steps=n] [--chars=n] [--shots=dir]. Needs `npm --prefix npm run build`.
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { arg } from "../lib/args.mjs";

const steps = Number(arg("steps") ?? 20);
const chars = Number(arg("chars") ?? 600);
// Pixels whose channels may differ by more than 8 between the two shots: 1%, since the pages
// differ by a few hundred along building edges after the steps; labels missing characters
// made 27000 before the atlas was rebuilt.
const MAX_DIFFERENT = 4800;

const { server, origin } = await serve();
const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
try {
  const open = async (step) => {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    const warnings = [];
    page.on("console", (m) => { if (m.type() === "warning" || m.type() === "error") warnings.push(m.text()); });
    page.on("pageerror", (e) => warnings.push(String(e)));
    await page.goto(`${origin}/bench/labels/atlas.html?step=${step}&chars=${chars}`);
    await page.waitForFunction(() => window.__ready === true, null, { timeout: 120_000 });
    return { page, warnings };
  };
  const long = await open(0);
  const t0 = Date.now();
  for (let k = 1; k < steps; k++) await long.page.evaluate((k) => window.__step(k), k);
  const elapsed = Date.now() - t0;
  const fresh = await open(steps - 1);
  const shot = (page) => page.evaluate(async () => {
    const bitmap = await createImageBitmap(await window.__map.toBlob());
    const c = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
    c.drawImage(bitmap, 0, 0);
    return Array.from(c.getImageData(0, 0, bitmap.width, bitmap.height).data);
  });
  const [a, b] = await Promise.all([shot(long.page), shot(fresh.page)]);
  const shots = arg("shots");
  if (shots) {
    await long.page.locator("#map").screenshot({ path: `${shots}/long.png` });
    await fresh.page.locator("#map").screenshot({ path: `${shots}/fresh.png` });
  }
  let different = 0;
  for (let i = 0; i < a.length; i += 4) {
    if (Math.max(Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]), Math.abs(a[i + 2] - b[i + 2])) > 8) different++;
  }
  const full = long.warnings.filter((w) => w.includes("atlas is full"));
  console.log(`${steps} steps x ${chars} characters in ${elapsed} ms; atlas-full warnings: ${full.length}; pixels apart from a fresh page: ${different}`);
  for (const w of new Set([...long.warnings, ...fresh.warnings])) console.log(`  ${w}`);
  if (full.length || different > MAX_DIFFERENT) process.exitCode = 1;
} finally {
  await browser.close();
  server.close();
}
