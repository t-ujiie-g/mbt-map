// The MoonBit API (mooncakes t-ujiie-g/mbtmap) from a MoonBit app (bench/moonbit/app): a map made
// with a JSON style, a source and a layer added on load, a query on idle, paint and camera changes,
// a listener taken off. The app writes what it saw to window.__moonbit.result.

export async function moonbitChecks(page) {
  await page.waitForFunction(() => window.__moonbit?.result, null, { timeout: 30000 });
  const r = await page.evaluate(() => window.__moonbit.result);
  const ok =
    JSON.stringify(r.layers) === JSON.stringify(["background", "places"]) &&
    Math.abs(r.point[0] - 400) < 1 && Math.abs(r.point[1] - 300) < 1 &&
    JSON.stringify(r.features) === JSON.stringify(["東京駅"]) &&
    JSON.stringify(r.layer) === JSON.stringify(["places"]) &&
    r.paint?.["circle-color"] === "#0000ff" && r.paint?.["circle-radius"] === 20 &&
    r.zoom === 15.5 && r.bearing === 10 &&
    Math.abs(r.center[0] - 139.7671) < 1e-9 && Math.abs(r.center[1] - 35.6812) < 1e-9 &&
    r.moved === true && r.movesAfterOff === 0;
  return [ok, r];
}
