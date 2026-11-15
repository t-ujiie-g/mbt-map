// The MoonBit API (mooncakes t-ujiie-g/mbtmap) from a MoonBit app (bench/moonbit/app): every method of `Map`,
// the events and queries (an unknown layer's included), then a click on the station, a restyle and `remove`.

export async function moonbitChecks(page) {
  await page.waitForFunction(() => window.__moonbit?.result && window.__moonbit?.more, null, { timeout: 30000 });
  const { result: r, more: m } = await page.evaluate(() => window.__moonbit);
  const first =
    JSON.stringify(r.layers) === JSON.stringify(["background", "places"]) &&
    Math.abs(r.point[0] - 400) < 1 && Math.abs(r.point[1] - 300) < 1 &&
    JSON.stringify(r.features) === JSON.stringify(["東京駅"]) &&
    JSON.stringify(r.layer) === JSON.stringify(["places"]) &&
    r.paint?.["circle-color"] === "#0000ff" && r.paint?.["circle-radius"] === 20 &&
    r.zoom === 15.5 && r.bearing === 10 &&
    Math.abs(r.center[0] - 139.7671) < 1e-9 && Math.abs(r.center[1] - 35.6812) < 1e-9 &&
    r.moved === true && r.movesAfterOff === 0;
  const place = m.places[0] ?? {};
  const state = await page.evaluate(() => window.__mbtmap.getFeatureState({ source: "places", id: 1 }));
  const second =
    JSON.stringify(m.moved) === JSON.stringify(["background", "extra", "places"]) &&
    JSON.stringify(m.removed) === JSON.stringify(["background", "places"]) &&
    m.sourceAdded === true && m.sourceRemoved === true &&
    place.layout?.["circle-sort-key"] === 1 &&
    JSON.stringify(place.filter) === JSON.stringify(["==", ["get", "kind"], "駅"]) &&
    m.pitch === 30 && m.eased === 16 &&
    Math.abs(m.fitted[0] - 139.765) < 1e-6 && Math.abs(m.fitted[1] - 35.68) < 1e-3 &&
    Math.abs(m.back[0] - 139.7671) < 1e-7 && Math.abs(m.back[1] - 35.6812) < 1e-7 &&
    state?.selected === true;
  // A click on the station: `on_layer` gets it, then the app restyles and removes the map.
  let clicked = null;
  for (let i = 0; i < 20 && !clicked; i++) {
    const p = await page.evaluate(() => window.__mbtmap.project([139.7671, 35.6812]));
    const box = await page.locator("#map").boundingBox();
    await page.mouse.click(box.x + p.x, box.y + p.y);
    await page.waitForTimeout(250);
    clicked = await page.evaluate(() => window.__moonbit.clicked ?? null);
  }
  const unknownLayer = await page.evaluate(() => window.__moonbit.unknownLayer ?? null);
  const restyled = await page.evaluate(() => window.__moonbit.restyled ?? null);
  const canvases = await page.evaluate(() => document.querySelectorAll("#map canvas").length);
  const last = JSON.stringify(clicked) === JSON.stringify(["東京駅"]) && JSON.stringify(restyled) === JSON.stringify(["background"]) && canvases === 0 && unknownLayer === 0;
  return [first && second && last, { ...r, more: m, state, clicked, restyled, canvases, unknownLayer }];
}
