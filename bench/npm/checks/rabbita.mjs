// examples/rabbita with ?local=1: the rabbita app (MoonBit, t-ujiie-g/mbtmap_rabbita) opens OpenFreeMap's
// Liberty at Tokyo (the fixtures' tiles), switches the labels' language, flies, names the city clicked,
// raises the buildings and swaps the base map to GSI and back, all through the typed MoonBit API.

const ZH = ["coalesce", ["get", "name:zh-Hans"], ["get", "name:zh"], ["get", "name"]];
const JA = ["coalesce", ["get", "name:ja"], ["get", "name"]];
const RAISED = ["get", "render_height"];

const text = (page, selector) => page.evaluate((s) => document.querySelector(s)?.textContent ?? null, selector);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// What the map's style says now: its sources and the properties the app changes.
const drawn = (page) =>
  page.evaluate(() => {
    const style = document.querySelector("mbt-map").map.getStyle();
    const layer = (id) => style.layers.find((l) => l.id === id);
    return {
      sources: Object.keys(style.sources).sort(),
      city: layer("label_city")?.layout?.["text-field"] ?? null,
      cities: layer("city-names")?.layout?.["text-field"] ?? null,
      shield: layer("highway-shield-non-us")?.layout?.["text-field"] ?? null,
      height: layer("building-3d")?.paint?.["fill-extrusion-height"] ?? null,
    };
  });

async function until(page, what, test) {
  for (let i = 0; i < 100; i++) {
    const now = await what();
    if (test(now)) return now;
    await page.waitForTimeout(100);
  }
  return what();
}

async function fly(page, key, place) {
  await page.click(`#go-${key}`);
  await page.waitForFunction((place) => document.getElementById("camera").textContent.startsWith(place), place, { timeout: 15000 });
  return text(page, "#camera");
}

export async function rabbitaChecks(page) {
  const style = () => drawn(page);
  const first = await style();
  const before = await text(page, "#camera");

  await page.click("#labels-ja");
  const japanese = await until(page, style, (s) => same(s.city, JA));

  const osaka = await fly(page, "osaka", "135.49590, 34.70250");
  const tokyo = await fly(page, "tokyo", "139.76710, 35.68120");

  const box = await page.locator("mbt-map").boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForFunction(() => document.querySelector("#feature .name"), null, { timeout: 15000 });
  const clicked = { name: await text(page, "#feature .name"), about: await text(page, "#feature dl") };

  await page.click("#buildings");
  const raised = await until(page, style, (s) => same(s.height, RAISED));
  await page.waitForFunction(() => document.getElementById("camera").textContent.endsWith("pitch 60°"), null, { timeout: 15000 });
  const pitched = await text(page, "#camera");

  await page.click("#base-gsi");
  const gsi = await until(page, style, (s) => s.sources.includes("gsi"));
  const disabled = await page.evaluate(() => document.getElementById("buildings").disabled);
  await page.click("#base-openfreemap");
  const back = await until(page, style, (s) => s.sources.includes("openmaptiles"));

  const ok =
    before === "Move the map to see the camera." &&
    same(first.sources, ["cities", "openmaptiles"]) &&
    same(first.city, ZH) && same(first.cities, ZH) && same(first.height, 0) &&
    same(japanese.city, JA) && same(japanese.cities, JA) && same(japanese.shield, ["to-string", ["get", "ref"]]) &&
    osaka.includes("zoom 15.00") && tokyo.includes("zoom 15.00") &&
    clicked.name === "東京" && clicked.about === "LayercitiesKindcity" &&
    same(raised.height, RAISED) && pitched.endsWith("pitch 60°") &&
    same(gsi.sources, ["cities", "gsi"]) && same(gsi.cities, JA) && disabled === true &&
    same(back.city, JA) && same(back.height, RAISED);
  return [ok, { first, before, japanese, osaka, tokyo, clicked, raised, pitched, gsi, disabled, back }];
}
