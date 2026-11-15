// examples/samples: every sample of index.json opens, draws a map canvas and throws nothing for a few seconds.
// The samples read live services (GSI, OpenFreeMap, PLATEAU); tiles that fail to load (CI) are not errors here.
import { fakeGeolocation } from "../../lib/fake-geolocation.mjs";
import { watchErrors } from "./step.mjs";

export async function samplesChecks(page) {
  const samples = await page.evaluate(async () => (await fetch("./index.json")).json());
  const base = page.url();
  const results = {};
  // Each sample gets a page of its own, closed after it: WebKit fails a worker still loading when the page
  // navigates away (the ArcGIS sample's, after its live query), which would land on the next sample.
  for (const { id } of samples) {
    const own = await page.context().browser().newPage({ viewport: page.viewportSize() });
    const { errors, settled } = watchErrors(own);
    await own.addInitScript(fakeGeolocation);
    await own.goto(new URL(`./${id}/`, base).href);
    const canvas = await own.waitForSelector("canvas", { timeout: 20000 }).then(() => true, () => false);
    await own.waitForTimeout(2500);
    await settled();
    await own.close();
    results[id] = canvas && errors.length === 0 ? "ok" : { canvas, errors: errors.slice() };
  }
  return [Object.values(results).every((r) => r === "ok"), results];
}
