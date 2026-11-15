// Screen checks of the pack test: pixels read from screenshots, and pins placed over the map.
import { decodePng } from "../../lib/png.mjs";

/** Whether a pin's `translate(xpx, ypx)` puts it at the 800 x 600 page's centre. */
export function atCentre(transform) {
  return translatedTo(transform, 400, 300);
}

/** Whether a CSS `translate(xpx, ypx)` moves to (x, y), within 0.01 px: WebKit gives the values back rounded. */
export function translatedTo(transform, x, y) {
  const m = /^translate\(([-\d.e]+)px, ([-\d.e]+)px\)$/.exec(transform ?? "");
  return !!m && Math.abs(Number(m[1]) - x) < 0.01 && Math.abs(Number(m[2]) - y) < 0.01;
}

// WebKit on Linux shows a WebGL canvas made with `antialias: false` one frame late (a bare canvas cleared once does
// the same), so there the map draws its frame again before the screen is read.
const LATE = process.platform === "linux";

async function present(page) {
  if (!LATE || page.context().browser()?.browserType().name() !== "webkit") return;
  await page.evaluate(() => {
    const map = window.__map ?? document.querySelector("mbt-map")?.map;
    if (!map?.triggerRepaint) return;
    const drawn = map.once("render");
    map.triggerRepaint();
    return drawn.then(() => new Promise((done) => requestAnimationFrame(() => done())));
  });
}

/** `page.screenshot(options)` once the map's last frame is on screen. */
export async function screenshot(page, options) {
  await present(page);
  return page.screenshot(options);
}

/** The colour of screen pixel (x, y), read from a screenshot. */
export async function pixel(page, x, y) {
  const { rgba } = decodePng(await screenshot(page, { clip: { x: Math.round(x), y: Math.round(y), width: 1, height: 1 } }));
  return [rgba[0], rgba[1], rgba[2]];
}

/** The share of the page's pixels that have its commonest colour. */
export async function commonestShare(page) {
  const { rgba } = decodePng(await screenshot(page));
  const counts = new Map();
  for (let i = 0; i < rgba.length; i += 4) {
    const key = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return Math.max(...counts.values()) / (rgba.length / 4);
}

/** Whether two colours differ by at most `d` in each channel. */
export const near = (rgb, want, d = 3) => rgb.every((v, i) => Math.abs(v - want[i]) <= d);
