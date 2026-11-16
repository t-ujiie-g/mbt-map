// bench/npm/pages/touch on a phone-sized touch screen: `touch-action` by the enabled handlers, the wheel, the
// canvases' names, `render-world-copies`. In Chromium real touches (CDP's Input.dispatchTouchEvent) pinch and drag
// the maps without zooming or scrolling the page; other browsers have no such input, so that part is skipped.
const VIEWPORT = { width: 400, height: 700 };

const state = (page) =>
  page.evaluate(() => {
    const el = document.querySelector("mbt-map");
    const of = (map) => ({ zoom: map.getZoom(), lat: map.getCenter().lat, action: getComputedStyle(map.getCanvas()).touchAction });
    return { map: of(window.__map), element: of(el.map), scale: window.visualViewport.scale, scrollY: window.scrollY };
  });

const still = (page) => page.waitForFunction(() => !window.__map.isMoving() && !document.querySelector("mbt-map").map.isMoving());

/** Touch gestures through CDP: fingers go down at `from`, move to `to` in steps and lift after the inertia buffer has emptied. */
async function gesture(cdp, page, from, to) {
  const points = (k) => from.map(([x, y], i) => ({ x: x + (to[i][0] - x) * k, y: y + (to[i][1] - y) * k, id: i }));
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: points(0) });
  for (let step = 1; step <= 8; step++) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: points(step / 8) });
    await page.waitForTimeout(16);
  }
  await page.waitForTimeout(250);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await still(page);
}

async function touches(page) {
  const cdp = await page.context().newCDPSession(page);
  const first = await state(page);
  // The map is at y 0 to 250, the element at 250 to 500, the plain box at 500 to 650.
  await gesture(cdp, page, [[180, 125], [220, 125]], [[80, 125], [320, 125]]);
  await gesture(cdp, page, [[180, 375], [220, 375]], [[80, 375], [320, 375]]);
  const pinched = await state(page);
  await gesture(cdp, page, [[200, 200]], [[200, 80]]);
  await gesture(cdp, page, [[200, 450]], [[200, 330]]);
  const dragged = await state(page);
  await page.evaluate(() => window.__map.dragPan.disable());
  await gesture(cdp, page, [[200, 200]], [[200, 80]]);
  const scrolled = await state(page);
  await page.evaluate(() => {
    window.__map.dragPan.enable();
    window.scrollTo(0, 0);
  });
  // The harness itself: the same pinch on a plain box does zoom the page.
  await gesture(cdp, page, [[180, 575], [220, 575]], [[80, 575], [320, 575]]);
  const plain = await state(page);
  const ok =
    pinched.scale === 1 && pinched.map.zoom > first.map.zoom + 1 && pinched.element.zoom > first.element.zoom + 1 &&
    dragged.scrollY === 0 && dragged.scale === 1 && dragged.map.lat < pinched.map.lat && dragged.element.lat < pinched.element.lat &&
    scrolled.scrollY > 50 && scrolled.map.lat === dragged.map.lat &&
    plain.scale > 1;
  return { ok, first, pinched, dragged, scrolled, plain: plain.scale };
}

export async function touchChecks(page, browserName) {
  const context = await page.context().browser().newContext({ viewport: VIEWPORT, hasTouch: true });
  try {
    const phone = await context.newPage();
    const errors = [];
    phone.on("pageerror", (e) => errors.push(e.message));
    await phone.goto(page.url());
    await phone.waitForFunction(() => window.__loaded, null, { timeout: 30000 });
    const actions = await phone.evaluate(async () => {
      const { Map } = await import("mbt-map");
      const map = window.__map;
      const action = (m = map) => getComputedStyle(m.getCanvas()).touchAction;
      const out = { both: action(), element: action(document.querySelector("mbt-map").map) };
      map.dragPan.disable();
      out.zoomOnly = action();
      map.touchZoomRotate.disable();
      out.pitchOnly = action();
      map.touchPitch.disable();
      out.neither = action();
      map.dragPan.enable();
      out.panOnly = action();
      map.touchZoomRotate.enable();
      map.touchPitch.enable();
      const div = document.createElement("div");
      div.style.cssText = "position:fixed;width:10px;height:10px";
      div.setAttribute("aria-label", "Overview");
      document.body.append(div);
      const fixed = new Map({ container: div, style: { version: 8, sources: {}, layers: [] }, interactive: false });
      await fixed.once("load");
      out.fixed = action(fixed);
      out.fixedLabel = fixed.getCanvas().getAttribute("aria-label");
      out.fixedTab = fixed.getCanvas().tabIndex;
      fixed.remove();
      div.remove();
      return out;
    });
    const named = await phone.evaluate(() => {
      const el = document.querySelector("mbt-map");
      const of = (canvas) => [canvas.getAttribute("role"), canvas.getAttribute("aria-label"), canvas.tabIndex];
      const out = { map: of(window.__map.getCanvas()), element: of(el.map.getCanvas()) };
      el.removeAttribute("aria-label");
      out.unnamed = el.map.getCanvas().getAttribute("aria-label");
      el.setAttribute("aria-label", "Tokyo Station");
      return out;
    });
    const copies = await phone.evaluate(() => {
      const el = document.querySelector("mbt-map");
      const out = { attribute: el.map.getRenderWorldCopies(), property: el.renderWorldCopies };
      el.setAttribute("render-world-copies", "true");
      out.changed = el.map.getRenderWorldCopies();
      el.setAttribute("render-world-copies", "yes");
      el.renderWorldCopies = 1;
      out.kept = el.renderWorldCopies;
      el.renderWorldCopies = false;
      out.set = el.map.getRenderWorldCopies();
      out.errors = window.__errors.splice(0);
      return out;
    });
    const before = await state(phone);
    await phone.mouse.move(200, 125);
    await phone.mouse.wheel(0, -300);
    await phone.waitForFunction((zoom) => window.__map.getZoom() > zoom && !window.__map.isMoving(), before.map.zoom);
    const wheeled = await state(phone);
    await phone.evaluate(() => window.__map.jumpTo({ zoom: 14.5 }));
    const touched = browserName === "chromium" ? await touches(phone) : { ok: true, skipped: `no CDP touch input (Input.dispatchTouchEvent) in ${browserName}` };
    const ok =
      actions.both === "none" && actions.element === "none" && actions.zoomOnly === "pan-x pan-y" && actions.pitchOnly === "pan-x pan-y" &&
      actions.neither === "auto" && actions.panOnly === "pinch-zoom" && actions.fixed === "auto" && actions.fixedLabel === "Overview" && actions.fixedTab === -1 &&
      JSON.stringify(named) === JSON.stringify({ map: ["region", "Map", 0], element: ["region", "Tokyo Station", 0], unnamed: "Map" }) &&
      copies.attribute === false && copies.property === false && copies.changed === true && copies.kept === true && copies.set === false &&
      copies.errors.length === 2 && copies.errors.every((e) => e.includes("invalid render-world-copies")) &&
      wheeled.scrollY === 0 && wheeled.map.zoom > before.map.zoom &&
      touched.ok && errors.length === 0;
    return [ok, { actions, named, copies, wheeled, touched, errors }];
  } finally {
    await context.close();
  }
}
