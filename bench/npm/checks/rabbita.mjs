// examples/rabbita with ?local=1: the rabbita app (MoonBit, t-ujiie-g/moonmap_rabbita) flies with its buttons
// and shows the camera from moon-map-moveend, names the station clicked (a query from update) and changes
// a paint property through the typed API.

const text = (page, id) => page.evaluate((id) => document.getElementById(id).textContent, id);

async function go(page, name, zoom) {
  await page.getByRole("button", { name, exact: true }).click();
  await page.waitForFunction((zoom) => document.getElementById("camera").textContent.includes(`ズーム ${zoom}`), zoom, { timeout: 15000 });
  return text(page, "camera");
}

export async function rabbitaChecks(page) {
  const before = await text(page, "camera");
  const fuji = await go(page, "富士山", "11.50");
  const tokyo = await go(page, "東京駅", "15.00");
  const box = await page.locator("moon-map").boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForFunction(() => document.getElementById("clicked").textContent.includes("（"), null, { timeout: 15000 });
  const clicked = await text(page, "clicked");
  await page.click("#resize");
  await page.waitForFunction(() => document.getElementById("resize").textContent === "点を小さく");
  const radius = await page.evaluate(() => {
    const el = document.querySelector("moon-map");
    return new Promise((done) => el.map.once("idle", () => done(el.map.getPaintProperty("stations", "circle-radius"))));
  });
  const ok =
    before === "地図を動かすと中心が出ます" &&
    fuji.includes("138.72740, 35.36060") &&
    tokyo.includes("139.76710, 35.68120") &&
    clicked.startsWith("クリック 139.767") && clicked.endsWith("（東京駅）") &&
    JSON.stringify(radius) === JSON.stringify(["interpolate", ["linear"], ["zoom"], 10, 14 / 3, 16, 14]);
  return [ok, { before, fuji, tokyo, clicked, radius }];
}
