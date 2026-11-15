// examples/samples: every sample of index.json opens, draws a map canvas and throws nothing for a few seconds.
// The samples read live services (GSI, OpenFreeMap, PLATEAU); tiles that fail to load (CI) are not errors here.

export async function samplesChecks(page) {
  const samples = await page.evaluate(async () => (await fetch("./index.json")).json());
  const base = page.url();
  const results = {};
  for (const { id } of samples) {
    const errors = [];
    const onError = (e) => errors.push(e.message);
    page.on("pageerror", onError);
    await page.goto(new URL(`./${id}/`, base).href);
    const canvas = await page.waitForSelector("canvas", { timeout: 20000 }).then(() => true, () => false);
    await page.waitForTimeout(2500);
    page.off("pageerror", onError);
    results[id] = canvas && errors.length === 0 ? "ok" : { canvas, errors };
  }
  return [Object.values(results).every((r) => r === "ok"), results];
}
