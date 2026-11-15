// bench/npm/pages/cdn: the package loaded from another origin, as from a CDN; its workers start through
// same-origin blobs that import them (urls.ts `workerScriptUrl`): the map draws, queries and analyses.

export async function cdnChecks(page) {
  await page.waitForFunction(() => window.__cdn, null, { timeout: 30000 });
  const r = await page.evaluate(() => window.__cdn);
  const ok =
    new URL(r.module).origin !== new URL(page.url()).origin &&
    JSON.stringify(r.names) === JSON.stringify(["東京駅"]) &&
    Math.abs(r.centroid[0] - 139.7671) < 1e-9 && Math.abs(r.centroid[1] - 35.6812) < 1e-9;
  return [ok, r];
}
